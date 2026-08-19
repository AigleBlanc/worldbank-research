# Dynamic, config-aware module descriptions — one function per module whose
# report section description should state the actual configured threshold
# for THIS project, rather than a generic static sentence (MODULE_META's
# static `desc` in build_outputs.R remains the fallback if a project's
# modules.yaml is missing/malformed, or for modules with no configurable
# threshold at all). Each function takes the project's confirmed `modules`
# list and returns a single description string. Dispatched from
# module_desc(code, modules) in build_outputs.R, wrapped in tryCatch there so
# a malformed config degrades to the static text rather than erroring the
# whole report build.

# "a, b, c, and N more" — keeps a variable list readable in a sentence.
fmt_var_list <- function(vars, n = 4) {
    vars <- vars[!is.na(vars) & nzchar(as.character(vars))]
    if (!length(vars)) return("")
    if (length(vars) <= n) return(paste(vars, collapse = ", "))
    paste0(paste(utils::head(vars, n), collapse = ", "), ", and ", length(vars) - n, " more")
}

m1_desc <- function(modules) {
    sig <- modules$M1$completion_signal %||% NA_character_
    var <- modules$M1$completion_var %||% NA_character_
    pct_median <- round(100 * (modules$M1$pct_median %||% 0.5))
    method <- if (identical(sig, "gating")) {
        gates <- fmt_var_list(modules$M1$gate_cols %||% character(), n = 4)
        if (nzchar(gates)) {
        sprintf("complete only if it passes every confirmed gate: %s (a fail on any one is a non-completion, with a Reason recorded)", gates)
        } else {
        "complete only if it passes every confirmed gate"
        }
    } else if (identical(sig, "status")) {
        sprintf("complete when its%s status column marks it Complete", if (!is.na(var)) sprintf(" `%s`", var) else "")
    } else if (identical(sig, "roster")) {
        "complete when it matches an entry in the project's target/roster file"
    } else if (identical(sig, "primary_secondary")) {
        sprintf("complete when its%s column marks it Primary sample", if (!is.na(var)) sprintf(" `%s`", var) else "")
    } else if (!is.na(var)) {
        sprintf("complete when its `%s` column looks affirmative, or (if that's blank) at least 90%% of its fields are filled in", var)
    } else {
        "complete once at least 90% of its fields are filled in"
    }
    daily_target <- suppressWarnings(as.numeric(modules$M1$daily_target_per_enum %||% NA_real_))
    daily_clause <- if (!is.na(daily_target)) {
        sprintf(" Also flags any enumerator whose submissions on a given day fall below the confirmed daily target of %s.", daily_target)
    } else ""
    repl_configured <- !is.na(modules$M1$replacement_status_col %||% NA_character_) &&
        !is.na(modules$M1$replacement_rank_col %||% NA_character_) &&
        !is.na(modules$M1$replacement_group_col %||% NA_character_)
    repl_clause <- if (repl_configured) {
        " Also reports, by group, what share of the targeted primary sample was replaced, and flags any group where a replacement completed out of order (an earlier-ranked replacement with no row in the data at all)."
    } else ""
    sprintf(
        "A submission counts %s. Reports these counts overall, by group, enumerator, and date, and flags any group below %s%% of the median completion count.%s%s",
        method, pct_median, daily_clause, repl_clause
    )
}

m2_desc <- function(modules) {
    key_cols <- c(modules$M2$id, modules$M2$extra_keys %||% character())
    key <- fmt_var_list(key_cols, n = 6)
    key_clause <- if (nzchar(key)) sprintf("the same %s", key) else "the same unique ID or survey key"
    sprintf(
        "Flags submissions that share %s, which usually means the same interview was uploaded or entered more than once.",
        key_clause
    )
}

m4_desc <- function(modules) {
    sd_rule <- modules$M4$sd_rule %||% 3
    base <- sprintf(
        "Reports how long interviews took, in minutes, overall and by enumerator, and flags individual interviews more than %s SD below the mean.",
        sd_rule
    )
    if (isTRUE(modules$M4$advanced_long_flag$on)) {
        base <- paste0(base, sprintf(
            " Advanced flagging is on for this project: interviews more than %s SD above the mean are also flagged.",
            sd_rule
        ))
    }
    base
}

m5_desc <- function(modules) {
    evening_hour <- modules$M5$evening_hour %||% 19
    morning_hour <- modules$M5$morning_hour %||% 7
    flag_weekend <- isTRUE(modules$M5$flag_weekend %||% TRUE)
    hrs <- sprintf("%02d:00-%02d:00", morning_hour, evening_hour)
    clause <- if (flag_weekend) {
        sprintf("weekends, or outside %s local time", hrs)
    } else {
        sprintf("outside %s local time", hrs)
    }
    sprintf("Flags interviews conducted at unusual times (%s), using each submission's local time zone.", clause)
}

m6_desc <- function(modules) {
    vars <- fmt_var_list(modules$M6$vars %||% character())
    var_clause <- if (nzchar(vars)) sprintf(" on: %s", vars) else ""
    if (identical(modules$M6$outlier_mode %||% "sd", "fixed") && length(modules$M6$fixed_thresholds %||% list())) {
        sprintf("Flags values outside a fixed, project-supplied range on key numeric questions%s.", var_clause)
    } else {
        sd_rule <- modules$M6$sd_rule %||% 3
        sprintf(
        "Flags unusually high or low values (beyond %s SD from the mean) on key numeric questions%s.",
        sd_rule, var_clause
        )
    }
}

m7_desc <- function(modules) {
    vars <- fmt_var_list(modules$M7$vars %||% character())
    var_clause <- if (nzchar(vars)) sprintf(" on: %s", vars) else ""
    base <- sprintf("Reports missingness on key survey questions%s. Descriptive only, not flagged as an issue.", var_clause)
    if (isTRUE(modules$M7$advanced_enum_flag$on)) {
        var_issue <- round(100 * (modules$M7$var_issue_threshold %||% 0.5))
        pool <- round(100 * (modules$M7$enum_pool_threshold %||% 0.9))
        enum_pct <- round(100 * (modules$M7$enum_pct_threshold %||% 0.5))
        base <- paste0(base, sprintf(
            " Advanced flagging is on for this project: any variable more than %s%% missing overall is treated as an issue, and for the worst variables (%s%%+ missing overall), any enumerator whose own missingness on that variable is %s%%+ is also flagged.",
            var_issue, pool, enum_pct
        ))
    }
    base
}

m10_desc <- function(modules) {
    base <- "Plots every submission with a valid coordinate on a map, for visual review. Descriptive only, not flagged as an issue by default."
    if (isTRUE(modules$M10$advanced_distance_flag$on)) {
        thr <- modules$M10$advanced_distance_flag$threshold_m %||% 300
        base <- paste0(base, sprintf(
            " Advanced flagging is on for this project: submissions recorded more than %s meters from the median location of other submissions at that site are flagged and shown in red.",
            thr
        ))
    }
    base
}

m8_desc <- function(modules) {
    enum_pct <- round(100 * (modules$M8$enum_threshold_pct %||% 1.0))
    survey_pct <- round(100 * (modules$M8$survey_threshold_pct %||% 0.9))
    sprintf(
        "Flags enumerators who gave the same answer on a question in %s%%+ of their interviews on a single day (minimum 3 that day), and submissions where %s%%+ of ordinal/Likert-style answers are identical.",
        enum_pct, survey_pct
    )
}

m13_desc <- function(modules) {
    "Flags a media-indicating column (audio, image, or qualitative-capture) that is completely empty across every surveyed row: usually a form/coding problem (the field isn't showing up in the enumerator's app, or the question is misconfigured), not a per-row file-hygiene issue."
}

DYNAMIC_MODULE_DESC <- list(
    M1 = m1_desc, M2 = m2_desc, M4 = m4_desc, M5 = m5_desc, M6 = m6_desc, M7 = m7_desc,
    M10 = m10_desc, M8 = m8_desc, M13 = m13_desc
)

#' Dynamic description for the "Other" section (report_sections.json: should
#' specify what's actually found, not a generic sentence). Unlike the
#' MODULE_DESC functions above, this is findings-dependent rather than
#' config-dependent — "Other" isn't its own module, it's the split-off part
#' of M9's output (see build_outputs.R's write_html_report()), so it takes
#' the already-computed `other_sub` findings subset directly. `other_sub`:
#' the "Other" section's own findings data frame (category != "field_
#' request"), already filtered by the caller. `module_notes_custom`:
#' `module_notes$custom`, used to resolve a category to its registered
#' check's human label when one exists; falls back to a prettified version
#' of the raw category string otherwise.
other_section_desc <- function(other_sub, module_notes_custom = NULL) {
    base <- "Findings outside the standard checks and Field Request."
    if (is.null(other_sub) || nrow(other_sub) == 0) return(base)
    cats <- sort(unique(as.character(other_sub$category)))
    cats <- cats[!is.na(cats) & nzchar(cats)]
    if (!length(cats)) return(base)
    cat_labels <- vapply(cats, function(cg) {
        entry <- module_notes_custom[[cg]]
        lbl <- entry$label %||% NA_character_
        if (!is.na(lbl) && nzchar(lbl)) return(lbl)
        gsub("(^|\\s)([a-z])", "\\1\\U\\2", gsub("_", " ", cg), perl = TRUE)
    }, character(1))
    n <- nrow(other_sub)
    sprintf(
        "Findings outside the standard checks and Field Request — %d issue%s found this run: %s.",
        n, if (n == 1) "" else "s", paste(cat_labels, collapse = ", ")
    )
}
