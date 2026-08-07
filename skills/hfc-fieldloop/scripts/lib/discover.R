# Discover microdata + SurveyCTO-like form inside the configured input data
# directory (config.json's input_data_dir) and any of its nested subfolders
# — never outside it. No searching across multiple top-level locations;
# media resolution lives entirely in config.json (cfg$media_dir) now, not
# here.
# Usage:
#   Rscript discover.R <input_data_dir>
#   source(); res <- discover_project(input_data_dir)

discover_project <- function(input_data_dir) {
    input_data_dir <- normalizePath(input_data_dir, mustWork = FALSE)
    if (!dir.exists(input_data_dir)) {
        return(list(
            input_data_dir = input_data_dir, data = NULL, form = NULL,
            all_data_candidates = character(), all_form_candidates = character(),
            status = "missing_dir"
        ))
    }

    candidates <- list.files(
        input_data_dir, pattern = "\\.(dta|csv|xlsx|xls)$", full.names = TRUE,
        ignore.case = TRUE, recursive = TRUE
    )
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

    # Roster/target-sample-list candidate — a second data file, distinct
    # from the main microdata file, that looks like a planned/target sample
    # list rather than actual survey responses (used by the completion
    # signal detector, profile_roles.R's detect_completion_signal()). Never
    # blocks the single-file happy path: roster_candidate is NULL whenever
    # there's no second file, which is the common case.
    is_roster_like <- function(path) {
        grepl("roster|sample.?frame|sample.?list|target.?list|listing", tolower(basename(path)))
    }
    roster_pool <- if (length(data_files) > 1) data_files[-1] else character()
    roster_named <- roster_pool[vapply(roster_pool, is_roster_like, logical(1))]
    roster_path <- if (length(roster_named)) roster_named[[1]] else if (length(roster_pool)) roster_pool[[1]] else NA_character_
    roster_candidate <- if (!is.na(roster_path)) {
        list(path = roster_path, confidence = if (length(roster_named)) "name_match" else "second_file")
    } else NULL

    # Project description / Pre-Analysis Plan document — background context
    # only (survey purpose, design, target sample, key outcomes), never a
    # data source. Same name-match-first, single-file-fallback pattern as
    # roster_candidate above. Extensions never overlap the data-file pattern,
    # so this can't steal a real data/form file.
    doc_candidates <- list.files(
        input_data_dir, pattern = "\\.(pdf|docx?|txt|md)$", full.names = TRUE,
        ignore.case = TRUE, recursive = TRUE
    )
    doc_candidates <- unique(normalizePath(doc_candidates, mustWork = FALSE))
    is_context_doc_like <- function(path) {
        grepl("pap|pre.?analysis|project.?description|protocol|concept.?note|proposal|study.?design|research.?plan|design.?report|background",
              tolower(basename(path)))
    }
    doc_named <- doc_candidates[vapply(doc_candidates, is_context_doc_like, logical(1))]
    context_doc <- if (length(doc_named)) {
        list(path = doc_named[[1]], confidence = "name_match")
    } else if (length(doc_candidates) == 1) {
        list(path = doc_candidates[[1]], confidence = "only_doc_file")
    } else NULL

    list(
        input_data_dir = input_data_dir,
        data = data_info,
        form = form_info,
        all_data_candidates = data_files,
        all_form_candidates = forms,
        roster_candidate = roster_candidate,
        context_doc = context_doc,
        status = if (!is.null(data_info)) "found" else "missing_data"
    )
}

# The block below is useful for sanity check, i.e. user wants to check discovery of files
cmd_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", cmd_args, value = TRUE)
is_main <- length(file_arg) > 0 && grepl("discover\\.R$", file_arg[[1]])

if (is_main) {
    this <- sub("^--file=", "", file_arg[[1]])
    source(file.path(dirname(this), "utils.R"), local = TRUE)
    args <- commandArgs(trailingOnly = TRUE)
    dir_arg <- if (length(args)) args[[1]] else getwd()
    suppressPackageStartupMessages({
        library(jsonlite)
        if (requireNamespace("haven", quietly = TRUE)) library(haven)
        if (requireNamespace("readr", quietly = TRUE)) library(readr)
        if (requireNamespace("readxl", quietly = TRUE)) library(readxl)
    })
    res <- discover_project(dir_arg)
    cat(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null"), "\n")
}
