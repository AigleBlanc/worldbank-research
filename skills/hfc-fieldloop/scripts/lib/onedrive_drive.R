# Feedback Sheet + report-link helpers: OneDrive for Business via Microsoft365R.
#
#   main_file  — shared with field (they edit field_comment / proposed_fix)
#   audit_file — working copy the code updates mid-process (status, resolved, …)
#
# Local twin: hfc/output/feedback_sheet.xlsx + hfc/registry/feedback.csv
#
# Auth model: delegated, one-time interactive sign-in (browser or device code).
# Microsoft365R/AzureAuth caches the token locally and refreshes it silently
# afterward — nothing secret is stored in this skill package. The first-ever
# sign-in must be done by a human in an interactive R session (see
# scripts/onedrive_auth_setup.R); it cannot be completed from a non-interactive
# Rscript invocation (e.g. one launched by Claude Code via the Bash tool).
#
# Target: a shared SharePoint/Team site document library (not one person's
# individual OneDrive), so multiple teammates can each sign in with their own
# account against the same shared folder. That folder's access (e.g. sharing
# it with specific external collaborators) is set up once by hand in the
# OneDrive/SharePoint web UI — this code never mints its own share links, it
# just uploads into the folder whose access is already configured.

source_feedback_libs <- function(lib_dir) {
  source(file.path(lib_dir, "utils.R"), local = FALSE)
  source(file.path(lib_dir, "build_outputs.R"), local = FALSE)
}

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

#' Load site_url/folder_path/file names from onedrive.json
#' Preference: hfc/config/onedrive.json → legacy config/ → assets/lib/onedrive.json.
#' Unlike the old google_drive.json, this file holds no secrets — delegated
#' auth needs no stored credential, just where to look.
load_onedrive_config <- function(project_root, skill_dir = NULL) {
  if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess(project_root)
  empty <- function(path = NA_character_, reason = NULL) {
    list(
      found = FALSE, path = path,
      site_url = NA_character_, folder_path = NA_character_,
      main_file = NA_character_, audit_file = NA_character_,
      reason = reason
    )
  }
  paths <- c(
    if (exists("hfc_path", mode = "function")) {
      hfc_path(project_root, "config", "onedrive.json")
    } else {
      file.path(project_root, "hfc", "config", "onedrive.json")
    },
    file.path(project_root, "config", "onedrive.json"), # legacy
    if (!is.null(skill_dir) && !is.na(skill_dir)) {
      file.path(skill_dir, "assets", "lib", "onedrive.json")
    } else NA_character_
  )
  paths <- unique(paths[!is.na(paths) & file.exists(paths)])
  if (!length(paths)) return(empty(reason = "missing_onedrive_json"))

  for (cfg_path in paths) {
    raw <- tryCatch(jsonlite::fromJSON(cfg_path), error = function(e) NULL)
    if (is.null(raw)) next
    site_url <- if (!is.null(raw$site_url)) as.character(raw$site_url) else NA_character_
    if (is.na(site_url) || !nzchar(site_url) || grepl("YOUR_", site_url, fixed = TRUE)) {
      next # placeholder-only config; try the next path in the preference order
    }
    return(list(
      found = TRUE,
      path = normalizePath(cfg_path),
      site_url = site_url,
      folder_path = if (!is.null(raw$folder_path) && nzchar(as.character(raw$folder_path))) {
        as.character(raw$folder_path)
      } else "HFC Reports",
      main_file = if (!is.null(raw$main_file) && nzchar(as.character(raw$main_file))) {
        as.character(raw$main_file)
      } else "feedback_main.xlsx",
      audit_file = if (!is.null(raw$audit_file) && nzchar(as.character(raw$audit_file))) {
        as.character(raw$audit_file)
      } else "feedback_audit.xlsx"
    ))
  }
  empty(path = normalizePath(paths[[1]]), reason = "placeholder_or_incomplete_onedrive_json")
}

# Cache the ms_drive object per site_url within one R session, so a single
# `Rscript run_setup_build.R` run doesn't re-resolve the site on every call.
.onedrive_drive_cache <- new.env(parent = emptyenv())

get_onedrive_drive <- function(cfg) {
  key <- cfg$site_url
  cached <- mget(key, envir = .onedrive_drive_cache, ifnotfound = list(NULL))[[1]]
  if (!is.null(cached)) return(cached)
  drive <- Microsoft365R::get_sharepoint_site(site_url = cfg$site_url)$get_drive()
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

#' Write a data frame to a temp .xlsx (sheet "Feedback") and upload it into
#' the configured OneDrive folder under `dest_name`. Returns the uploaded
#' item's properties (id, webUrl) or NULL on failure.
upload_feedback_xlsx <- function(drive, folder_item, df, dest_name) {
  suppressPackageStartupMessages({ library(openxlsx) })
  tmp <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp), add = TRUE)
  openxlsx::write.xlsx(df, tmp, sheetName = "Feedback", overwrite = TRUE)
  item <- folder_item$upload(tmp, dest = dest_name)
  item$properties
}

#' Push feedback to main (field) + audit (code) files from onedrive.json
#' @param target "both" | "main" | "audit"
sync_drive_feedback_best_effort <- function(project_root, project_id, feedback_df,
                                            skill_dir = NULL, target = "both") {
  out <- list(
    status = "skipped",
    reason = "no_config",
    main_url = NA_character_, audit_url = NA_character_,
    main_id = NA_character_, audit_id = NA_character_,
    # backwards-compat aliases (main = field-facing)
    url = NA_character_, id = NA_character_
  )
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

  tryCatch({
    drive <- get_onedrive_drive(cfg)
    folder_item <- ensure_onedrive_folder(drive, cfg$folder_path)
    wrote <- character()
    if (target %in% c("both", "main")) {
      props <- upload_feedback_xlsx(drive, folder_item, feedback_df, cfg$main_file)
      out$main_url <- props$webUrl %||% NA_character_
      out$url <- out$main_url
      wrote <- c(wrote, "main")
    }
    if (target %in% c("both", "audit")) {
      props <- upload_feedback_xlsx(drive, folder_item, feedback_df, cfg$audit_file)
      out$audit_url <- props$webUrl %||% NA_character_
      wrote <- c(wrote, "audit")
    }
    out$status <- "ok"
    out$reason <- paste0("synced:", paste(wrote, collapse = "+"))
  }, error = function(e) {
    out$status <<- "skipped"
    out$reason <<- conditionMessage(e)
  })
  out
}

# Backwards-compatible name used by older callers
create_drive_sheet_best_effort <- function(project_root, project_id, feedback_df,
                                           skill_dir = NULL) {
  sync_drive_feedback_best_effort(project_root, project_id, feedback_df,
                                  skill_dir = skill_dir, target = "both")
}

#' Pull field edits from main_file; fall back to audit then local
pull_feedback_from_drive <- function(project_root, skill_dir = NULL, prefer = c("main", "audit")) {
  if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess(project_root)
  cfg <- load_onedrive_config(project_root, skill_dir)
  out <- list(ok = FALSE, source = NA_character_, data = NULL, reason = NULL)
  if (!isTRUE(cfg$found)) {
    out$reason <- cfg$reason %||% "missing_onedrive_json"
    return(out)
  }
  if (!requireNamespace("Microsoft365R", quietly = TRUE)) {
    out$reason <- "packages_missing"
    return(out)
  }
  tryCatch({
    drive <- get_onedrive_drive(cfg)
    folder_item <- ensure_onedrive_folder(drive, cfg$folder_path)
    for (which in prefer) {
      fname <- if (identical(which, "main")) cfg$main_file else cfg$audit_file
      item <- tryCatch(folder_item$get_item(fname), error = function(e) NULL)
      if (is.null(item)) next
      tmp <- tempfile(fileext = ".xlsx")
      on.exit(unlink(tmp), add = TRUE)
      item$download(dest = tmp, overwrite = TRUE)
      df <- as.data.frame(openxlsx::read.xlsx(tmp, sheet = "Feedback"), stringsAsFactors = FALSE)
      out$ok <- TRUE
      out$source <- which
      out$data <- ensure_resolved_column(df)
      out$reason <- paste0("read_", which)
      return(out)
    }
    out$reason <- "no_readable_file"
  }, error = function(e) {
    out$reason <<- conditionMessage(e)
  })
  out
}

#' After code updates (resolved / ra_status), push to audit_file (and optionally main)
push_feedback_midprocess <- function(project_root, feedback_df, skill_dir = NULL,
                                     target = "audit") {
  sync_drive_feedback_best_effort(
    project_root, basename(project_root), feedback_df,
    skill_dir = skill_dir, target = target
  )
}

ensure_resolved_column <- function(fb) {
  fb <- as.data.frame(fb, stringsAsFactors = FALSE)
  if ("ra_status" %in% names(fb) && !"status" %in% names(fb)) {
    fb$status <- fb$ra_status
    fb$ra_status <- NULL
  }
  if (!"status" %in% names(fb)) fb$status <- "Open"
  fb$status[is.na(fb$status) | !nzchar(as.character(fb$status))] <- "Open"
  fb$status[tolower(as.character(fb$status)) == "open"] <- "Open"
  if (!"resolved" %in% names(fb)) fb$resolved <- "No"
  fb$resolved[is.na(fb$resolved) | !nzchar(as.character(fb$resolved))] <- "No"
  fb$resolved[tolower(as.character(fb$resolved)) == "no"] <- "No"
  fb$check_module <- NULL
  fb
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
