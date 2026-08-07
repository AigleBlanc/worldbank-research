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
    sprintf(
        "Reports how long interviews took, in minutes, overall and by enumerator, and flags individual interviews more than %s SD above or below the mean.",
        sd_rule
    )
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
    sprintf("Flags interviews conducted at unusual times — %s — using each submission's local time zone.", clause)
}

m6_desc <- function(modules) {
    sd_rule <- modules$M6$sd_rule %||% 3
    vars <- fmt_var_list(modules$M6$vars %||% character())
    var_clause <- if (nzchar(vars)) sprintf(" on: %s", vars) else ""
    sprintf(
        "Flags unusually high or low values (beyond %s SD from the mean) on key numeric questions%s.",
        sd_rule, var_clause
    )
}

m7_desc <- function(modules) {
    var_issue <- round(100 * (modules$M7$var_issue_threshold %||% 0.5))
    pool <- round(100 * (modules$M7$enum_pool_threshold %||% 0.9))
    enum_pct <- round(100 * (modules$M7$enum_pct_threshold %||% 0.5))
    vars <- fmt_var_list(modules$M7$vars %||% character())
    var_clause <- if (nzchar(vars)) sprintf(" on: %s", vars) else ""
    sprintf(
        "Reports missingness on key survey questions%s, flagging any variable more than %s%% missing overall. For the worst variables (%s%%+ missing overall), also flags any enumerator whose own missingness on that variable is %s%%+.",
        var_clause, var_issue, pool, enum_pct
    )
}

m8_desc <- function(modules) {
    thr <- modules$M8$threshold_m %||% 300
    sprintf(
        "Flags submissions recorded more than %s meters from the median location of other submissions at that site.",
        thr
    )
}

m9_desc <- function(modules) {
    enum_pct <- round(100 * (modules$M9$enum_threshold_pct %||% 0.9))
    survey_pct <- round(100 * (modules$M9$survey_threshold_pct %||% 0.9))
    sprintf(
        "Flags enumerators who gave the same answer on a question in %s%%+ of their interviews, and submissions where %s%%+ of ordinal/Likert-style answers are identical.",
        enum_pct, survey_pct
    )
}

m11_desc <- function(modules) {
    "Flags a media-indicating column (audio, image, or qualitative-capture) that is completely empty across every surveyed row — usually a form/coding problem (the field isn't showing up in the enumerator's app, or the question is misconfigured), not a per-row file-hygiene issue."
}

DYNAMIC_MODULE_DESC <- list(
    M2 = m2_desc, M4 = m4_desc, M5 = m5_desc, M6 = m6_desc, M7 = m7_desc,
    M8 = m8_desc, M9 = m9_desc, M11 = m11_desc
)
