# Discover microdata + SurveyCTO-like form under a project root.
# Usage:
#   Rscript discover.R <project_root>
#   source(); res <- discover_project(project_root)

discover_project <- function(project_root, create_raw_if_missing = TRUE) {
  project_root <- normalizePath(project_root, mustWork = FALSE)
  raw_dir <- file.path(project_root, "data", "raw")
  if (create_raw_if_missing && !dir.exists(raw_dir)) {
    dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  }

  search_dirs <- unique(c(
    raw_dir,
    file.path(project_root, "data"),
    file.path(project_root, "instrument"),
    file.path(project_root, "data", "surveys"),
    project_root
  ))
  search_dirs <- search_dirs[dir.exists(search_dirs)]

  candidates <- character()
  for (d in search_dirs) {
    candidates <- c(candidates, list.files(
      d, pattern = "\\.(dta|csv|xlsx|xls)$", full.names = TRUE,
      ignore.case = TRUE, recursive = FALSE
    ))
  }
  candidates <- unique(normalizePath(candidates, mustWork = FALSE))
  # Exclude resolved outputs and feedback/tracking workbooks by name
  bn <- tolower(basename(candidates))
  candidates <- candidates[!grepl("_resolved\\.|feedback|tracking|ieduplicates|summary", bn)]

  is_form_like <- function(path) {
    bn <- tolower(basename(path))
    if (grepl("fieldwork|surveycto|instrument|form", bn)) return(TRUE)
    if (!grepl("\\.xlsx?$", bn)) return(FALSE)
    if (!requireNamespace("readxl", quietly = TRUE)) return(FALSE)
    sheets <- tryCatch(tolower(readxl::excel_sheets(path)), error = function(e) character())
    any(sheets %in% c("survey", "choices", "settings"))
  }

  forms <- candidates[vapply(candidates, is_form_like, logical(1))]
  data_files <- setdiff(candidates, forms)

  # Prefer .dta then largest csv/xlsx as microdata
  rank_data <- function(p) {
    ext <- tolower(tools::file_ext(p))
    sz <- file.info(p)$size %||% 0
    pri <- switch(ext, dta = 3, csv = 2, xlsx = 1, xls = 1, 0)
    pri * 1e12 + sz
  }
  data_files <- data_files[order(vapply(data_files, rank_data, numeric(1)), decreasing = TRUE)]

  summarize_data <- function(path) {
    info <- list(path = path, size_bytes = file.info(path)$size, nrow = NA, ncol = NA, error = NULL)
    tryCatch({
      if (grepl("\\.dta$", path, ignore.case = TRUE)) {
        ds <- haven::read_dta(path, n_max = 5)
        # full nrow via cheaper approach when possible
        full <- haven::read_dta(path)
        info$nrow <- nrow(full)
        info$ncol <- ncol(full)
      } else if (grepl("\\.csv$", path, ignore.case = TRUE)) {
        full <- readr::read_csv(path, show_col_types = FALSE, guess_max = 1000)
        info$nrow <- nrow(full)
        info$ncol <- ncol(full)
      } else {
        full <- readxl::read_excel(path, n_max = 5)
        info$ncol <- ncol(full)
        info$nrow <- NA
      }
    }, error = function(e) info$error <<- conditionMessage(e))
    info
  }

  data_info <- if (length(data_files)) summarize_data(data_files[[1]]) else NULL
  form_info <- if (length(forms)) {
    list(path = forms[[1]], sheets = tryCatch(readxl::excel_sheets(forms[[1]]), error = function(e) character()))
  } else NULL

  data_path <- if (!is.null(data_info)) data_info$path else NULL
  media <- if (exists("discover_media_folder", mode = "function")) {
    discover_media_folder(project_root, data_path)
  } else {
    # Fallback when media.R not sourced yet
    cands <- c(
      file.path(project_root, "data", "raw", "media"),
      file.path(project_root, "data", "media"),
      file.path(project_root, "media")
    )
    hit <- cands[dir.exists(cands)]
    list(
      path = if (length(hit)) normalizePath(hit[[1]]) else NA_character_,
      found = length(hit) > 0,
      candidates = cands
    )
  }

  list(
    project_root = project_root,
    raw_dir = raw_dir,
    raw_dir_exists = dir.exists(raw_dir),
    data = data_info,
    form = form_info,
    media_folder = media$path,
    media_folder_found = isTRUE(media$found),
    media_folder_candidates = media$candidates,
    all_data_candidates = data_files,
    all_form_candidates = forms,
    status = if (!is.null(data_info)) "found" else "missing_data"
  )
}

# --- CLI ---
if (sys.nframe() == 0L || identical(sys.frame(1)$ofile, NULL)) {
  # When run via Rscript --file=
}

cmd_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", cmd_args, value = TRUE)
is_main <- length(file_arg) > 0 && grepl("discover\\.R$", file_arg[[1]])

if (is_main) {
  this <- sub("^--file=", "", file_arg[[1]])
  source(file.path(dirname(this), "utils.R"), local = TRUE)
  source(file.path(dirname(this), "media.R"), local = TRUE)
  args <- commandArgs(trailingOnly = TRUE)
  root <- if (length(args)) args[[1]] else getwd()
  suppressPackageStartupMessages({
    library(jsonlite)
    if (requireNamespace("haven", quietly = TRUE)) library(haven)
    if (requireNamespace("readr", quietly = TRUE)) library(readr)
    if (requireNamespace("readxl", quietly = TRUE)) library(readxl)
  })
  res <- discover_project(root)
  cat(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null"), "\n")
}
