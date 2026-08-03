# OneDrive for Business primitives via Microsoft365R, plus report-link upload.
#
# One file matters: main_file (issue_tracking.xlsx) — shared with the field
# team, edited collaboratively by the agent, RA, and field team. Once OneDrive
# is configured it is the sole source of truth (see scripts/lib/issue_store.R,
# which builds the actual fetch/commit logic on top of the primitives here).
# Local fallback (OneDrive not configured): hfc/output/issue_tracking.xlsx.
#
# Auth model: delegated, one-time interactive sign-in (browser or device code).
# Microsoft365R/AzureAuth caches the token locally and refreshes it silently
# afterward — nothing secret is stored in this skill package. The first-ever
# sign-in must be done by a human in an interactive R session (see
# setup_onedrive_auth.R); it cannot be completed from a non-interactive
# Rscript invocation (e.g. one launched by Claude Code via the Bash tool).
#
# Target: whoever runs the pipeline connects it to their OWN individual
# OneDrive for Business account — no SharePoint site or Team needs to be
# created. That person then manually shares the resulting folder with
# collaborators (edit access) via OneDrive's normal "Specific people" sharing
# UI — this code never mints its own share links, it just uploads into
# whatever folder access has already been configured by hand.

# Resolve skill root for config lookup
skill_dir_guess <- function(project_root = NULL) {
  cands <- c(
    if (!is.null(project_root)) file.path(project_root, "hfc-fieldloop"),
    "hfc-fieldloop",
    if (!is.null(project_root)) file.path(dirname(project_root), "hfc-fieldloop")
  )
  for (c in cands) {
    if (!is.null(c) && dir.exists(c) && file.exists(file.path(c, "scripts", "lib", "onedrive_drive.R"))) {
      return(normalizePath(c))
    }
  }
  NA_character_
}

#' Load folder_path/file names from onedrive.json
#' One rule: the only file that matters is assets/lib/onedrive.json, inside
#' the skill itself. Every user edits that one file with their own
#' folder/file names — there is no per-project override and no legacy path
#' to fall back to. Unlike the old google_drive.json, this file holds no
#' secrets — delegated auth needs no stored credential, just where to look.
#' There's no site/tenant URL to configure either — `get_business_onedrive()`
#' connects to whichever account is signed in, so the only signal for "is
#' this actually set up" is the explicit `enabled` flag (the skill ships
#' `enabled: false`).
load_onedrive_config <- function(project_root, skill_dir = NULL) {
  if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess(project_root)
  empty <- function(path = NA_character_, reason = NULL) {
    list(
      found = FALSE, path = path,
      folder_path = NA_character_,
      main_file = NA_character_,
      reason = reason
    )
  }
  if (is.null(skill_dir) || is.na(skill_dir)) return(empty(reason = "missing_onedrive_json"))
  cfg_path <- file.path(skill_dir, "assets", "lib", "onedrive.json")
  if (!file.exists(cfg_path)) return(empty(reason = "missing_onedrive_json"))

  raw <- tryCatch(jsonlite::fromJSON(cfg_path), error = function(e) NULL)
  if (is.null(raw)) return(empty(path = normalizePath(cfg_path), reason = "invalid_onedrive_json"))
  if (!isTRUE(raw$enabled)) return(empty(path = normalizePath(cfg_path), reason = "not_enabled_in_onedrive_json"))

  list(
    found = TRUE,
    path = normalizePath(cfg_path),
    folder_path = if (!is.null(raw$folder_path) && nzchar(as.character(raw$folder_path))) {
      as.character(raw$folder_path)
    } else "HFC Reports",
    main_file = if (!is.null(raw$main_file) && nzchar(as.character(raw$main_file))) {
      as.character(raw$main_file)
    } else "issue_tracking.xlsx"
  )
}

# Cache the ms_drive object within one R session, so a single
# `Rscript run_setup_build.R` run doesn't re-authenticate on every call.
.onedrive_drive_cache <- new.env(parent = emptyenv())

get_onedrive_drive <- function(cfg) {
  key <- "business_onedrive"
  cached <- mget(key, envir = .onedrive_drive_cache, ifnotfound = list(NULL))[[1]]
  if (!is.null(cached)) return(cached)
  drive <- Microsoft365R::get_business_onedrive()
  assign(key, drive, envir = .onedrive_drive_cache)
  drive
}

#' Get (creating if needed) the ms_drive_item for a (possibly nested) folder path.
ensure_onedrive_folder <- function(drive, folder_path) {
  folder_path <- gsub("^/+|/+$", "", folder_path)
  if (!nzchar(folder_path)) return(drive$get_item("/"))
  segs <- strsplit(folder_path, "/")[[1]]
  cur_path <- ""
  item <- NULL
  for (seg in segs) {
    cur_path <- if (nzchar(cur_path)) paste0(cur_path, "/", seg) else seg
    item <- tryCatch(drive$get_item(cur_path), error = function(e) NULL)
    if (is.null(item)) {
      item <- tryCatch(drive$create_folder(cur_path), error = function(e) drive$get_item(cur_path))
    }
  }
  item
}

#' Write a findings/issue-tracking data frame (internal snake_case columns)
#' to a temp .xlsx (sheet "Tracking", display header labels — same sheet name
#' local write_issue_tracking() uses, so read paths don't need to care whether
#' a file came from OneDrive or local disk) and upload it into the given
#' OneDrive folder under `dest_name`. Returns the uploaded item's properties
#' (id, webUrl). Generic over `dest_name` — used for the live issue_tracking
#' file, dated snapshots, and merged_*.xlsx alike; see scripts/lib/issue_store.R
#' for the higher-level fetch/commit wrappers built on this.
upload_feedback_xlsx <- function(drive, folder_item, df, dest_name) {
  suppressPackageStartupMessages({ library(openxlsx) })
  tmp <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp), add = TRUE)
  openxlsx::write.xlsx(rename_to_issue_tracking_headers(df), tmp, sheetName = "Tracking", overwrite = TRUE)
  item <- folder_item$upload(tmp, dest = dest_name)
  item$properties
}

#' Upload the built HTML report into the configured OneDrive folder and
#' return its ordinary OneDrive URL. No share link is minted here — the
#' folder's access (e.g. specific external collaborators) is set up once by
#' hand in the OneDrive web UI, and anyone already granted access to it can
#' open this URL directly.
upload_report_and_get_link <- function(project_root, project_id, skill_dir = NULL, html_path) {
  out <- list(status = "skipped", reason = "no_config", url = NA_character_)
  if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess(project_root)
  cfg <- load_onedrive_config(project_root, skill_dir)
  if (!isTRUE(cfg$found)) {
    out$reason <- cfg$reason %||% "missing_onedrive_json"
    return(out)
  }
  if (!requireNamespace("Microsoft365R", quietly = TRUE)) {
    out$reason <- "packages_missing"
    return(out)
  }
  if (!file.exists(html_path)) {
    out$reason <- "html_report_missing"
    return(out)
  }
  tryCatch({
    drive <- get_onedrive_drive(cfg)
    folder_item <- ensure_onedrive_folder(drive, cfg$folder_path)
    dest_name <- paste0(gsub("[^A-Za-z0-9_-]+", "_", project_id), "_report.html")
    item <- folder_item$upload(html_path, dest = dest_name)
    out$status <- "ok"
    out$reason <- "uploaded"
    out$url <- item$properties$webUrl %||% NA_character_
  }, error = function(e) {
    out$status <<- "skipped"
    out$reason <<- conditionMessage(e)
  })
  out
}
