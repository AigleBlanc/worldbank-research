# Shared helpers for scripts/lib

# Null-coalescing: falls through to `b` on NULL, zero-length, NA, or "".
`%||%` <- function(a, b) {
    if (is.null(a) || length(a) == 0) return(b)
    if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(as.character(a))))) return(b)
    a
}

# Coerce a (possibly labelled) column to plain numeric, NA on failure.
safe_num <- function(x) {
    if (inherits(x, "haven_labelled")) x <- as.vector(x)
    suppressWarnings(as.numeric(x))
}

# Single shared rounding convention for every data-derived value shown in
# the HTML report or issue tracking sheet (means/medians/SDs, GPS distance,
# outlier values, durations, percentages) - 1 decimal place, never 3.
# Does NOT apply to threshold-describing prose (e.g. "flags values below
# 50% missing") - those describe a configured setting, not a measured
# value, and stay at 0 decimals via their own sprintf("%.0f%%", ...) calls.
round1 <- function(x) round(suppressWarnings(as.numeric(x)), 1)

# One finding-date-per-row, truncated to a bare "YYYY-MM-DD" string,
# preferring start_date and falling back to end_date - shared by every
# place that needs to compare a finding against a specific calendar day
# (the Last Day filter, the issues-table Date column, chronological sort).
# `findings$start_date`/`end_date` (mk_findings(), this file) store the
# RAW, untruncated roles$start/roles$end value (e.g. a full timestamp
# string) - as.Date() safely truncates that to just the date (confirmed:
# as.Date("2026-06-30 10:00:00") -> "2026-06-30", NA-safe on blank/NA
# input), unlike a naive exact-string comparison against a bare date like
# roles$last_date, which never matches a full-timestamp start/end column.
finding_date_vec <- function(df) {
    if (is.null(df) || !nrow(df)) return(character())
    sd <- if ("start_date" %in% names(df)) as.character(df$start_date) else rep(NA_character_, nrow(df))
    ed <- if ("end_date" %in% names(df)) as.character(df$end_date) else rep(NA_character_, nrow(df))
    raw <- ifelse(!is.na(sd) & nzchar(sd), sd, ed)
    suppressWarnings(as.character(as.Date(raw)))
}

# Clean, human-readable display name for a raw survey column (e.g.
# price_rice_kg -> "Rice price (kg)") - roles$var_labels (role_map.yaml) is
# a {colname: "Clean Label"} map generated once, silently, by agent
# judgment at setup time (SKILL.md A2, same posture as M7's extra-vars
# pick) from the column name + its instrument question label, covering
# every column that can actually surface in a finding. Falls back to the
# raw column name when unset - matters for a rebuild against an older
# config that predates this field, or any column outside that pool. Use
# this ONLY for human-facing sentence/table text; the raw column name
# stays in mk_findings()'s `variable_name` (-> issue_tracking.xlsx's
# "Variable (DIME use)" column), documented for programmatic/DIME reuse.
# Vectorized: a single colname or a vector of them (e.g. joining several
# flagged variables into one sentence).
var_label <- function(colname, roles) {
    labels <- roles$var_labels %||% list()
    vapply(colname, function(cn) {
        if (is.na(cn) || !nzchar(as.character(cn))) return(as.character(cn))
        labels[[cn]] %||% cn
    }, character(1), USE.NAMES = FALSE)
}

#' Decode a Stata/SurveyCTO value-labelled column (e.g. 1/2/3 with attached
#' labels "Name 1"/"Name 2"/"Name 3") to its label text. Common SurveyCTO
#' pattern: the enumerator/group field IS the labelled ID, with no separate
#' name column at all, so this is what makes those names show up anywhere
#' rather than raw codes. Values with no matching label fall back to their
#' own printed value (haven::as_factor()'s default), never an error. A
#' plain (non-labelled) column passes through unchanged.
decode_labelled_chr <- function(x) {
    if (inherits(x, "haven_labelled")) {
        return(as.character(haven::as_factor(x)))
    }
    as.character(x)
}

#' Resolve a per-row display name for an enumerator/group ID column: the
#' separate name column when one was found (roles$enum_name/group_name),
#' else the ID column's own decoded value labels, else NA. Never applied to
#' the respondent/entity ID — that stays anonymous by design (see
#' roles$entity_display / resolve_display_vec()).
resolve_unit_name <- function(ds, id_col, name_col) {
    if (!is.null(name_col) && !is.na(name_col) && name_col %in% names(ds)) {
        return(as.character(ds[[name_col]]))
    }
    # Only decode when the ID column is genuinely value-labelled (has actual
    # names attached) - an unlabelled ID still returns blank here, same as
    # before this fallback existed, preserving "never fall back to
    # duplicating the ID" (see pick_name_field()'s doc comment above).
    if (!is.null(id_col) && !is.na(id_col) && id_col %in% names(ds) &&
        inherits(ds[[id_col]], "haven_labelled")) {
        return(decode_labelled_chr(ds[[id_col]]))
    }
    rep("", nrow(ds))
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

#' Resolve a display vector for an ID+optional-name pair, honoring a
#' "name"|"id" display mode (roles$entity_display/enumerator_display/
#' group_display — see profile_roles.R). "id" (or no name vector available)
#' returns the raw ID; "name" coalesces to the name wherever it's non-blank,
#' else falls back to the ID. This is the one place the
#' de-identification-by-default policy is enforced: entity defaults to "id"
#' (we never have the surveyed individual's real name), enumerator/group
#' default to "name" (we do have those) — a project can flip either via a
#' silent role_map.yaml override, never guessed, only set on explicit
#' request. Two use shapes: pre-aggregation (run_checks.R, working directly
#' off `ds[[roles$enum]]`/`ds[[roles$enum_name]]`) and post-hoc
#' (build_outputs.R, working off findings' already-extracted id/name
#' columns) — both are just two parallel character vectors once extracted.
resolve_display_vec <- function(id_vals, name_vals, mode = "name") {
    id_vals <- as.character(id_vals)
    if (identical(mode, "id") || is.null(name_vals)) return(id_vals)
    name_vals <- as.character(name_vals)
    ifelse(!is.na(name_vals) & nzchar(name_vals), name_vals, id_vals)
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
        value = if (!is.null(value_col) && value_col %in% names(df)) decode_labelled_chr(df[[value_col]]) else "",
        variable = variable_name %||% "",
        # Entity/respondent stays exactly as-is here (never decoded from the
        # ID's own value labels) - anonymity by design, see roles$entity_display.
        entity_name = if (!is.null(roles$entity_name_field) && roles$entity_name_field %in% names(df)) as.character(df[[roles$entity_name_field]]) else "",
        group_name = resolve_unit_name(df, roles$group, roles$group_name),
        enumerator_name = resolve_unit_name(df, roles$enum, roles$enum_name),
        sort_value = if (!is.null(sort_value_col) && sort_value_col %in% names(df)) suppressWarnings(as.numeric(df[[sort_value_col]])) else NA_real_
    )
}

#' One finding per AGGREGATE UNIT (an enumerator or a group/site), never one
#' per underlying submission row. Deliberately leaves submission_id/
#' entity_name/key blank — an aggregate finding was never established at the
#' entity level, so nothing entity-shaped should appear downstream (HTML
#' table, xlsx/csv Entity ID column) for it.
#' `unit_df`: one row per flagged unit, already aggregated by the caller
#' (e.g. check_m7()'s `by_e` table filtered to the flagged enumerators) — NOT
#' the raw microdata. Must have a `unit_id` column (the raw enumerator/group
#' ID); an optional `unit_name` column (display name, NA/blank if
#' unavailable) is used for `enumerator_name`/`group_name`. Optional
#' `date_col`: for a unit-level check that's scoped to a single day (e.g.
#' M8's per-enumerator-per-day straightlining), the column in `unit_df`
#' holding that day's date — populates start_date/end_date (both, so
#' finding_date_vec()'s start-preferred/end-fallback logic sees it either
#' way) instead of leaving them blank, AND is folded into finding_id so the
#' same unit flagged on two different days gets two distinct findings, not a
#' collision. Omitted (default) preserves the fully dateless aggregate
#' finding used by M1/M7 (a standing structural flag, not tied to one day).
mk_aggregate_finding <- function(unit_df, check_id, module, category, issue_chr, roles,
                                  unit_type = c("enumerator", "group"),
                                  value_col = NULL, variable_name = NULL, sort_value_col = NULL,
                                  date_col = NULL) {
    unit_type <- match.arg(unit_type)
    if (is.null(unit_df) || nrow(unit_df) == 0) return(empty_findings())
    n <- nrow(unit_df)
    unit_id <- as.character(unit_df$unit_id)
    unit_name <- if ("unit_name" %in% names(unit_df)) as.character(unit_df$unit_name) else rep(NA_character_, n)
    unit_name <- ifelse(is.na(unit_name), "", unit_name)
    var_suffix <- if (!is.null(variable_name) && nzchar(variable_name)) paste0(":", variable_name) else ""
    date_vals <- if (!is.null(date_col) && date_col %in% names(unit_df)) as.character(unit_df[[date_col]]) else rep("", n)
    date_suffix <- ifelse(nzchar(date_vals), paste0(":", date_vals), "")
    tibble::tibble(
        finding_id = paste0(tolower(module), ":", unit_type, ":", unit_id, var_suffix, date_suffix),
        check_id = check_id,
        check_module = module,
        category = category,
        issue = if (length(issue_chr) == n) issue_chr else rep(issue_chr, n),
        submission_id = "",
        group_id = if (unit_type == "group") unit_id else "",
        enumerator = if (unit_type == "enumerator") unit_id else "",
        start_date = date_vals,
        end_date = date_vals,
        key = "",
        value = if (!is.null(value_col) && value_col %in% names(unit_df)) as.character(unit_df[[value_col]]) else "",
        variable = variable_name %||% "",
        entity_name = "",
        group_name = if (unit_type == "group") unit_name else "",
        enumerator_name = if (unit_type == "enumerator") unit_name else "",
        sort_value = if (!is.null(sort_value_col) && sort_value_col %in% names(unit_df)) suppressWarnings(as.numeric(unit_df[[sort_value_col]])) else NA_real_
    )
}

#' Row-selection for a single module — the full dataset vs. the completed/
#' surveyed subset only, per `modules[[mod_code]]$full_data` (default_
#' modules(), profile_roles.R, sets this TRUE only for M1 — M1 needs the
#' complete picture to compute completion rates; every other module defaults
#' to completed rows only, per the completion redesign). Shared by
#' run_check_modules() (the live build, run_checks.R) AND every standalone
#' assets/check_templates/*.R script, so a hand-edited full_data in
#' modules.yaml is honored identically in both places — a template can no
#' longer silently diverge from the live report by hardcoding its own
#' completed-only filter (the drift this helper replaces).
ds_for_module_selection <- function(ds_full, mod_code, modules) {
    if (isTRUE(modules[[mod_code]]$full_data)) return(ds_full)
    if (!".hfc_completed" %in% names(ds_full) || all(ds_full$.hfc_completed)) return(ds_full)
    filtered <- ds_full[ds_full$.hfc_completed, , drop = FALSE]
    attr(filtered, "hfc_form_map") <- attr(ds_full, "hfc_form_map")
    filtered
}

#' One finding per DUPLICATE-KEY GROUP (M2 Duplicates only), never one per
#' underlying duplicate row (report_sections.json: "one row per duplicate
#' GROUP rather than one row per individual duplicate submission" — every
#' submission's timestamp goes into Value instead, e.g. "2 submissions:
#' 2026-08-13 03:16, 2026-08-13 04:01"). `df` is already filtered to
#' duplicate rows only; `group_cols` is the key the duplicates were detected
#' on (may include disambiguating extra_keys beyond the entity ID itself);
#' `id_cols` is the entity ID column(s) actually shown (report_sections.json:
#' the only identifying column on this table — no Date/Group/Enumerator).
#' start_date/end_date are deliberately left blank, same as M1/M7's
#' enumerator/group aggregates — a duplicate group can span several
#' different days, so there is no single "the" date for it, only the list
#' already captured in Value (finding_date_vec()/sort_findings_for_display()
#' already treat a blank date as a dateless aggregate finding, sorting it
#' last within its module, same as those). `time_col`: roles$start, falling
#' back to roles$end, used only to format Value's per-submission list.
mk_duplicate_group_findings <- function(df, group_cols, id_cols, check_id, module, category, issue_chr, roles, time_col = NA_character_) {
    if (is.null(df) || nrow(df) == 0) return(empty_findings())
    group_cols <- group_cols[group_cols %in% names(df)]
    if (!length(group_cols)) return(empty_findings())
    grp_key <- composite_id_string(df, group_cols, sep = "")
    splits <- split(seq_len(nrow(df)), grp_key)
    rows <- lapply(splits, function(idx) {
        sub <- df[idx, , drop = FALSE]
        sub_id <- composite_id_string(sub[1, , drop = FALSE], id_cols, roles$entity_id_sep %||% " / ")
        times <- if (!is.na(time_col) && time_col %in% names(sub)) {
            format(parse_datetime_col(sub[[time_col]]), "%Y-%m-%d %H:%M")
        } else {
            rep(NA_character_, nrow(sub))
        }
        times <- times[!is.na(times)]
        val <- if (length(times)) {
            sprintf("%d submissions: %s", nrow(sub), paste(times, collapse = ", "))
        } else {
            sprintf("%d submissions", nrow(sub))
        }
        tibble::tibble(
            finding_id = paste0(tolower(module), ":", sub_id),
            check_id = check_id, check_module = module, category = category,
            issue = issue_chr, submission_id = sub_id,
            group_id = "", enumerator = "", start_date = "", end_date = "", key = "",
            value = val, variable = "",
            entity_name = "", group_name = "", enumerator_name = "",
            sort_value = NA_real_
        )
    })
    dplyr::bind_rows(rows)
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
