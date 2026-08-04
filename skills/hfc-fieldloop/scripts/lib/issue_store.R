# Single source of truth for "where does issue_tracking.xlsx live, right now."
# OneDrive (assets/lib/onedrive.json, enabled: true) is REQUIRED and is the
# SOLE store — there is no local backup/fallback in the product. Every read
# fetches current state; every write commits back. Built entirely on
# scripts/lib/onedrive_drive.R's primitives (get_onedrive_drive,
# ensure_onedrive_folder, upload_feedback_xlsx, load_onedrive_config) — no
# new upload/download mechanism here, just OneDrive access.
#
# Subfolders alongside the live file, inside the same OneDrive folder:
#   intermediate/<YYYYMMDD>_issue_tracking.xlsx   — one per setup-build run
#   resolutions/<YYYYMMDD>_issues_resolution.xlsx — one working clone per
#                                                    "Process HFC feedback" day
# NOTE naming collision: this "intermediate/" (tracking snapshots) is
# unrelated to data/intermediate/ (fixed microdata, see write_intermediate()
# in utils.R) — always use the qualified path when referring to either.
#
# The "local" backend below still exists as a code path, but it is an
# internal test-only fallback, never exposed via any CLI flag, AskUserQuestion,
# or documentation — see require_onedrive_ready(), which every user-facing
# entry point calls before doing any real work. It exists purely so this
# skill's own test suite can exercise the tracking/merge logic without a
# live OneDrive connection (by pointing skill_dir at a path with no
# resolvable onedrive.json) — no product code path can reach it.

# Resolve where the live file lives right now — OneDrive folder item, or a
# local dir — computed once per script invocation and threaded through the
# read/write calls below so a script only resolves/authenticates once.
resolve_tracking_ctx <- function(project_root, skill_dir = NULL, force_local = FALSE) {
  if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess(project_root)
  cfg <- load_onedrive_config(project_root, skill_dir)
  if (!force_local && isTRUE(cfg$found) && requireNamespace("Microsoft365R", quietly = TRUE)) {
    ctx <- tryCatch({
      drive <- get_onedrive_drive(cfg)
      folder_item <- ensure_onedrive_folder(drive, cfg$folder_path)
      list(backend = "onedrive", cfg = cfg, drive = drive, folder_item = folder_item,
           local_dir = hfc_path(project_root, "output"), reason = "ok")
    }, error = function(e) NULL)
    if (!is.null(ctx)) return(ctx)
  }
  list(backend = "local", cfg = cfg, drive = NULL, folder_item = NULL,
       local_dir = hfc_path(project_root, "output"),
       reason = if (force_local) "no-onedrive flag" else (cfg$reason %||% "onedrive_unavailable"))
}

#' Hard-require that OneDrive is configured and reachable before doing any
#' real work — the product has no local-only path. Every user-facing entry
#' point (the CLI scripts under scripts/) calls this immediately after
#' resolving project_root, before anything else. Returns the resolved ctx
#' (always backend == "onedrive") on success; stop()s with setup
#' instructions otherwise.
require_onedrive_ready <- function(project_root, skill_dir = NULL) {
  ctx <- resolve_tracking_ctx(project_root, skill_dir)
  if (!identical(ctx$backend, "onedrive")) {
    stop(
      "OneDrive is required before running HFC FieldLoop — issue tracking has no local fallback.\n",
      "  1. Rscript <skill_dir>/install.R\n",
      "  2. Edit <skill_dir>/assets/lib/onedrive.json: set \"enabled\": true and a folder_path.\n",
      "  3. Rscript <skill_dir>/setup_onedrive_auth.R   (one-time interactive sign-in, run yourself, outside Claude Code)\n",
      "Reason OneDrive wasn't reachable just now: ", ctx$reason %||% "unknown"
    )
  }
  ctx
}

# Resolve (creating if needed) a named subfolder alongside the live file.
.tracking_subfolder <- function(ctx, subfolder) {
  if (identical(ctx$backend, "onedrive")) {
    ensure_onedrive_folder(ctx$drive, paste0(ctx$cfg$folder_path, "/", subfolder))
  } else {
    dir <- file.path(ctx$local_dir, subfolder)
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    dir
  }
}

#' Read a named tracking-shaped xlsx from the live location (or a subfolder),
#' or NULL if it doesn't exist yet.
read_named_tracking_file <- function(ctx, dest_name, subfolder = NULL) {
  if (identical(ctx$backend, "onedrive")) {
    folder <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$folder_item
    item <- tryCatch(folder$get_item(dest_name), error = function(e) NULL)
    if (is.null(item)) return(NULL)
    tmp <- tempfile(fileext = ".xlsx")
    on.exit(unlink(tmp), add = TRUE)
    item$download(dest = tmp, overwrite = TRUE)
    read_issue_tracking(tmp)
  } else {
    dir <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$local_dir
    path <- file.path(dir, dest_name)
    if (!file.exists(path)) return(NULL)
    read_issue_tracking(path)
  }
}

#' Write a tracking-shaped tibble as `dest_name` at the live location (or a
#' subfolder) — single xlsx, no CSV twin (a CSV registry copy is kept only
#' for the live issue_tracking.xlsx itself, see commit_issue_tracking()).
write_named_tracking_file <- function(ctx, tbl, dest_name, subfolder = NULL) {
  if (identical(ctx$backend, "onedrive")) {
    folder <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$folder_item
    props <- upload_feedback_xlsx(ctx$drive, folder, tbl, dest_name)
    list(status = "ok", backend = "onedrive", url = props$webUrl %||% NA_character_)
  } else {
    dir <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$local_dir
    xlsx_path <- file.path(dir, dest_name)
    display <- prepare_tracking_display(tbl)
    suppressPackageStartupMessages(library(openxlsx))
    wb <- createWorkbook(); addWorksheet(wb, "Tracking")
    writeData(wb, "Tracking", display); saveWorkbook(wb, xlsx_path, overwrite = TRUE)
    list(status = "ok", backend = "local", url = NA_character_)
  }
}

#' Delete a named file at the live location (or a subfolder) — used after a
#' merged_*.xlsx has been committed.
delete_named_tracking_file <- function(ctx, dest_name, subfolder = NULL) {
  if (identical(ctx$backend, "onedrive")) {
    folder <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$folder_item
    item <- tryCatch(folder$get_item(dest_name), error = function(e) NULL)
    if (!is.null(item)) tryCatch(item$delete(confirm = FALSE), error = function(e) NULL)
  } else {
    dir <- if (!is.null(subfolder)) .tracking_subfolder(ctx, subfolder) else ctx$local_dir
    path <- file.path(dir, dest_name)
    if (file.exists(path)) file.remove(path)
  }
  invisible(NULL)
}

#' Fetch the current live issue_tracking.xlsx into internal snake_case
#' columns. `tbl` is NULL if it doesn't exist yet (first-ever run).
fetch_issue_tracking <- function(project_root, skill_dir = NULL, force_local = FALSE) {
  ctx <- resolve_tracking_ctx(project_root, skill_dir, force_local = force_local)
  dest_name <- if (identical(ctx$backend, "onedrive")) ctx$cfg$main_file else "issue_tracking.xlsx"
  tbl <- read_named_tracking_file(ctx, dest_name)
  c(ctx, list(tbl = tbl, dest_name = dest_name))
}

#' Commit tbl as the live issue_tracking.xlsx. No local copy is written —
#' OneDrive (or, only from this skill's own tests, the local-fallback
#' backend) is the sole store; see the file header.
commit_issue_tracking <- function(project_root, tbl, skill_dir = NULL, fetch_ctx = NULL, force_local = FALSE) {
  ctx <- fetch_ctx %||% resolve_tracking_ctx(project_root, skill_dir, force_local = force_local)
  dest_name <- if (identical(ctx$backend, "onedrive")) ctx$cfg$main_file else "issue_tracking.xlsx"
  write_named_tracking_file(ctx, tbl, dest_name)
}

snapshot_tracking_filename <- function(date = Sys.Date()) paste0(format(date, "%Y%m%d"), "_issue_tracking.xlsx")
snapshot_resolution_filename <- function(date = Sys.Date()) paste0(format(date, "%Y%m%d"), "_issues_resolution.xlsx")

#' Write/read today's intermediate/ snapshot (one per setup-build run; a
#' same-day rerun overwrites today's file rather than appending a new one).
write_tracking_snapshot <- function(ctx, tbl, date = Sys.Date()) {
  write_named_tracking_file(ctx, tbl, snapshot_tracking_filename(date), subfolder = "intermediate")
}
read_tracking_snapshot <- function(ctx, date = Sys.Date()) {
  read_named_tracking_file(ctx, snapshot_tracking_filename(date), subfolder = "intermediate")
}

#' Write/read today's resolutions/ clone (one working copy per "Process HFC
#' feedback" day — a same-day second pass reuses the existing clone rather
#' than discarding in-progress Status/Corrections edits).
write_resolution_clone <- function(ctx, tbl, date = Sys.Date()) {
  write_named_tracking_file(ctx, tbl, snapshot_resolution_filename(date), subfolder = "resolutions")
}
read_resolution_clone <- function(ctx, date = Sys.Date()) {
  read_named_tracking_file(ctx, snapshot_resolution_filename(date), subfolder = "resolutions")
}
