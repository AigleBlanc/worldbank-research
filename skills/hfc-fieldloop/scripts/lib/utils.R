# Shared helpers for scripts/lib

# Null-coalescing: falls through to `b` on NULL, zero-length, NA, or "".
`%||%` <- function(a, b) {
    if (is.null(a) || length(a) == 0) return(b)
    if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(as.character(a))))) return(b)
    a
}

# Undo macOS's "~+~" space-encoding in an Rscript --file= path.
decode_file_arg <- function(path) {
    gsub("~+~", " ", path, fixed = TRUE)
}

# Coerce a (possibly labelled) column to plain numeric, NA on failure.
safe_num <- function(x) {
    if (inherits(x, "haven_labelled")) x <- as.vector(x)
    suppressWarnings(as.numeric(x))
}

# Product root: all built artifacts live under <code_output_dir>/hfc/ — the
# git-tracked folder named in config.json's code_output_dir, decoupled from
# wherever the input microdata actually lives.
hfc_root <- function(code_output_dir) {
    file.path(code_output_dir, "hfc")
}

# Build a path under the configured code_output_dir's hfc/ product root.
hfc_path <- function(code_output_dir, ...) {
    file.path(hfc_root(code_output_dir), ...)
}

# A short, stable label for this survey — used in the HTML report title, the
# structure/check-modules preview pages, and the OneDrive report-copy
# filename. Just the basename of the configured input data directory.
derive_project_id <- function(input_data_dir) {
    basename(normalizePath(input_data_dir, mustWork = FALSE))
}

# Read survey microdata (.dta/.csv/.xlsx), optionally subsampled with a fixed seed.
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

# Write agent-fixed data to <sibling of input_data_dir>/intermediate/<stem>.<ext>
# — never inside input_data_dir itself, so raw stays untouched/immutable, and
# never under code_output_dir either (full microdata, agent-fixed or not,
# carries the same privacy sensitivity as raw data and shouldn't land in a
# git-tracked folder). Each fix pass overwrites this one evolving file (not
# a new file per pass), so later fixes build on top of earlier ones.
write_intermediate <- function(ds, input_data_dir, stem, ext) {
    suppressPackageStartupMessages({ library(haven); library(readr); library(openxlsx) })
    # Drop labels that block character mutations / write
    ds <- as.data.frame(lapply(ds, function(col) {
        if (inherits(col, "haven_labelled")) return(as.vector(col))
        col
    }), stringsAsFactors = FALSE)
    dir <- file.path(dirname(normalizePath(input_data_dir, mustWork = FALSE)), "intermediate")
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    ext <- tolower(ext)
    out <- file.path(dir, paste0(stem, ".", ext))
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
        out <- file.path(dir, paste0(stem, ".csv"))
        write_csv(ds, out)
    }
    normalizePath(out)
}

# Load the latest fixed version from <sibling of input_data_dir>/intermediate/
# if a prior fix pass wrote one, else fall back to the original file in
# input_data_dir. `data_file` is always a bare filename (project.yaml stores
# it that way — the file lives directly in the configured input_data_dir,
# never copied elsewhere).
load_latest_dataset <- function(input_data_dir, data_file, sample_n = NA_integer_) {
    stem <- tools::file_path_sans_ext(basename(data_file))
    ext <- tolower(tools::file_ext(data_file))
    intermediate_path <- file.path(dirname(normalizePath(input_data_dir, mustWork = FALSE)), "intermediate", paste0(stem, ".", ext))
    path <- if (file.exists(intermediate_path)) intermediate_path else file.path(input_data_dir, basename(data_file))
    load_microdata(path, sample_n = sample_n)
}

# Zero-row findings tibble with the standard column schema.
empty_findings <- function() {
    tibble::tibble(
        finding_id = character(), check_id = character(), check_module = character(),
        category = character(), issue = character(), submission_id = character(),
        group_id = character(), enumerator = character(),
        start_date = character(), end_date = character(),
        key = character(), value = character(), variable = character(),
        entity_name = character(), group_name = character(), enumerator_name = character(),
        sort_value = double()
    )
}

#' Paste one or more ID columns into a single display/sort string.
#' `id_cols` is usually a single column name, but may be a character vector
#' when the survey's unique key is composite (e.g. household_id + member_id).
composite_id_string <- function(df, id_cols, sep = ":") {
    id_cols <- id_cols[!is.na(id_cols) & nzchar(as.character(id_cols))]
    id_cols <- id_cols[id_cols %in% names(df)]
    if (!length(id_cols)) return(rep("", nrow(df)))
    if (length(id_cols) == 1) return(as.character(df[[id_cols]]))
    parts <- lapply(id_cols, function(cn) as.character(df[[cn]]))
    do.call(paste, c(parts, list(sep = sep)))
}

# Build a findings tibble from flagged rows of df, one row per finding.
# `sort_value_col`: optional numeric column (already present in df) used only
# for display ordering (sort_findings_for_display() in build_outputs.R) — a
# module-specific "how bad is this" magnitude, decoupled from the displayed
# `value` string since that's often not the right sort key as-is (e.g. a raw
# outlier value isn't comparable across positive/negative deviations; a
# formatted datetime string isn't numeric at all). Never exported to
# issue_tracking.xlsx/csv (those pull a fixed named column list).
mk_findings <- function(df, check_id, module, category, issue_chr, roles, value_col = NULL, variable_name = NULL,
                         sort_value_col = NULL) {
    if (is.null(df) || nrow(df) == 0) return(empty_findings())
    n <- nrow(df)
    sub_id <- if (".hfc_id_display" %in% names(df)) {
        as.character(df[[".hfc_id_display"]])
    } else {
        composite_id_string(df, roles$entity_id, roles$entity_id_sep %||% " / ")
    }
    var_suffix <- if (!is.null(variable_name) && nzchar(variable_name)) paste0(":", variable_name) else ""
    tibble::tibble(
        finding_id = paste0(tolower(module), ":", sub_id, var_suffix),
        check_id = check_id,
        check_module = module,
        category = category,
        issue = issue_chr,
        submission_id = sub_id,
        group_id = if (!is.null(roles$group) && roles$group %in% names(df)) as.character(df[[roles$group]]) else "",
        enumerator = if (!is.null(roles$enum) && roles$enum %in% names(df)) as.character(df[[roles$enum]]) else "",
        start_date = if (!is.null(roles$start) && roles$start %in% names(df)) as.character(df[[roles$start]]) else "",
        end_date = if (!is.null(roles$end) && roles$end %in% names(df)) as.character(df[[roles$end]]) else "",
        key = if (!is.null(roles$key) && roles$key %in% names(df)) as.character(df[[roles$key]]) else "",
        value = if (!is.null(value_col) && value_col %in% names(df)) as.character(df[[value_col]]) else "",
        variable = variable_name %||% "",
        entity_name = if (!is.null(roles$entity_name_field) && roles$entity_name_field %in% names(df)) as.character(df[[roles$entity_name_field]]) else "",
        group_name = if (!is.null(roles$group_name) && roles$group_name %in% names(df)) as.character(df[[roles$group_name]]) else "",
        enumerator_name = if (!is.null(roles$enum_name) && roles$enum_name %in% names(df)) as.character(df[[roles$enum_name]]) else "",
        sort_value = if (!is.null(sort_value_col) && sort_value_col %in% names(df)) suppressWarnings(as.numeric(df[[sort_value_col]])) else NA_real_
    )
}

# mk_findings() assigns finding_id = "<module>:<entity>[:<variable>]" per call,
# but can't see across other calls/modules — two separate findings can end up
# with the same base id (e.g. M2 duplicate rows: same module, same entity, no
# variable to disambiguate). Run once over the FULL combined findings tibble
# to suffix any repeats :2, :3, ... in row order, keeping the first occurrence
# bare so ids stay stable/content-derived rather than purely positional.
dedupe_finding_ids <- function(findings) {
    if (is.null(findings) || nrow(findings) == 0) return(findings)
    dupn <- ave(seq_len(nrow(findings)), findings$finding_id, FUN = seq_along)
    findings$finding_id <- ifelse(dupn > 1, paste0(findings$finding_id, ":", dupn), findings$finding_id)
    findings
}
