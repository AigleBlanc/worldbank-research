# Shared helpers for FieldLoop scripts/lib

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(as.character(a))))) return(b)
  a
}

decode_file_arg <- function(path) {
  gsub("~+~", " ", path, fixed = TRUE)
}

this_script_path <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd_args, value = TRUE)
  if (!length(file_arg)) return(NA_character_)
  decode_file_arg(sub("^--file=", "", file_arg[[1]]))
}

skill_from_script <- function(depth_up = 1L) {
  # depth_up=1: script in scripts/ → skill root; depth_up=2: script in scripts/lib/
  sp <- this_script_path()
  if (is.na(sp)) return(NA_character_)
  p <- dirname(sp)
  if (depth_up >= 2L) p <- dirname(p)
  if (depth_up >= 1L && basename(dirname(sp)) == "lib") {
    # scripts/lib/*.R → skill is ../..
    p <- normalizePath(file.path(dirname(sp), "..", ".."))
  } else {
    p <- normalizePath(file.path(dirname(sp), ".."))
  }
  p
}

safe_num <- function(x) {
  if (inherits(x, "haven_labelled")) x <- as.vector(x)
  suppressWarnings(as.numeric(x))
}

skill_root_from_file <- function(this_file) {
  # .../hfc-fieldloop/scripts/lib/foo.R -> skill root
  normalizePath(file.path(dirname(this_file), "..", ".."))
}

project_root_from_skill <- function(skill_dir) {
  normalizePath(file.path(skill_dir, ".."))
}

#' Product root: all built artifacts live under <project>/hfc/
hfc_root <- function(project_root) {
  file.path(project_root, "hfc")
}

hfc_path <- function(project_root, ...) {
  file.path(hfc_root(project_root), ...)
}

load_microdata <- function(path, sample_n = NA_integer_) {
  suppressPackageStartupMessages({
    library(haven); library(readr); library(readxl)
  })
  ext <- tolower(tools::file_ext(path))
  ds <- if (ext == "dta") {
    read_dta(path)
  } else if (ext == "csv") {
    read_csv(path, show_col_types = FALSE, guess_max = 10000)
  } else if (ext %in% c("xlsx", "xls")) {
    read_excel(path)
  } else {
    stop("Unsupported microdata type: ", ext)
  }
  if (!is.na(sample_n) && sample_n > 0 && nrow(ds) > sample_n) {
    set.seed(42)
    ds <- ds[sample.int(nrow(ds), sample_n), , drop = FALSE]
  }
  ds
}

write_resolved <- function(ds, source_path) {
  suppressPackageStartupMessages({ library(haven); library(readr); library(openxlsx) })
  # Drop labels that block character mutations / write
  ds <- as.data.frame(lapply(ds, function(col) {
    if (inherits(col, "haven_labelled")) return(as.vector(col))
    col
  }), stringsAsFactors = FALSE)
  dir <- dirname(source_path)
  stem <- tools::file_path_sans_ext(basename(source_path))
  ext <- tolower(tools::file_ext(source_path))
  out <- file.path(dir, paste0(stem, "_resolved.", ext))
  if (ext == "dta") {
    write_dta(ds, out)
  } else if (ext == "csv") {
    write_csv(ds, out)
  } else if (ext %in% c("xlsx", "xls")) {
    wb <- createWorkbook()
    addWorksheet(wb, "data")
    writeData(wb, "data", ds)
    saveWorkbook(wb, out, overwrite = TRUE)
  } else {
    out <- file.path(dir, paste0(stem, "_resolved.csv"))
    write_csv(ds, out)
  }
  normalizePath(out)
}

empty_findings <- function() {
  tibble::tibble(
    finding_id = character(), check_id = character(), check_module = character(),
    category = character(), issue = character(), submission_id = character(),
    school_id = character(), enumerator = character(),
    start_date = character(), end_date = character(),
    key = character(), value = character()
  )
}

#' Paste one or more ID columns into a single display/sort string.
#' `id_cols` is usually a single column name, but may be a character vector
#' when the survey's unique key is composite (e.g. household_id + member_id).
composite_id_string <- function(df, id_cols, sep = " / ") {
  id_cols <- id_cols[!is.na(id_cols) & nzchar(as.character(id_cols))]
  id_cols <- id_cols[id_cols %in% names(df)]
  if (!length(id_cols)) return(rep("", nrow(df)))
  if (length(id_cols) == 1) return(as.character(df[[id_cols]]))
  parts <- lapply(id_cols, function(cn) as.character(df[[cn]]))
  do.call(paste, c(parts, list(sep = sep)))
}

mk_findings <- function(df, check_id, module, category, issue_chr, roles, value_col = NULL) {
  if (is.null(df) || nrow(df) == 0) return(empty_findings())
  n <- nrow(df)
  sub_id <- if (".hfc_id_display" %in% names(df)) {
    as.character(df[[".hfc_id_display"]])
  } else {
    composite_id_string(df, roles$id, roles$id_sep %||% " / ")
  }
  tibble::tibble(
    finding_id = sprintf("%s-%06d", check_id, seq_len(n)),
    check_id = check_id,
    check_module = module,
    category = category,
    issue = issue_chr,
    submission_id = sub_id,
    school_id = if (!is.null(roles$school) && roles$school %in% names(df)) as.character(df[[roles$school]]) else "",
    enumerator = if (!is.null(roles$enum) && roles$enum %in% names(df)) as.character(df[[roles$enum]]) else "",
    start_date = if (!is.null(roles$start) && roles$start %in% names(df)) as.character(df[[roles$start]]) else "",
    end_date = if (!is.null(roles$end) && roles$end %in% names(df)) as.character(df[[roles$end]]) else "",
    key = if (!is.null(roles$key) && roles$key %in% names(df)) as.character(df[[roles$key]]) else "",
    value = if (!is.null(value_col) && value_col %in% names(df)) as.character(df[[value_col]]) else ""
  )
}
