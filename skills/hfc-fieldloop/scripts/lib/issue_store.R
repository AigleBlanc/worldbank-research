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
write_named_tracking_file <- function(ctx, tbl, dest_name, subfolder = NULL, entity_label = NA_character_, group_label = NA_character_) {
  dir <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$local_dir
  xlsx_path <- file.path(dir, dest_name)
  display <- prepare_tracking_display(tbl, entity_label, group_label)
  suppressPackageStartupMessages(library(openxlsx))
  wb <- createWorkbook(); addWorksheet(wb, "Tracking")
  writeData(wb, "Tracking", display); saveWorkbook(wb, xlsx_path, overwrite = TRUE)
  list(status = "ok", path = xlsx_path)
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
