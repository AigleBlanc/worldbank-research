# Single source of truth for "where does issue_tracking.xlsx live, right now."
# Once OneDrive is configured (assets/lib/onedrive.json, enabled: true) it is
# the SOLE store — no permanent local copy is ever treated as authoritative.
# Every read fetches current state; every write commits back. When OneDrive
# isn't configured (or a call fails), local hfc/output/ becomes the sole
# store instead — always exactly one location, never a persistent dual copy.
# Built entirely on scripts/lib/onedrive_drive.R's primitives (get_onedrive_drive,
# ensure_onedrive_folder, upload_feedback_xlsx, load_onedrive_config) — no new
# upload/download mechanism here, just backend selection + local fallback.
#
# Subfolders alongside the live file, in whichever backend is active:
#   intermediate/<YYYYMMDD>_issue_tracking.xlsx   — one per setup-build run
#   resolutions/<YYYYMMDD>_issues_resolution.xlsx — one working clone per
#                                                    "Process HFC feedback" day
# NOTE naming collision: this "intermediate/" (tracking snapshots) is
# unrelated to data/intermediate/ (fixed microdata, see write_intermediate()
# in utils.R) — always use the qualified path when referring to either.

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

#' Commit tbl as the live issue_tracking.xlsx, always also writing the local
#' hfc/registry/issue_tracking.csv as a plain-text audit trail (never read
#' back as authoritative — the live xlsx, wherever it lives, always wins).
commit_issue_tracking <- function(project_root, tbl, skill_dir = NULL, fetch_ctx = NULL, force_local = FALSE) {
  ctx <- fetch_ctx %||% resolve_tracking_ctx(project_root, skill_dir, force_local = force_local)
  dest_name <- if (identical(ctx$backend, "onedrive")) ctx$cfg$main_file else "issue_tracking.xlsx"
  res <- write_named_tracking_file(ctx, tbl, dest_name)
  reg_csv <- hfc_path(project_root, "registry", "issue_tracking.csv")
  dir.create(dirname(reg_csv), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(prepare_tracking_display(tbl), reg_csv)
  res
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
