# Best-effort SurveyCTO / XLSForm relevance (nested / skip-logic) helper.
# Child blanks are expected when parent relevance is false — do not flag as missing (F22).

# Parse survey sheet for name + relevant expressions.
# @return data.frame with columns: name, type, relevant, required
parse_form_relevance <- function(form_path) {
    if (is.null(form_path) || is.na(form_path) || !nzchar(as.character(form_path)) ||
        !file.exists(form_path)) {
        return(data.frame(
        name = character(), type = character(), relevant = character(),
        required = character(), stringsAsFactors = FALSE
        ))
    }
    if (!requireNamespace("readxl", quietly = TRUE)) {
        return(data.frame(
        name = character(), type = character(), relevant = character(),
        required = character(), stringsAsFactors = FALSE
        ))
    }
    sheets <- tryCatch(tolower(readxl::excel_sheets(form_path)), error = function(e) character())
    survey_sheet <- if ("survey" %in% sheets) {
        readxl::excel_sheets(form_path)[match("survey", sheets)]
    } else {
        return(data.frame(
        name = character(), type = character(), relevant = character(),
        required = character(), stringsAsFactors = FALSE
        ))
    }
    surv <- tryCatch(as.data.frame(readxl::read_excel(form_path, sheet = survey_sheet),
                                    stringsAsFactors = FALSE),
                    error = function(e) NULL)
    if (is.null(surv) || !nrow(surv)) {
        return(data.frame(
        name = character(), type = character(), relevant = character(),
        required = character(), stringsAsFactors = FALSE
        ))
    }
    nms <- tolower(names(surv))
    col <- function(want) {
        i <- match(want, nms)
        if (is.na(i)) return(rep(NA_character_, nrow(surv)))
        as.character(surv[[i]])
    }
    out <- data.frame(
        name = col("name"),
        type = col("type"),
        relevant = col("relevant"),
        required = col("required"),
        stringsAsFactors = FALSE
    )
    out <- out[!is.na(out$name) & nzchar(out$name), , drop = FALSE]
    out
}

# Extract referenced variable names from a simple relevant expression.
# Handles patterns like ${var} = '1', ${var} = 1, selected(${var}, 'yes')
relevant_parents <- function(expr) {
    if (is.null(expr) || is.na(expr) || !nzchar(as.character(expr))) return(character())
    expr <- as.character(expr)
    m <- gregexpr("\\$\\{([^}]+)\\}", expr, perl = TRUE)[[1]]
    if (m[1] == -1) return(character())
    starts <- as.integer(m)
    lens <- attr(m, "match.length")
    vapply(seq_along(starts), function(i) {
        sub("^\\$\\{", "", sub("\\}$", "", substr(expr, starts[i], starts[i] + lens[i] - 1L)))
    }, character(1))
}

# Best-effort: is a row "relevant" for a child column given parent values in ds?
# Conservative: if we cannot evaluate, assume relevant (flag blanks).
# For common yes/no parents: relevant when parent is 1 / Yes / yes / TRUE.
row_is_relevant <- function(ds, relevant_expr) {
    n <- nrow(ds)
    if (is.null(relevant_expr) || is.na(relevant_expr) || !nzchar(as.character(relevant_expr))) {
        return(rep(TRUE, n))
    }
    expr <- as.character(relevant_expr)
    parents <- relevant_parents(expr)
    if (!length(parents)) return(rep(TRUE, n))
    # Only evaluate simple single-parent equality / selected patterns
    p <- parents[[1]]
    if (!p %in% names(ds)) return(rep(TRUE, n))
    pv <- as.character(ds[[p]])
    # Detect expected positive values from expression
    pos <- character()
    if (grepl("=\\s*['\"]?(1|yes|true)['\"]?", expr, ignore.case = TRUE)) {
        pos <- c("1", "Yes", "yes", "TRUE", "true")
    } else if (grepl("selected\\s*\\(", expr, ignore.case = TRUE)) {
        m2 <- regmatches(expr, regexpr("['\"]([^'\"]+)['\"]", expr))
        if (length(m2)) pos <- gsub("['\"]", "", m2)
    }
    if (!length(pos)) {
        # If relevant mentions parent but we cannot parse: treat blank parent as not relevant
        return(!(is.na(ds[[p]]) | !nzchar(pv)))
    }
    (pv %in% pos) & !is.na(ds[[p]]) & nzchar(pv)
}

# Filter a candidate "missing" subset: drop rows where child is blank but not relevant.
# @param miss_df rows already flagged as missing on `col`
# @param full_ds full microdata (same row order / ids as used to build miss_df)
# @param col child column name
# @param form_map data.frame from parse_form_relevance
filter_expected_skips <- function(miss_df, full_ds, col, form_map) {
    if (is.null(miss_df) || nrow(miss_df) == 0) return(miss_df)
    if (is.null(form_map) || nrow(form_map) == 0 || !col %in% form_map$name) return(miss_df)
    rel <- form_map$relevant[match(col, form_map$name)]
    if (is.na(rel) || !nzchar(rel)) return(miss_df)
    # Rebuild relevance on full_ds, then keep miss rows that are still relevant
    # Prefer matching by row names / .hfc_row if present
    if (".hfc_row" %in% names(miss_df) && ".hfc_row" %in% names(full_ds)) {
        rel_vec <- row_is_relevant(full_ds, rel)
        keep <- rel_vec[match(miss_df$.hfc_row, full_ds$.hfc_row)]
        keep[is.na(keep)] <- TRUE
        return(miss_df[keep, , drop = FALSE])
    }
    # Fallback: evaluate relevance on miss_df itself (parent cols must be present)
    keep <- row_is_relevant(miss_df, rel)
    miss_df[keep, , drop = FALSE]
}
