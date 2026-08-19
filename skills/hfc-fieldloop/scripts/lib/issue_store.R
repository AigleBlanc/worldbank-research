# Single source of truth for "where does issue_tracking.xlsx live, right now."
# The configured OneDrive output folder (skills/hfc-fieldloop/config.json's
# onedrive_output_dir) is REQUIRED and is the SOLE store — there is no
# separate local-only copy in the product. onedrive_output_dir points at a
# folder something outside this skill (in practice, the OneDrive desktop
# app) already keeps synced to the cloud, so every read/write here is plain
# filesystem I/O — see scripts/lib/sync_fpaths.R for the small amount of
# primitive logic (config loading, folder creation, report copy) this file
# builds on.
#
# Subfolders alongside the live file, inside the same synced folder:
#   intermediate/<YYYYMMDD>_issue_tracking.xlsx   — one per setup-build run
#   resolutions/<YYYYMMDD>_issues_resolution.xlsx — one working clone per
#                                                    "Process HFC feedback" day
# NOTE naming collision: this "intermediate/" (tracking snapshots) is
# unrelated to data/intermediate/ (fixed microdata, sibling of the
# configured input_data_dir — see write_intermediate() in utils.R) — always
# use the qualified path when referring to either.

# Resolve where the live file lives right now — the configured OneDrive
# output folder — computed once per script invocation and threaded through
# the read/write calls below so a script only resolves this once.
resolve_tracking_ctx <- function(skill_dir = NULL) {
  if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess()
  cfg <- load_fieldloop_config(skill_dir)
  if (!isTRUE(cfg$found)) {
    return(list(ready = FALSE, cfg = cfg, local_dir = NA_character_, reason = cfg$reason %||% "config_unavailable"))
  }
  ensure_local_folder(cfg$onedrive_output_dir)
  if (!dir.exists(cfg$onedrive_output_dir)) {
    return(list(ready = FALSE, cfg = cfg, local_dir = NA_character_, reason = "onedrive_output_dir_not_creatable"))
  }
  list(ready = TRUE, cfg = cfg, local_dir = cfg$onedrive_output_dir, reason = "ok")
}

#' Hard-require that config.json is fully configured and its OneDrive output
#' folder is reachable before doing any real work — the product has no
#' local-only path. Every user-facing entry point (the CLI scripts under
#' scripts/) calls this immediately after resolving the skill dir, before
#' anything else. Returns the resolved ctx (always ready == TRUE) on
#' success; stop()s with setup instructions otherwise.
require_fieldloop_config_ready <- function(skill_dir = NULL) {
  ctx <- resolve_tracking_ctx(skill_dir)
  if (!isTRUE(ctx$ready)) {
    stop(
      "skills/hfc-fieldloop/config.json must be fully configured before running HFC FieldLoop.\n",
      "  1. Rscript <skill_dir>/install.R\n",
      "  2. Make sure OneDrive's desktop app is installed and signed in on this machine, and note the local folder it syncs to.\n",
      "  3. Edit <skill_dir>/config.json: set input_data_dir, onedrive_output_dir, and code_output_dir (media_dir is optional).\n",
      "Reason it wasn't ready just now: ", ctx$reason %||% "unknown"
    )
  }
  ctx
}

# Resolve (creating if needed) a named subfolder alongside the live file.
.tracking_subfolder <- function(ctx, subfolder) {
  dir <- file.path(ctx$local_dir, subfolder)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  dir
}

#' Read a named tracking-shaped xlsx from the live location (or a subfolder),
#' or NULL if it doesn't exist yet. `entity_label`/`group_label`: project's
#' configured labels (role_map.yaml), so the file's own "Entity ID"/"Group"-
#' style headers are read back correctly regardless of what they were
#' configured as.
read_named_tracking_file <- function(ctx, dest_name, subfolder = NULL, entity_label = NA_character_, group_label = NA_character_) {
  dir <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$local_dir
  path <- file.path(dir, dest_name)
  if (!file.exists(path)) return(NULL)
  read_issue_tracking(path, entity_label = entity_label, group_label = group_label)
}

#' Write a tracking-shaped tibble as `dest_name` at the live location (or a
#' subfolder) — single xlsx, no CSV twin (a CSV registry copy is kept only
#' for the live issue_tracking.xlsx itself, see commit_issue_tracking()).
#' Writes to a temp file in the SAME directory first, then file.rename()s it
#' into place: rename is atomic on the same filesystem, so an interruption
#' mid-write can never leave xlsx_path truncated/corrupted the way
#' openxlsx::saveWorkbook(..., overwrite=TRUE) directly at xlsx_path could
#' (it's a file.copy() under the hood, not atomic) — this is the writer
#' behind every clone/snapshot/merged-file write AND the live
#' issue_tracking.xlsx commit, so the fix applies everywhere at once.
write_named_tracking_file <- function(ctx, tbl, dest_name, subfolder = NULL, entity_label = NA_character_, group_label = NA_character_) {
  dir <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$local_dir
  xlsx_path <- file.path(dir, dest_name)
  display <- prepare_tracking_display(tbl, entity_label, group_label)
  suppressPackageStartupMessages(library(openxlsx))
  wb <- createWorkbook(); addWorksheet(wb, "Tracking")
  writeData(wb, "Tracking", display)
  tmp_path <- file.path(dir, paste0(".", basename(dest_name), ".", Sys.getpid(), ".tmp"))
  saveWorkbook(wb, tmp_path, overwrite = TRUE)
  if (!file.rename(tmp_path, xlsx_path)) {
    # Rename can fail across filesystems (e.g. dest on a different mount) —
    # fall back to a direct copy so the write still completes.
    file.copy(tmp_path, xlsx_path, overwrite = TRUE)
    file.remove(tmp_path)
  }
  list(status = "ok", path = xlsx_path)
}

#' Integrity check for a tracking table — stop()s loudly rather than letting
#' a corrupted read/write succeed silently. Checks: row count didn't shrink
#' unexpectedly (expect_n, when given), no blank finding_id, no duplicate
#' finding_id — the join key the whole merge system depends on. The real
#' incident this guards against: a manual single-cell correction via raw
#' openxlsx::loadWorkbook()/writeData() (bypassing these safe read/write
#' functions) silently wiped several columns' content, including
#' finding_id, across every row, not just the edited one.
verify_tracking_integrity <- function(tbl, expect_n = NULL) {
  if (is.null(tbl)) stop("verify_tracking_integrity(): tbl is NULL.")
  if (!"finding_id" %in% names(tbl)) stop("verify_tracking_integrity(): tbl has no finding_id column.")
  if (!is.null(expect_n) && nrow(tbl) != expect_n) {
    stop(sprintf("verify_tracking_integrity(): row count is %d, expected %d — a write may have been truncated.", nrow(tbl), expect_n))
  }
  fid <- as.character(tbl$finding_id)
  blank <- is.na(fid) | !nzchar(fid)
  if (any(blank)) {
    stop(sprintf("verify_tracking_integrity(): %d row(s) have a blank finding_id — the join key the merge system depends on.", sum(blank)))
  }
  dup <- unique(fid[duplicated(fid)])
  if (length(dup)) {
    stop(sprintf("verify_tracking_integrity(): duplicate finding_id(s): %s", paste(dup, collapse = ", ")))
  }
  invisible(TRUE)
}

#' Patch N cells in the LIVE tracking file safely — read-modify-write
#' through read_named_tracking_file()/write_named_tracking_file() only,
#' never a raw openxlsx call (see verify_tracking_integrity()'s header
#' comment for the incident this exists to prevent). `updates`: a
#' data.frame with a finding_id column plus any other columns to patch —
#' only named columns present in BOTH `updates` and the live table are
#' touched; every other cell, and every row not named in `updates`, is left
#' exactly as read. Errors (not silently no-ops) on an unknown finding_id,
#' so a typo'd ID can't quietly patch nothing.
patch_tracking_cells <- function(ctx, dest_name, updates, subfolder = NULL, entity_label = NA_character_, group_label = NA_character_) {
  if (!is.data.frame(updates) || !"finding_id" %in% names(updates)) {
    stop("patch_tracking_cells(): `updates` must be a data.frame with a finding_id column.")
  }
  current <- read_named_tracking_file(ctx, dest_name, subfolder = subfolder, entity_label = entity_label, group_label = group_label)
  if (is.null(current)) stop("patch_tracking_cells(): no existing file at ", dest_name, " to patch.")
  verify_tracking_integrity(current)
  patch_cols <- intersect(setdiff(names(updates), "finding_id"), names(current))
  if (!length(patch_cols)) {
    stop("patch_tracking_cells(): no patchable columns in common between `updates` and the live table.")
  }
  unknown_ids <- setdiff(as.character(updates$finding_id), as.character(current$finding_id))
  if (length(unknown_ids)) {
    stop("patch_tracking_cells(): finding_id(s) not present in the live table: ", paste(unknown_ids, collapse = ", "))
  }
  match_idx <- match(as.character(updates$finding_id), as.character(current$finding_id))
  for (col in patch_cols) {
    current[[col]][match_idx] <- updates[[col]]
  }
  n_before <- nrow(current)
  verify_tracking_integrity(current, expect_n = n_before)
  write_named_tracking_file(ctx, current, dest_name, subfolder = subfolder, entity_label = entity_label, group_label = group_label)
}

#' Delete a named file at the live location (or a subfolder) — used after a
#' merged_*.xlsx has been committed.
delete_named_tracking_file <- function(ctx, dest_name, subfolder = NULL) {
  dir <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$local_dir
  path <- file.path(dir, dest_name)
  if (file.exists(path)) file.remove(path)
  invisible(NULL)
}

#' Fetch the current live issue_tracking.xlsx into internal snake_case
#' columns. `tbl` is NULL if it doesn't exist yet (first-ever run).
fetch_issue_tracking <- function(skill_dir = NULL, entity_label = NA_character_, group_label = NA_character_) {
  ctx <- resolve_tracking_ctx(skill_dir)
  dest_name <- ctx$cfg$main_file %||% "issue_tracking.xlsx"
  tbl <- read_named_tracking_file(ctx, dest_name, entity_label = entity_label, group_label = group_label)
  c(ctx, list(tbl = tbl, dest_name = dest_name))
}

#' Commit tbl as the live issue_tracking.xlsx. No local-only copy is written
#' anywhere else — the configured OneDrive output folder is the sole store;
#' see the file header.
commit_issue_tracking <- function(tbl, skill_dir = NULL, fetch_ctx = NULL, entity_label = NA_character_, group_label = NA_character_) {
  ctx <- fetch_ctx %||% resolve_tracking_ctx(skill_dir)
  dest_name <- ctx$cfg$main_file %||% "issue_tracking.xlsx"
  # Live-file writer only (not every snapshot/clone/merged-file write) —
  # stop()s loudly on a corrupted table rather than committing it.
  verify_tracking_integrity(tbl)
  write_named_tracking_file(ctx, tbl, dest_name, entity_label = entity_label, group_label = group_label)
}

snapshot_tracking_filename <- function(date = Sys.Date()) paste0(format(date, "%Y%m%d"), "_issue_tracking.xlsx")
snapshot_resolution_filename <- function(date = Sys.Date()) paste0(format(date, "%Y%m%d"), "_issues_resolution.xlsx")

#' Write/read today's intermediate/ snapshot (one per setup-build run; a
#' same-day rerun overwrites today's file rather than appending a new one).
write_tracking_snapshot <- function(ctx, tbl, date = Sys.Date(), entity_label = NA_character_, group_label = NA_character_) {
  write_named_tracking_file(ctx, tbl, snapshot_tracking_filename(date), subfolder = "intermediate", entity_label = entity_label, group_label = group_label)
}
read_tracking_snapshot <- function(ctx, date = Sys.Date(), entity_label = NA_character_, group_label = NA_character_) {
  read_named_tracking_file(ctx, snapshot_tracking_filename(date), subfolder = "intermediate", entity_label = entity_label, group_label = group_label)
}

#' Write/read today's resolutions/ clone (one working copy per "Process HFC
#' feedback" day — a same-day second pass reuses the existing clone rather
#' than discarding in-progress Status/Corrections edits).
write_resolution_clone <- function(ctx, tbl, date = Sys.Date(), entity_label = NA_character_, group_label = NA_character_) {
  write_named_tracking_file(ctx, tbl, snapshot_resolution_filename(date), subfolder = "resolutions", entity_label = entity_label, group_label = group_label)
}
read_resolution_clone <- function(ctx, date = Sys.Date(), entity_label = NA_character_, group_label = NA_character_) {
  read_named_tracking_file(ctx, snapshot_resolution_filename(date), subfolder = "resolutions", entity_label = entity_label, group_label = group_label)
}

touched_ids_filename <- function(date = Sys.Date()) paste0(format(date, "%Y%m%d"), "_touched_ids.txt")

#' Record that the agent actually modified `finding_id` in today's
#' resolutions pass — called from .update_clone_row()
#' (apply_feedback_helpers.R) every time a row's Status/Corrections is
#' changed. This is the source of truth merge_resolutions.R uses to scope
#' its live-file overwrite to only rows the agent actually touched today,
#' never a row a field/RA edit reached concurrently on the live file that
#' the agent's clone never saw (see merge_resolution_updates()'s
#' touched_ids parameter, build_outputs.R — the fix for the data-loss bug
#' the pre-deployment audit found: without this, EVERY finding_id present
#' in both the clone and the live file got the clone's Status/Corrections/
#' Correction Author blindly, even ones the agent never touched this pass).
record_touched_id <- function(ctx, finding_id, date = Sys.Date()) {
  dir <- .tracking_subfolder(ctx, "resolutions")
  path <- file.path(dir, touched_ids_filename(date))
  cat(finding_id, "\n", file = path, append = TRUE, sep = "")
  invisible(NULL)
}

#' Every finding_id the agent actually touched during today's resolution
#' pass — character(0) if none/no file yet (a caller merging against zero
#' touched ids should overwrite nothing, not everything).
read_touched_ids <- function(ctx, date = Sys.Date()) {
  dir <- .tracking_subfolder(ctx, "resolutions")
  path <- file.path(dir, touched_ids_filename(date))
  if (!file.exists(path)) return(character(0))
  ids <- readLines(path, warn = FALSE)
  unique(ids[nzchar(ids)])
}

applied_ids_filename <- function(date = Sys.Date()) paste0(format(date, "%Y%m%d"), "_applied_ids.txt")

#' Record that finding_id's fix has been written to the intermediate/ data
#' file today — called from apply_one_fix() (apply_feedback_helpers.R)
#' immediately after write_intermediate() succeeds, before the (separate)
#' clone update. Guards against a crash-then-retry double-applying a
#' non-idempotent fix: load_latest_dataset() always prefers the intermediate
#' file once it exists, so re-running fix(ds) against already-fixed data
#' would silently double-apply it. A retry checks is_fix_applied() first and,
#' if TRUE, skips straight to catching up the (idempotent) clone update
#' instead of re-running the fix.
record_fix_applied <- function(ctx, finding_id, date = Sys.Date()) {
  dir <- .tracking_subfolder(ctx, "resolutions")
  path <- file.path(dir, applied_ids_filename(date))
  cat(finding_id, "\n", file = path, append = TRUE, sep = "")
  invisible(NULL)
}

#' Has finding_id's fix already been written to today's intermediate/ file?
is_fix_applied <- function(ctx, finding_id, date = Sys.Date()) {
  dir <- .tracking_subfolder(ctx, "resolutions")
  path <- file.path(dir, applied_ids_filename(date))
  if (!file.exists(path)) return(FALSE)
  ids <- readLines(path, warn = FALSE)
  finding_id %in% ids[nzchar(ids)]
}

#' Load a project's configured entity_label from hfc/config/role_map.yaml —
#' for scripts that don't already have `roles` loaded in memory (e.g.
#' commit_merged_issue_tracking.R, merge_resolutions.R). Returns NA if the
#' file or field is missing (reproduces the generic "Entity ID"/"Entity"
#' header, same as today).
load_entity_label <- function(code_output_dir) {
  path <- hfc_path(code_output_dir, "config", "role_map.yaml")
  if (!file.exists(path)) return(NA_character_)
  cfg <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  lbl <- cfg$entity_label
  if (is.null(lbl) || !nzchar(as.character(lbl))) return(NA_character_)
  as.character(lbl)
}

#' Load a project's configured group_label from hfc/config/role_map.yaml —
#' mirrors load_entity_label(). Returns NA if the file/field is missing
#' (reproduces the generic "Group" header, same as today).
load_group_label <- function(code_output_dir) {
  path <- hfc_path(code_output_dir, "config", "role_map.yaml")
  if (!file.exists(path)) return(NA_character_)
  cfg <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  lbl <- cfg$group_label
  if (is.null(lbl) || !nzchar(as.character(lbl))) return(NA_character_)
  as.character(lbl)
}
