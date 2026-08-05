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
    sd_multiplier <- modules$M7$sd_multiplier %||% 2
    vars <- fmt_var_list(modules$M7$vars %||% character())
    var_clause <- if (nzchar(vars)) sprintf(" on: %s", vars) else ""
    sprintf(
        "Flags enumerators whose missingness rate is more than %sx the between-enumerator SD above the survey average%s.",
        sd_multiplier, var_clause
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
    enum_pct <- round(100 * (modules$M9$enum_threshold_pct %||% 0.8))
    survey_pct <- round(100 * (modules$M9$survey_threshold_pct %||% 0.8))
    sprintf(
        "Flags enumerators who gave the same answer on a question in %s%%+ of their interviews, and submissions where %s%%+ of ordinal/Likert-style answers are identical.",
        enum_pct, survey_pct
    )
}

m12_desc <- function(modules) {
    min_dur <- modules$M12$min_duration_sec %||% 5
    max_dur <- modules$M12$max_duration_sec %||% 3600
    min_audio <- modules$M12$min_audio_bytes %||% 1024L
    min_image <- modules$M12$min_image_bytes %||% 2048L
    sprintf(
        "Flags problems with recorded audio/photo files: missing files, empty filename cells, files below %s bytes (audio) / %s bytes (image), audio duration outside [%s, %s]s, wrong file types, or duplicates.",
        min_audio, min_image, min_dur, max_dur
    )
}

DYNAMIC_MODULE_DESC <- list(
    M4 = m4_desc, M5 = m5_desc, M6 = m6_desc, M7 = m7_desc,
    M8 = m8_desc, M9 = m9_desc, M12 = m12_desc
)
