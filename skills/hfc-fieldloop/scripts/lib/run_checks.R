# Run M1-M13 checks given ds, roles, modules config.
# Returns list(findings = <tibble>, stats = <named list of data.frames per module>).
# Optional code_output_dir: sources custom checks from hfc/code/checks/*.R (run_<name>).
#
# Each module's check logic lives in its own check_mN(ds, roles, modules)
# function, returning list(findings = <tibble>, stats = <df or list-of-df>)
# (only the keys that apply). run_check_modules() is a thin orchestrator that
# calls prepare_ds_for_checks() once, then each check_mN() in module order,
# wrapping each in the same per-module tryCatch() as before. This same
# check_mN()/prepare_ds_for_checks() pair is what a standalone
# hfc/code/checks/Mx_y.R script calls to reproduce one module's findings in
# isolation: `ds <- prepare_ds_for_checks(ds, roles, code_output_dir);
# res <- check_mN(ds, roles, modules); res$findings <- dedupe_finding_ids(res$findings)`
# — safe because dedupe_finding_ids() only ever disambiguates collisions
# *within* a module (finding_id is always module-prefixed), so deduping one
# module's findings alone gives byte-identical ids to deduping the full
# combined pipeline, as long as each check_mN() preserves its own internal
# row order (documented per-function below where it matters).
#
# M10 (fully agent-authored per project, dynamically sourced) and M11
# (already delegated to run_m11_media_checks() in media.R) are intentionally
# NOT extracted — there is no inline logic to pull out for either.
#
# Intentional divergence from the full-pipeline path: run_check_modules()
# wraps each check_mN() call in tryCatch() so one module's error doesn't
# abort the rest of the build; a standalone script calling check_mN()
# directly does NOT swallow errors, so a real traceback surfaces when
# debugging one module in isolation.

#' Resolve a per-row IANA timezone: one global tz (single-country mode) or a
#' per-row lookup via a confirmed country column (multi-country mode).
resolve_row_timezone <- function(ds, roles) {
    n <- nrow(ds)
    if (identical(roles$country_mode, "multi") &&
        !is.null(roles$country_col) && !is.na(roles$country_col) &&
        roles$country_col %in% names(ds)) {
        map <- roles$country_timezone_map %||% list()
        vals <- as.character(ds[[roles$country_col]])
        tz <- vapply(vals, function(v) {
        t <- map[[v]]
        if (is.null(t) || !nzchar(t)) NA_character_ else t
        }, character(1), USE.NAMES = FALSE)
        return(tz)
    }
    rep(roles$timezone %||% Sys.timezone(), n)
}

#' Extract local hour-of-day and ISO weekday (1=Mon..7=Sun) from a naive
#' datetime vector, honoring a possibly-different timezone per row. R's
#' POSIXct only carries one tzone attribute for an entire vector, so each
#' timezone group is force_tz()'d and read back separately, then only the
#' extracted (non-POSIXct) hour/weekday numbers are recombined.
local_daypart <- function(dt, tz_vec) {
    n <- length(dt)
    hr <- rep(NA_real_, n)
    wd <- rep(NA_integer_, n)
    tz_vec <- as.character(tz_vec)
    tz_vec[is.na(tz_vec) | !nzchar(tz_vec)] <- Sys.timezone()
    for (tz in unique(tz_vec)) {
        idx <- which(tz_vec == tz & !is.na(dt))
        if (!length(idx)) next
        sub <- tryCatch(lubridate::force_tz(dt[idx], tzone = tz), error = function(e) dt[idx])
        hr[idx] <- lubridate::hour(sub) + lubridate::minute(sub) / 60
        wd[idx] <- lubridate::wday(sub, week_start = 1)
    }
    list(hour = hr, wday = wd)
}

#' Same per-timezone-group force_tz() approach as local_daypart(), extended
#' to also return each row's local calendar date and exact minute (not just
#' fractional hour) - needed for grouping by day and formatting an exact
#' HH:MM clock time (the daily earliest/latest start/end table), which
#' local_daypart()'s hour-only contract doesn't provide. Extraction happens
#' entirely inside each per-timezone group's loop iteration and is never
#' recombined as POSIXct afterward - a POSIXct vector has exactly one
#' tzone attribute for its whole length, so values force_tz()'d to
#' different zones and then merged into one vector would each still be
#' numerically correct, but every subsequent as.Date()/format() call would
#' silently reinterpret them all in whatever zone that merged vector
#' happens to carry (confirmed: as.Date.POSIXct()'s default tz="" argument
#' uses the SYSTEM timezone, not the input's own attached tzone - an easy,
#' silent date-off-by-one trap this sidesteps by always passing tz=
#' explicitly and only ever combining plain numbers/strings, never POSIXct,
#' across timezone groups).
local_date_hm <- function(dt, tz_vec) {
    n <- length(dt)
    date <- rep(NA_character_, n)
    hour <- rep(NA_integer_, n)
    minute <- rep(NA_integer_, n)
    tz_vec <- as.character(tz_vec)
    tz_vec[is.na(tz_vec) | !nzchar(tz_vec)] <- Sys.timezone()
    for (tz in unique(tz_vec)) {
        idx <- which(tz_vec == tz & !is.na(dt))
        if (!length(idx)) next
        sub <- tryCatch(lubridate::force_tz(dt[idx], tzone = tz), error = function(e) dt[idx])
        date[idx] <- as.character(as.Date(sub, tz = tz))
        hour[idx] <- lubridate::hour(sub)
        minute[idx] <- lubridate::minute(sub)
    }
    list(date = date, hour = hour, minute = minute)
}

#' Parse a start/end timestamp column into a naive POSIXct vector, trying a
#' couple of common SurveyCTO export formats.
parse_datetime_col <- function(x) {
    x <- as.character(x)
    dt <- suppressWarnings(lubridate::ymd_hms(x, quiet = TRUE))
    if (sum(!is.na(dt)) < 0.5 * length(x)) {
        dt <- suppressWarnings(lubridate::parse_date_time(
        x, orders = c("Ymd HMS", "mdy HMS", "Ymd HM", "mdy HM", "Ymd", "mdy"), quiet = TRUE
        ))
    }
    dt
}

#' Small per-enumerator ID -> display-name lookup table (.enum, .ename),
#' decoding a value-labelled ID column via resolve_unit_name() (utils.R)
#' whenever there's no separate name column - the common SurveyCTO pattern
#' where the enumerator field is just a coded ID with attached value labels.
#' Shared by every check_mN() that aggregates by enumerator and then needs
#' to attach a display name to the raw ID afterward (M1, M4, M7, M9, M13).
#' NULL when there's no usable enumerator column at all.
enum_name_lookup <- function(ds, roles) {
  if (is.na(roles$enum) || !roles$enum %in% names(ds)) return(NULL)
  ename_vec <- resolve_unit_name(ds, roles$enum, roles$enum_name)
  tibble(.enum = as.character(ds[[roles$enum]]), .ename = ename_vec) %>%
    dplyr::filter(!is.na(.enum), nzchar(.enum)) %>%
    dplyr::group_by(.enum) %>%
    dplyr::summarise(.ename = dplyr::first(stats::na.omit(.ename), default = NA_character_), .groups = "drop")
}

#' Row-wise fraction of missing/blank cells across a set of columns.
row_missing_ratio <- function(ds, cols) {
    cols <- cols[cols %in% names(ds)]
    if (!length(cols)) return(rep(0, nrow(ds)))
    m <- vapply(cols, function(cn) {
        x <- ds[[cn]]
        if (is.character(x) || is.factor(x)) is.na(x) | !nzchar(as.character(x)) else is.na(x)
    }, logical(nrow(ds)))
    if (is.null(dim(m))) m <- matrix(m, nrow = nrow(ds))
    rowMeans(m)
}

#' TRUE where a value looks like a "yes/complete/positive" indicator.
is_complete_value <- function(x) {
    s <- tolower(trimws(as.character(x)))
    s %in% c("1", "yes", "y", "true", "complete", "completed", "full")
}

#' Count + percent-complete, overall or split by a grouping vector.
completion_summary <- function(complete_flag, group_vec = NULL) {
    if (is.null(group_vec)) {
        return(tibble::tibble(
        group = "Overall", n = length(complete_flag),
        n_complete = sum(complete_flag, na.rm = TRUE),
        pct_complete = round(100 * mean(complete_flag, na.rm = TRUE), 1)
        ))
    }
    tibble::tibble(group = as.character(group_vec), complete = complete_flag) %>%
        dplyr::filter(!is.na(group), nzchar(group)) %>%
        dplyr::group_by(group) %>%
        dplyr::summarise(
        n = dplyr::n(),
        n_complete = sum(complete, na.rm = TRUE),
        pct_complete = round(100 * mean(complete, na.rm = TRUE), 1),
        .groups = "drop"
        )
}

#' TRUE for rows that belong in the M2-M13 "surveyed subset". Only the
#' "status" completion signal actually removes rows — an explicit
#' Incomplete/Refused-style status means that row wasn't really surveyed.
#' The "roster" and "primary_secondary" signals never remove rows from ds:
#' every row in ds IS a completed survey by construction under those two
#' signal types; they only change what M1 itself reports (target-vs-actual,
#' or primary/secondary composition), not which rows the other modules see.
#' No signal detected at all -> unchanged from pre-completion-redesign
#' behavior (every row counts).
compute_completed_flag <- function(ds, roles) {
    if (identical(roles$completion_primary_signal, "status")) {
        col <- roles$completion_status_col
        if (!is.null(col) && !is.na(col) && col %in% names(ds)) {
        complete_values <- roles$completion_status_complete_values %||% c("complete", "completed")
        return(tolower(trimws(as.character(ds[[col]]))) %in% tolower(complete_values))
        }
    }
    rep(TRUE, nrow(ds))
}

#' Shared per-run setup: one-time library loads, form-map resolution (read
#' from an existing attribute, or freshly parsed and written back onto that
#' same attribute so every check_mN() call — including from a standalone
#' generated script — can read it via attr(ds, "hfc_form_map") without
#' needing its own code_output_dir parameter), and the derived columns
#' every module can rely on (.hfc_row, .hfc_id_display, .hfc_completed).
#' `target_ds`: the loaded roster/target-sample tibble, only when
#' roles$completion_primary_signal == "roster" (NULL otherwise) — attached
#' as an attribute so check_m1() alone can read it without every other
#' check_mN() needing to know it exists.
prepare_ds_for_checks <- function(ds, roles, code_output_dir = NULL, target_ds = NULL) {
    suppressPackageStartupMessages({
        library(dplyr); library(lubridate); library(tibble)
    })
    form_map <- attr(ds, "hfc_form_map")
    if (is.null(form_map) && !is.null(code_output_dir)) {
        fp <- hfc_path(code_output_dir, "instruments", "form.xlsx")
        if (file.exists(fp) && exists("parse_form_relevance", mode = "function")) {
        form_map <- parse_form_relevance(fp)
        }
    }
    attr(ds, "hfc_form_map") <- form_map
    ds$.hfc_row <- seq_len(nrow(ds))
    ds$.hfc_id_display <- composite_id_string(ds, roles$entity_id, roles$entity_id_sep %||% " / ")
    ds$.hfc_completed <- compute_completed_flag(ds, roles)
    attr(ds, "hfc_target_ds") <- target_ds
    ds
}

# ---- M1 Completion ---------------------------------------------------------
# Redesigned around three possible completion signals (roles$completion_
# primary_signal, set from role_map.yaml once the agent confirms it in
# SKILL.md A1's required-gate window):
#   "status"           - complete_flag = ds$.hfc_completed (already computed
#                         in prepare_ds_for_checks()); this IS the classic
#                         "did this row finish" signal.
#   "roster"           - complete_flag is defined over the ROSTER
#                         (attr(ds, "hfc_target_ds")) rows, not ds: TRUE =
#                         this target entity's key appears in the surveyed
#                         ds. Overall/by-group rates describe "planned vs.
#                         actually surveyed" (by-enumerator naturally comes
#                         out empty, since a roster has no enumerator
#                         column — nothing surveyed a row that was never
#                         surveyed).
#   "primary_secondary" - every surveyed row counts; complete_flag instead
#                         marks "is this the primary-sample designation",
#                         so the SAME overall/by-group/by-enumerator
#                         completion_summary() plumbing reports composition
#                         (% primary vs secondary) rather than a rate.
#   NA (no signal)      - unchanged fallback: today's row-missingness
#                         heuristic, for surveys with none of the three
#                         signals.
# The separate "low completion by site" FINDING below (flagging specific
# under-enrolled sites via roles$group, the site/cluster ID) is orthogonal
# to all of this and always operates on the actual surveyed ds.
check_m1 <- function(ds, roles, modules) {
    sig <- roles$completion_primary_signal %||% NA_character_
    target_ds <- attr(ds, "hfc_target_ds")
    group_source_ds <- ds

    if (identical(sig, "roster") && !is.null(target_ds) && !is.na(roles$entity_id[[1]] %||% NA_character_)) {
        entity_col <- roles$entity_id[[1]]
        roster_key_col <- roles$completion_roster_key_col %||% entity_col
        if (roster_key_col %in% names(target_ds) && entity_col %in% names(ds)) {
        surveyed_keys <- as.character(ds[[entity_col]])
        target_keys <- as.character(target_ds[[roster_key_col]])
        complete_flag <- target_keys %in% surveyed_keys
        group_source_ds <- target_ds
        } else {
        sig <- NA_character_
        }
    }
    if (identical(sig, "primary_secondary")) {
        ps_col <- roles$completion_primary_secondary_col
        primary_value <- roles$completion_primary_value %||% NA_character_
        complete_flag <- if (!is.na(ps_col) && ps_col %in% names(ds) && !is.na(primary_value)) {
        tolower(trimws(as.character(ds[[ps_col]]))) == tolower(primary_value)
        } else {
        rep(TRUE, nrow(ds))
        }
    } else if (identical(sig, "status")) {
        complete_flag <- ds$.hfc_completed
    } else if (identical(sig, "gating")) {
        # A respondent is complete only if they passed EVERY confirmed gate
        # (Completion Signals window, A1) — a failing value on any one gate
        # means the rest of the survey was never asked. gate_pass_values
        # gives each gate's own "pass"/continue value; a gate with no
        # configured pass value is treated as non-blocking (always passes).
        gate_cols <- modules$M1$gate_cols %||% character()
        gate_cols <- gate_cols[!is.na(gate_cols) & gate_cols %in% names(ds)]
        gate_pass <- modules$M1$gate_pass_values %||% list()
        if (length(gate_cols)) {
        pass_mat <- vapply(gate_cols, function(gc) {
            pv <- gate_pass[[gc]] %||% NA_character_
            if (is.na(pv)) rep(TRUE, nrow(ds)) else tolower(trimws(as.character(ds[[gc]]))) == tolower(pv)
        }, logical(nrow(ds)))
        complete_flag <- apply(pass_mat, 1, all)
        } else {
        complete_flag <- rep(TRUE, nrow(ds))
        }
    } else if (!identical(sig, "roster")) {
        completion_var <- modules$M1$completion_var %||% NA_character_
        complete_flag <- if (!is.na(completion_var) && completion_var %in% names(ds)) {
        is_complete_value(ds[[completion_var]])
        } else {
        row_missing_ratio(ds, setdiff(names(ds), c(".hfc_row", ".hfc_id_display", ".hfc_completed"))) <= 0.1
        }
    }

    stats_overall <- completion_summary(complete_flag)
    group_vars <- modules$M1$group_vars %||% character()
    # Under "roster" mode, group_source_ds IS target_ds - the roster's own
    # strata column can carry a different name than ds's (e.g. ds has
    # "village", the roster has "village_name"). Without reconciling that,
    # a name mismatch would silently drop the variable from by_group_df
    # entirely (no error, nothing computed) rather than compute anything -
    # roles$completion_roster_group_map (role_map.yaml) bridges the gap,
    # agent-resolved at setup the same way completion_roster_key_col
    # already bridges the entity-key name mismatch; identity (no map entry
    # needed) whenever the names already match, the common case.
    roster_group_map <- roles$completion_roster_group_map %||% list()
    resolve_group_var <- function(gv) {
        if (gv %in% names(group_source_ds)) return(gv)
        if (!identical(sig, "roster")) return(NA_character_)
        mapped <- roster_group_map[[gv]] %||% NA_character_
        if (!is.na(mapped) && mapped %in% names(group_source_ds)) mapped else NA_character_
    }
    by_group <- lapply(group_vars, function(gv) {
        gv_resolved <- resolve_group_var(gv)
        if (is.na(gv_resolved)) return(NULL)
        # Table's own `group_var` label stays the name as known in the
        # primary survey data (gv), never the roster's internal column
        # name (gv_resolved) - that's an implementation detail, not
        # something the report should surface.
        completion_summary(complete_flag, group_source_ds[[gv_resolved]]) %>%
        mutate(group_var = gv, .before = 1) %>%
        rename(value = group)
    })
    by_group <- by_group[!vapply(by_group, is.null, logical(1))]
    by_group_df <- if (length(by_group)) bind_rows(by_group) else tibble()
    by_enum_df <- if (isTRUE(modules$M1$by_enum %||% TRUE) && !is.na(roles$enum) && roles$enum %in% names(group_source_ds)) {
        enum_disp <- resolve_display_vec(
        group_source_ds[[roles$enum]],
        resolve_unit_name(group_source_ds, roles$enum, roles$enum_name),
        roles$enumerator_display %||% "name"
        )
        completion_summary(complete_flag, enum_disp) %>% rename(enumerator = group) %>% arrange(pct_complete)
    } else tibble()
    by_date_df <- if (isTRUE(modules$M1$by_date %||% TRUE) && !is.na(roles$start) && roles$start %in% names(group_source_ds)) {
        d <- suppressWarnings(as.Date(as.character(group_source_ds[[roles$start]])))
        completion_summary(complete_flag, as.character(d)) %>% rename(date = group) %>% arrange(desc(date))
    } else tibble()
    stats <- list(overall = stats_overall, by_group = by_group_df,
                    by_enumerator = by_enum_df, by_date = by_date_df)

    # Reasons for non-completion (gating mode only) — for each incomplete
    # respondent, the reason is the FIRST gate (in confirmed order) they
    # failed, since nothing after it was ever asked. The reason label
    # decodes the failing value's own labels when the gate column is
    # value-labelled (decode_labelled_chr()), else falls back to the gate's
    # own question label/name.
    by_reason_df <- tibble()
    if (identical(sig, "gating") && length(gate_cols)) {
        gate_labels <- modules$M1$gate_labels %||% list()
        reason_vec <- rep(NA_character_, nrow(ds))
        for (gc in gate_cols) {
        pv <- gate_pass[[gc]] %||% NA_character_
        if (is.na(pv)) next
        failed <- tolower(trimws(as.character(ds[[gc]]))) != tolower(pv)
        assign_idx <- is.na(reason_vec) & failed
        if (any(assign_idx)) {
            decoded <- decode_labelled_chr(ds[[gc]])
            raw <- as.character(ds[[gc]])
            gc_label <- gate_labels[[gc]] %||% gc
            reason_vec[assign_idx] <- ifelse(
            nzchar(decoded[assign_idx]) & decoded[assign_idx] != raw[assign_idx],
            decoded[assign_idx], gc_label
            )
        }
        }
        reasons_present <- reason_vec[!complete_flag & !is.na(reason_vec)]
        if (length(reasons_present)) {
        # Named "count", not "n" — M1's column-label map maps `n` to "Surveys
        # Submitted" for the by_group/by_enumerator/by_date tables, which
        # would be a wrong label here (this is a respondent count per
        # reason, not a submitted-surveys count).
        by_reason_df <- tibble(reason = reasons_present) %>% count(reason, sort = TRUE, name = "count")
        }
    }
    stats$by_reason <- by_reason_df

    findings <- empty_findings()
    # complete_flag is only row-aligned with `ds` for "status"/"primary_
    # secondary"/no-signal — under "roster" it's aligned with target_ds
    # instead (see above), so this ds-based site-level finding is skipped
    # in that case (every ds row is, by construction, a completed survey
    # under "roster", so there's nothing row-level to flag here anyway).
    if (isTRUE(modules$M1$low_completion_on) && !is.na(roles$group) && roles$group %in% names(ds) &&
        length(complete_flag) == nrow(ds)) {
        pct_median <- modules$M1$pct_median %||% 0.5
        group_term <- roles$group_label %||% "Group"
        group_name_vec <- resolve_unit_name(ds, roles$group, roles$group_name)
        counts <- ds %>% mutate(.complete = complete_flag, .gname = group_name_vec) %>%
        filter(.complete, !is.na(.data[[roles$group]])) %>%
        group_by(.data[[roles$group]]) %>%
        summarise(
            n = n(),
            .group_name = dplyr::first(stats::na.omit(.gname), default = NA_character_),
            .groups = "drop"
        )
        if (nrow(counts) > 1) {
        # Target = median completed-submission count across groups — a
        # stand-in for a real enrollment target when the project has none.
        tgt <- stats::median(counts$n)
        # Sort worst-first (lowest completion ratio first): each flagged
        # group's completion count over the target.
        low <- counts %>% filter(n < pct_median * tgt) %>% mutate(.sortv = n / tgt)
        if (nrow(low)) {
            unit_df <- tibble::tibble(
            unit_id = as.character(low[[roles$group]]),
            unit_name = low$.group_name,
            .sortv = low$.sortv,
            .value = sprintf("%d submissions (%.0f%% of target)", low$n, 100 * low$.sortv)
            )
            findings <- mk_aggregate_finding(
            unit_df, "low_completion", "M1", "low_completion",
            sprintf("%s has fewer completed submissions than %.0f%% of the target", group_term, 100 * pct_median),
            roles, unit_type = "group", value_col = ".value", sort_value_col = ".sortv"
            )
        }
        }
    }

    # Day-by-day enumerator productivity, against a user-stated daily target
    # (Completion Signals window) — NOT a median: an enumerator whose count
    # on a given day falls short of the confirmed target is flagged for that
    # day. One aggregate finding per enumerator, listing every under-target
    # day (mirrors M7/M9's "one row per enumerator, list every instance").
    daily_target <- suppressWarnings(as.numeric(modules$M1$daily_target_per_enum %||% NA_real_))
    if (!is.na(daily_target) && !is.na(roles$enum) && roles$enum %in% names(ds) &&
        !is.na(roles$start) && roles$start %in% names(ds)) {
        enum_raw <- as.character(ds[[roles$enum]])
        day_full <- suppressWarnings(as.Date(as.character(ds[[roles$start]])))
        day_counts <- tibble::tibble(enum = enum_raw, day = day_full) %>%
        filter(!is.na(enum), nzchar(enum), !is.na(day)) %>%
        count(enum, day, name = "n") %>%
        filter(n < daily_target)
        if (nrow(day_counts)) {
        enum_lookup <- enum_name_lookup(ds, roles)
        by_enum_day <- day_counts %>%
            arrange(day) %>%
            group_by(enum) %>%
            summarise(
            .vars = paste(sprintf("%s (%d)", day, n), collapse = " & "),
            .n_days = n(),
            .worst = min(n),
            .groups = "drop"
            )
        ename <- if (!is.null(enum_lookup)) enum_lookup$.ename[match(by_enum_day$enum, enum_lookup$.enum)] else NA_character_
        unit_df2 <- tibble::tibble(
            unit_id = by_enum_day$enum,
            unit_name = ename,
            .issue = sprintf(
            "Below the daily target of %s on %d day%s: %s",
            daily_target, by_enum_day$.n_days, ifelse(by_enum_day$.n_days == 1, "", "s"), by_enum_day$.vars
            ),
            .value = by_enum_day$.vars,
            .sortv = by_enum_day$.worst
        )
        day_findings <- mk_aggregate_finding(
            unit_df2, "low_completion_enum_day", "M1", "low_completion_enum_day", unit_df2$.issue,
            roles, unit_type = "enumerator", value_col = ".value", sort_value_col = ".sortv"
        )
        findings <- bind_rows(findings, day_findings)
        }
    }

    # Replacement-sample analysis (Completion Signals window) — independent
    # of `sig`/completion_signal: whenever the roster (target_ds) has
    # confirmed primary/replacement/rank/group columns, report the
    # replacement rate and check the replacement sequence was followed
    # correctly, regardless of which signal is actually driving M1's own
    # completion accounting above.
    repl_status_col <- modules$M1$replacement_status_col %||% NA_character_
    repl_rank_col <- modules$M1$replacement_rank_col %||% NA_character_
    repl_group_col <- modules$M1$replacement_group_col %||% NA_character_
    if (!is.null(target_ds) && !is.na(repl_status_col) && repl_status_col %in% names(target_ds) &&
        !is.na(repl_rank_col) && repl_rank_col %in% names(target_ds) &&
        !is.na(repl_group_col) && repl_group_col %in% names(target_ds) &&
        !is.na(roles$entity_id[[1]] %||% NA_character_) && roles$entity_id[[1]] %in% names(ds)) {
        entity_col <- roles$entity_id[[1]]
        roster_key_col <- roles$completion_roster_key_col %||% entity_col

        # Every row that exists in `ds` is a completed survey under "roster"
        # mode by construction (ds there only ever contains completed
        # submissions — same convention already documented elsewhere in
        # this function); otherwise reuse this project's own per-row
        # completion flag, already computed above and row-aligned with ds.
        ds_complete_flag <- if (identical(sig, "roster")) rep(TRUE, nrow(ds)) else complete_flag

        surveyed_key <- as.character(ds[[entity_col]])
        completed_key <- unique(surveyed_key[ds_complete_flag %in% TRUE])
        attempted_key <- unique(surveyed_key)

        primary_values <- tolower(trimws(as.character(modules$M1$replacement_primary_values %||% "primary")))
        is_primary <- tolower(trimws(as.character(target_ds[[repl_status_col]]))) %in% primary_values
        roster_key <- as.character(target_ds[[roster_key_col]])
        roster_grp <- as.character(target_ds[[repl_group_col]])
        roster_rank <- suppressWarnings(as.numeric(target_ds[[repl_rank_col]]))

        roster_tbl <- tibble::tibble(key = roster_key, group = roster_grp, is_primary = is_primary, rank = roster_rank) %>%
        filter(!is.na(key), nzchar(key), !is.na(group), nzchar(group))

        if (nrow(roster_tbl)) {
        by_group_repl <- roster_tbl %>%
            group_by(group) %>%
            summarise(
            n_primary = sum(is_primary),
            n_primary_completed = sum(is_primary & key %in% completed_key),
            n_replaced = sum(!is_primary & key %in% completed_key),
            .groups = "drop"
            ) %>%
            filter(n_primary > 0) %>%
            mutate(pct_replaced = round(100 * n_replaced / n_primary, 1))

        if (nrow(by_group_repl)) {
            by_repl_tbl <- by_group_repl %>%
            transmute(
                group, `Primary targeted` = n_primary,
                `Primary completed` = n_primary_completed, Replaced = n_replaced,
                `% Replaced` = pct_replaced
            )
            # What roles$group actually denotes for this survey (e.g.
            # "Village", "Farmer group"), never the generic "Group" -
            # derive_group_label()'s guess, same source as every other
            # dynamically-labelled M1 table.
            names(by_repl_tbl)[1] <- roles$group_label %||% "Group"
            stats$by_replacement <- by_repl_tbl
        }

        # Validity: within each group's shared replacement queue (ordered
        # by rank), if the highest COMPLETED rank is K, every rank < K
        # must have a row in ds at all (attempted) — a rank with no row is
        # a genuine gap, skipped without being attempted.
        repl_tbl <- roster_tbl %>% filter(!is_primary, !is.na(rank))
        violations <- list()
        for (g in unique(repl_tbl$group)) {
            g_repl <- repl_tbl %>% filter(group == g) %>% arrange(rank)
            completed_ranks <- g_repl$rank[g_repl$key %in% completed_key]
            if (!length(completed_ranks)) next
            max_completed_rank <- max(completed_ranks)
            earlier <- g_repl %>% filter(rank < max_completed_rank)
            missing <- earlier %>% filter(!(key %in% attempted_key))
            if (nrow(missing)) {
            violations[[g]] <- tibble::tibble(
                group = g,
                .issue = sprintf(
                "Replacement rank %s was completed, but replacement rank%s %s in this %s %s no row in the submitted data at all",
                max_completed_rank,
                if (nrow(missing) > 1) "s" else "",
                paste(sort(missing$rank), collapse = ", "),
                tolower(roles$group_label %||% "group"),
                if (nrow(missing) > 1) "have" else "has"
                )
            )
            }
        }
        if (length(violations)) {
            viol_df <- bind_rows(violations)
            unit_df3 <- tibble::tibble(unit_id = viol_df$group, unit_name = NA_character_, .issue = viol_df$.issue)
            repl_findings <- mk_aggregate_finding(
            unit_df3, "replacement_sequence_gap", "M1", "replacement_sequence_gap", unit_df3$.issue,
            roles, unit_type = "group"
            )
            findings <- bind_rows(findings, repl_findings)
        }
        }
    }

    # Full daily roster (latest day) - every enumerator who has EVER
    # appeared in ds, with their attempted/completed tally for the most
    # recent day in the data, and their most recent active day (most
    # informative when Attempted is 0 today). Always present whenever
    # roles$enum + roles$start exist, independent of daily_target_per_enum
    # being configured - same posture as M4's always-present
    # stats$by_day_times. Lets the Summary narrative name every
    # enumerator's day, not just the ones flagged for falling below a
    # target, including anyone who submitted nothing at all.
    if (!is.na(roles$enum) && roles$enum %in% names(ds) &&
        !is.na(roles$start) && roles$start %in% names(ds)) {
        enum_raw <- as.character(ds[[roles$enum]])
        day_all <- suppressWarnings(as.Date(as.character(ds[[roles$start]])))
        # Same roster-mode convention as the replacement-sample block above:
        # every ds row is a completed survey by construction under "roster"
        # (complete_flag there is aligned to target_ds, not ds).
        roster_complete_flag <- if (identical(sig, "roster")) rep(TRUE, nrow(ds)) else complete_flag

        roster_df <- tibble::tibble(enum = enum_raw, day = day_all, complete = roster_complete_flag) %>%
        filter(!is.na(enum), nzchar(enum), !is.na(day))

        if (nrow(roster_df)) {
        latest_day <- max(roster_df$day, na.rm = TRUE)
        per_enum_today <- roster_df %>%
            filter(day == latest_day) %>%
            group_by(enum) %>%
            summarise(attempted = n(), completed = sum(complete), .groups = "drop")
        last_active <- roster_df %>%
            group_by(enum) %>%
            summarise(.last_active = max(day), .groups = "drop") %>%
            left_join(per_enum_today, by = "enum") %>%
            mutate(
            attempted = ifelse(is.na(attempted), 0L, attempted),
            completed = ifelse(is.na(completed), 0L, completed)
            ) %>%
            arrange(attempted, enum)

        enum_lookup <- enum_name_lookup(ds, roles)
        ename <- if (!is.null(enum_lookup)) enum_lookup$.ename[match(last_active$enum, enum_lookup$.enum)] else NA_character_
        enum_disp <- resolve_display_vec(last_active$enum, ename, roles$enumerator_display %||% "name")

        stats$by_enum_latest_day <- tibble::tibble(
            Enumerator = enum_disp,
            Attempted = last_active$attempted,
            Completed = last_active$completed,
            `Last Active Day` = as.character(last_active$.last_active)
        )
        }
    }
    list(findings = findings, stats = stats)
}

# ---- M2 Duplicates ----------------------------------------------------------
check_m2 <- function(ds, roles, modules) {
    findings <- empty_findings()
    idc <- modules$M2$id %||% roles$entity_id
    idc <- idc[!is.na(idc) & nzchar(as.character(idc)) & idc %in% names(ds)]
    # Extra disambiguating columns (e.g. round/wave) confirmed at setup so
    # an entity legitimately surveyed more than once isn't flagged as a
    # duplicate — see roles$dup_key_extra / the duplicate-check-key gate.
    extra <- modules$M2$extra_keys %||% character()
    extra <- extra[!is.na(extra) & nzchar(as.character(extra)) & extra %in% names(ds)]
    full_key <- c(idc, extra)
    parts <- list()
    if (length(full_key)) {
        dups <- ds %>%
        filter(if_all(all_of(full_key), ~ !is.na(.) & as.character(.) != "")) %>%
        group_by(across(all_of(full_key))) %>%
        filter(n() > 1) %>%
        ungroup()
        parts$m2 <- mk_findings(dups, "duplicates_id", "M2", "duplicates",
                                sprintf("Duplicate rows sharing the same %s", paste(full_key, collapse = " + ")), roles)
        if (nrow(dups) == 0 && !is.na(roles$key) && roles$key %in% names(ds)) {
        dups2 <- ds %>%
            filter(!is.na(.data[[roles$key]]), as.character(.data[[roles$key]]) != "") %>%
            group_by(.data[[roles$key]]) %>%
            filter(n() > 1) %>%
            ungroup()
        parts$m2b <- mk_findings(dups2, "duplicates_key", "M2", "duplicates",
                                sprintf("Duplicate rows sharing the same %s", roles$key), roles)
        }
    }
    if (length(parts)) findings <- bind_rows(parts)
    list(findings = findings)
}

# ---- M3 Form Version --------------------------------------------------------
check_m3 <- function(ds, roles, modules) {
    findings <- empty_findings()
    stats <- NULL
    version_col <- modules$M3$version_col %||% NA_character_
    version_map <- modules$M3$version_map %||% list()
    dcol <- roles$start
    if (!is.na(version_col) && version_col %in% names(ds)) {
        vc <- as.character(ds[[version_col]])
        if (!is.na(dcol) && dcol %in% names(ds)) {
        d <- suppressWarnings(as.Date(as.character(ds[[dcol]])))
        by_version <- tibble(version = vc, date = d) %>%
            filter(!is.na(version), nzchar(version)) %>%
            group_by(version) %>%
            summarise(n = n(), date_min = as.character(min(date, na.rm = TRUE)),
                    date_max = as.character(max(date, na.rm = TRUE)), .groups = "drop")
        stats <- by_version
        }
        if (length(version_map) && !is.na(dcol) && dcol %in% names(ds)) {
        d <- suppressWarnings(as.Date(as.character(ds[[dcol]])))
        expected <- rep(NA_character_, nrow(ds))
        for (vspec in version_map) {
            d_start <- as.Date(vspec$date_start); d_end <- as.Date(vspec$date_end)
            idx <- which(!is.na(d) & d >= d_start & d <= d_end)
            expected[idx] <- vspec$version_label
        }
        mismatch <- !is.na(expected) & !is.na(vc) & nzchar(vc) & vc != expected
        if (any(mismatch)) {
            tmp <- ds[mismatch, , drop = FALSE]
            tmp$.v <- sprintf("recorded=%s expected=%s", vc[mismatch], expected[mismatch])
            findings <- mk_findings(
            tmp, "form_version_mismatch", "M3", "form_version_mismatch",
            "Recorded form version doesn't match the expected version for this date", roles, ".v",
            variable_name = version_col
            )
        }
        }
    } else if (length(version_map)) {
        rows <- lapply(version_map, function(v) {
        tibble(version = v$version_label, date_start = v$date_start, date_end = v$date_end)
        })
        stats <- bind_rows(rows)
    }
    list(findings = findings, stats = stats)
}

# ---- M4 Survey Duration ------------------------------------------------------
#' SD-outlier flag one duration vector (minutes), reused for both the overall
#' duration column and each opted-in section pair below — same threshold
#' logic, just parameterized by label/variable_name so the resulting
#' long_duration/short_duration findings stay distinguishable per section.
.m4_flag_outliers <- function(ds, dur, sd_rule, roles, variable_name) {
  ok <- is.finite(dur)
  parts <- list()
  mu <- mean(dur[ok]); sdv <- stats::sd(dur[ok])
  if (is.finite(mu) && is.finite(sdv) && sdv > 0) {
    long_flag <- ok & dur > mu + sd_rule * sdv
    short_flag <- ok & dur < mu - sd_rule * sdv & dur > 0
    if (any(long_flag)) {
      tmp <- ds[long_flag, , drop = FALSE]; tmp$.v <- round1(dur[long_flag])
      parts$long <- mk_findings(
        tmp, "long_duration", "M4", "long_duration",
        sprintf("%s more than %s SD above the mean", variable_name, sd_rule), roles, ".v",
        variable_name = variable_name, sort_value_col = ".v"
      )
    }
    if (any(short_flag)) {
      tmp <- ds[short_flag, , drop = FALSE]; tmp$.v <- round1(dur[short_flag])
      parts$short <- mk_findings(
        tmp, "short_duration", "M4", "short_duration",
        sprintf("%s more than %s SD below the mean", variable_name, sd_rule), roles, ".v",
        variable_name = variable_name, sort_value_col = ".v"
      )
    }
  }
  if (length(parts)) bind_rows(parts) else empty_findings()
}

check_m4 <- function(ds, roles, modules) {
  findings <- empty_findings()
  stats <- NULL
  dc <- modules$M4$duration %||% roles$duration
  sd_rule <- modules$M4$sd_rule %||% 3
  section_findings <- list()
  section_stats_extra <- list()

  # Section-level start/end pairs (SKILL.md A2, Keys & Hours window) — opted
  # into via modules$M4$section_pairs, a named list label -> list(start=,
  # end=) sourced from roles$section_time_pairs. Runs independently of the
  # overall duration column below: a survey can have section timing with or
  # without a single global duration field.
  section_pairs <- modules$M4$section_pairs %||% list()
  for (label in names(section_pairs)) {
    pr <- section_pairs[[label]]
    if (is.null(pr$start) || is.null(pr$end) ||
        !pr$start %in% names(ds) || !pr$end %in% names(ds)) next
    sec_dur <- as.numeric(difftime(
      parse_datetime_col(ds[[pr$end]]), parse_datetime_col(ds[[pr$start]]), units = "mins"
    ))
    # Bare section name (e.g. "Consent") for the stats-table row - the
    # "<name> duration" phrasing only belongs in the outlier finding's
    # sentence ("Consent duration is more than 3 SD above the mean"),
    # never as the Section column's own value.
    finding_label <- paste0(label, " duration")
    section_stats_extra[[label]] <- sec_dur
    section_findings[[label]] <- .m4_flag_outliers(ds, sec_dur, sd_rule, roles, finding_label)
  }

  stat_row <- function(label, vals) {
    tibble(level = label, n = sum(is.finite(vals)),
          mean = round1(mean(vals, na.rm = TRUE)), median = round1(stats::median(vals, na.rm = TRUE)),
          sd = round1(stats::sd(vals, na.rm = TRUE)),
          min = round1(suppressWarnings(min(vals, na.rm = TRUE))),
          max = round1(suppressWarnings(max(vals, na.rm = TRUE))))
  }

  if (!is.na(dc) && dc %in% names(ds)) {
    # SurveyCTO's duration export is always in seconds; always convert to
    # minutes for stats, outlier detection, and the finding's Value — every
    # downstream use of `dur` inherits this single conversion point.
    dur <- safe_num(ds[[dc]]) / 60
    ok <- is.finite(dur)
    stats_overall <- stat_row("Overall", dur[ok])
    # Pre-computed per-section duration columns (e.g. introduction_duration),
    # as distinct from the section_pairs start/end derivation above — both
    # feed the same by_section stats table.
    section_dur_cols <- grep("_duration$", setdiff(names(ds), dc), value = TRUE)
    section_map <- modules$M4$section_map %||% list()
    stats_section_precomputed <- if (length(section_dur_cols)) {
      bind_rows(lapply(section_dur_cols, function(cn) {
        label <- section_map[[cn]] %||% cn
        stat_row(label, safe_num(ds[[cn]]) / 60)  # same seconds->minutes convention as the main duration column
      }))
    } else tibble()
    stats_by_enum <- if (isTRUE(modules$M4$by_enum %||% TRUE) && !is.na(roles$enum) && roles$enum %in% names(ds)) {
      enum_disp <- resolve_display_vec(
        ds[[roles$enum]], resolve_unit_name(ds, roles$enum, roles$enum_name),
        roles$enumerator_display %||% "name"
      )
      ds %>% mutate(.dur = dur, .enum_disp = enum_disp) %>% filter(is.finite(.dur)) %>%
        group_by(enumerator = .enum_disp) %>%
        summarise(n = n(), mean = round1(mean(.dur)), median = round1(stats::median(.dur)),
                  sd = round1(stats::sd(.dur)), min = round1(min(.dur)), max = round1(max(.dur)),
                  .groups = "drop")
    } else tibble()

    section_findings[["__overall__"]] <- .m4_flag_outliers(ds, dur, sd_rule, roles, dc)
    stats <- list(overall = stats_overall, by_enumerator = stats_by_enum)
  } else {
    stats_section_precomputed <- tibble()
    stats <- list(overall = tibble(), by_enumerator = tibble())
  }

  stats_section_pairs <- if (length(section_stats_extra)) {
    bind_rows(lapply(names(section_stats_extra), function(lbl) stat_row(lbl, section_stats_extra[[lbl]])))
  } else tibble()
  stats$by_section <- bind_rows(stats_section_precomputed, stats_section_pairs)

  # Daily earliest/latest start/end times — always present (needs only
  # roles$start; roles$end is optional), independent of whether a single
  # duration column is configured at all. "How did today go" operational
  # monitoring, not tied to the SD-outlier machinery above.
  if (!is.na(roles$start) && roles$start %in% names(ds)) {
    row_tz <- resolve_row_timezone(ds, roles)
    fmt_hm <- function(hour, minute) {
      tolower(format(ISOdatetime(2000, 1, 1, hour, minute, 0, tz = "UTC"), "%I:%M %p"))
    }
    start_parts <- local_date_hm(parse_datetime_col(ds[[roles$start]]), row_tz)
    has_end <- !is.na(roles$end) && roles$end %in% names(ds)
    end_parts <- if (has_end) {
      local_date_hm(parse_datetime_col(ds[[roles$end]]), row_tz)
    } else {
      list(date = rep(NA_character_, nrow(ds)), hour = rep(NA_integer_, nrow(ds)), minute = rep(NA_integer_, nrow(ds)))
    }
    day_tbl <- tibble(
      day = start_parts$date, s_hour = start_parts$hour, s_min = start_parts$minute,
      e_hour = end_parts$hour, e_min = end_parts$minute
    ) %>% filter(!is.na(day))
    if (nrow(day_tbl)) {
      by_day_time <- day_tbl %>%
        mutate(.s = s_hour * 60 + s_min, .e = e_hour * 60 + e_min) %>%
        group_by(day) %>%
        summarise(
          `Earliest Start` = fmt_hm(s_hour[which.min(.s)], s_min[which.min(.s)]),
          `Latest Start` = fmt_hm(s_hour[which.max(.s)], s_min[which.max(.s)]),
          `Earliest End` = if (all(is.na(.e))) NA_character_ else fmt_hm(e_hour[which.min(.e)], e_min[which.min(.e)]),
          `Latest End` = if (all(is.na(.e))) NA_character_ else fmt_hm(e_hour[which.max(.e)], e_min[which.max(.e)]),
          .groups = "drop"
        ) %>%
        arrange(day) %>%
        rename(Day = day)
      stats$by_day_times <- by_day_time
    }
  }

  if (length(section_findings)) findings <- bind_rows(section_findings)
  list(findings = findings, stats = stats)
}

# ---- M5 Irregular Timing (tz-aware) -----------------------------------------
check_m5 <- function(ds, roles, modules) {
  findings <- empty_findings()
  st <- roles$start
  if (!is.na(st) && st %in% names(ds)) {
    dt <- parse_datetime_col(ds[[st]])
    row_tz <- resolve_row_timezone(ds, roles)
    dp <- local_daypart(dt, row_tz)
    evening_hour <- modules$M5$evening_hour %||% 19
    morning_hour <- modules$M5$morning_hour %||% 7
    flag_weekend <- isTRUE(modules$M5$flag_weekend %||% TRUE)
    is_weekend <- flag_weekend & dp$wday %in% c(6, 7)
    is_offhours <- dp$hour >= evening_hour | dp$hour < morning_hour
    flag <- (is_weekend | is_offhours) & !is.na(dt)
    if (any(flag)) {
      tmp <- ds[flag, , drop = FALSE]
      tmp$.v <- format(dt[flag], "%Y-%m-%d %H:%M")
      hrs_window <- sprintf("%02d:00-%02d:00", morning_hour, evening_hour)
      reason <- ifelse(
        is_weekend[flag] & is_offhours[flag],
        sprintf("weekend and outside %s local time", hrs_window),
        ifelse(is_weekend[flag], "on a weekend",
               sprintf("outside %s local time", hrs_window))
      )
      tmp$.issue <- sprintf("Interview conducted %s", reason)
      # Sort worst-first: distance past the nearest hour-window edge, plus a
      # flat bonus for weekend flags so they don't get buried under small
      # off-hours deviations.
      off_dist <- ifelse(dp$hour[flag] >= evening_hour, dp$hour[flag] - evening_hour,
                   ifelse(dp$hour[flag] < morning_hour, morning_hour - dp$hour[flag], 0))
      tmp$.sortv <- off_dist + ifelse(is_weekend[flag], 1, 0)
      findings <- mk_findings(
        tmp, "irregular_time", "M5", "irregular_time",
        tmp$.issue, roles, ".v", sort_value_col = ".sortv"
      )
    }
  }
  list(findings = findings)
}

# ---- M6 Numeric Outliers (up to 10 vars, clean two-sided N-SD) -------------
check_m6 <- function(ds, roles, modules) {
  findings <- empty_findings()
  vars <- modules$M6$vars %||% utils::head(roles$numeric_shortlist, 10)
  vars <- vars[!is.na(vars) & vars %in% names(ds)]
  sd_rule <- modules$M6$sd_rule %||% 3
  parts <- list()
  for (vc in vars) {
    v <- safe_num(ds[[vc]])
    ok <- is.finite(v)
    if (sum(ok) < 30) next
    mu <- mean(v[ok]); sdv <- stats::sd(v[ok])
    if (!is.finite(sdv) || sdv <= 0) next
    flag <- ok & abs(v - mu) > sd_rule * sdv
    if (!any(flag)) next
    tmp <- ds[flag, , drop = FALSE]
    tmp$.v <- round1(v[flag])
    # Sort worst-first by deviation magnitude (SDs from the mean), not the
    # raw value — a raw value alone isn't comparable across variables or
    # across low/high outliers on the same variable.
    tmp$.sortv <- abs(v[flag] - mu) / sdv
    tmp$.direction <- ifelse(v[flag] > mu, "more", "less")
    catg <- if (identical(vc, roles$age) || grepl("age", vc, ignore.case = TRUE)) "age_outlier" else "numeric_outlier"
    tmp <- utils::head(tmp, 200)
    # var_label() for the human-facing sentence; `vc` itself stays raw for
    # the check_id and variable_name (-> issue_tracking.xlsx's DIME column).
    label <- sprintf("Outlier value for %s; the value is %s than %s SD from the mean", var_label(vc, roles), tmp$.direction, sd_rule)
    parts[[vc]] <- mk_findings(
      tmp, sprintf("outlier_%s", vc), "M6", catg, label, roles, ".v",
      variable_name = vc, sort_value_col = ".sortv"
    )
  }
  if (length(parts)) findings <- bind_rows(parts)
  list(findings = findings)
}

# ---- M7 Missingness ----------------------------------------------------------
check_m7 <- function(ds, roles, modules) {
  vars <- modules$M7$vars %||% character()
  vars <- vars[!is.na(vars) & vars %in% names(ds)]
  sentinel <- modules$M7$sentinel_codes %||% character()
  sentinel_is_map <- is.list(sentinel) && !is.null(names(sentinel))
  by_enum <- isTRUE(modules$M7$by_enum %||% TRUE) && !is.na(roles$enum) && roles$enum %in% names(ds)
  # Three fixed, stated-not-asked thresholds (see SKILL.md/check_modules.md):
  # a variable only counts as an "issue" (shows up at all) past
  # var_issue_threshold population missingness; only the worst variables
  # (past enum_pool_threshold) are even eligible for enumerator-level
  # flagging; within that pool, an enumerator is flagged if THEIR OWN
  # missingness on it clears enum_pct_threshold.
  var_issue_threshold <- modules$M7$var_issue_threshold %||% 0.5
  enum_pool_threshold <- modules$M7$enum_pool_threshold %||% 0.9
  enum_pct_threshold <- modules$M7$enum_pct_threshold %||% 0.5
  form_map <- attr(ds, "hfc_form_map")
  enum_lookup <- if (by_enum) enum_name_lookup(ds, roles) else NULL
  by_var <- list(); by_enum_list <- list(); enum_flags <- list()
  for (vc in vars) {
    codes <- if (sentinel_is_map) sentinel[[vc]] %||% character() else sentinel
    x <- ds[[vc]]
    miss <- is.na(x) | as.character(x) %in% as.character(codes)

    # Skip-logic exclusion: a row where this variable wasn't relevant (a
    # parent answer routed the respondent around it) never counts toward
    # missingness — dropped from the numerator AND the denominator, not
    # just hidden from the numerator, or an entirely-skipped question would
    # misleadingly show near-zero missingness.
    applicable <- rep(TRUE, nrow(ds))
    if (!is.null(form_map) && nrow(form_map) > 0 && vc %in% form_map$name &&
        exists("row_is_relevant", mode = "function")) {
      rel <- form_map$relevant[match(vc, form_map$name)]
      if (!is.na(rel) && nzchar(rel)) applicable <- row_is_relevant(ds, rel)
    }
    miss[!applicable] <- FALSE
    n_applicable <- sum(applicable)
    pct_missing <- if (n_applicable > 0) round(100 * sum(miss) / n_applicable, 1) else NA_real_

    # Gate 1: only real population-level issues get a row at all — "do not
    # create rows for variables who don't have more than 50% missing."
    if (is.na(pct_missing) || pct_missing <= var_issue_threshold * 100) next
    by_var[[vc]] <- tibble(variable = var_label(vc, roles), pct_missing = pct_missing,
                            n_missing = sum(miss), n = n_applicable)

    if (by_enum) {
      # by_e$enumerator stays the RAW ID throughout this block — the
      # threshold check and mk_aggregate_finding() below both need the true
      # ID, not a display name. A separate display-resolved copy is what
      # actually goes into by_enum_list (stats$by_enumerator, rendered in
      # the report) — see below.
      by_e <- tibble(enumerator = as.character(ds[[roles$enum]]), miss = miss, applicable = applicable) %>%
        filter(!is.na(enumerator), nzchar(enumerator), applicable) %>%
        group_by(enumerator) %>%
        summarise(pct_missing = round(100 * mean(miss), 1), n = n(), .groups = "drop") %>%
        # Clean label, not the raw column name - feeds both the by_enumerator
        # stats table and the aggregate finding's sentence below, neither of
        # which is a DIME-facing raw-name column.
        mutate(variable = var_label(vc, roles))
      by_e_display <- by_e
      by_e_display$enumerator <- resolve_display_vec(
        by_e$enumerator,
        if (!is.null(enum_lookup)) enum_lookup$.ename[match(by_e$enumerator, enum_lookup$.enum)] else NULL,
        roles$enumerator_display %||% "name"
      )
      by_enum_list[[vc]] <- by_e_display

      # Gate 2: this variable only becomes eligible for enumerator-level
      # flagging once its OWN population missingness clears the much higher
      # pool threshold — a narrower subset of the Gate-1 "issue" variables.
      if (pct_missing >= enum_pool_threshold * 100) {
        # Gate 3: within that pool, flag enumerators whose personal
        # missingness on it clears the (lower) personal threshold.
        hi <- by_e %>% filter(pct_missing >= enum_pct_threshold * 100)
        if (nrow(hi)) enum_flags[[vc]] <- hi %>% mutate(variable = vc)
      }
    }
  }

  # One row per enumerator, not one per (enumerator, variable) pair: an
  # enumerator flagged on several variables gets every variable listed in
  # the issue text and every personal missingness % joined with " & " in
  # value, instead of a separate finding per variable (same pattern as
  # check_m9()'s straightlining_enum).
  findings <- empty_findings()
  if (length(enum_flags)) {
    all_flags <- bind_rows(enum_flags)
    by_enum_agg <- all_flags %>%
      group_by(enumerator) %>%
      summarise(
        vars = paste(variable, collapse = ", "),
        pct_vals = paste(sprintf("%s%%", pct_missing), collapse = " & "),
        worst_pct = max(pct_missing),
        .groups = "drop"
      )
    ename <- if (!is.null(enum_lookup)) enum_lookup$.ename[match(by_enum_agg$enumerator, enum_lookup$.enum)] else NA_character_
    unit_df <- tibble::tibble(
      unit_id = by_enum_agg$enumerator,
      unit_name = ename,
      .issue = sprintf("Enumerator's missingness is %.0f%%+ on %s", enum_pct_threshold * 100, by_enum_agg$vars),
      .value_display = by_enum_agg$pct_vals,
      .sort = by_enum_agg$worst_pct
    )
    findings <- mk_aggregate_finding(
      unit_df, "high_missing_enum", "M7", "high_missingness", unit_df$.issue,
      roles, unit_type = "enumerator", value_col = ".value_display", sort_value_col = ".sort"
    )
  }

  stats <- list(
    by_variable = if (length(by_var)) bind_rows(by_var) else tibble(),
    by_enumerator = if (length(by_enum_list)) bind_rows(by_enum_list) else tibble()
  )
  list(findings = findings, stats = stats)
}

# ---- M8 GPS -------------------------------------------------------------------
check_m8 <- function(ds, roles, modules) {
  findings <- empty_findings()
  xc <- modules$M8$x %||% roles$x
  yc <- modules$M8$y %||% roles$y
  thr <- modules$M8$threshold_m %||% 300
  grp <- roles$group
  if (!is.na(xc) && !is.na(yc) && !is.na(grp) && all(c(xc, yc, grp) %in% names(ds))) {
    tmp <- ds %>%
      mutate(x = safe_num(.data[[xc]]), y = safe_num(.data[[yc]]), grp = .data[[grp]]) %>%
      filter(is.finite(x), is.finite(y), !is.na(grp))
    ref <- tmp %>% group_by(grp) %>% summarise(rx = median(x), ry = median(y), .groups = "drop")
    tmp <- tmp %>% left_join(ref, by = "grp") %>%
      mutate(dist_m = sqrt((x - rx)^2 + (y - ry)^2))
    if (median(abs(tmp$x), na.rm = TRUE) < 180 && median(abs(tmp$y), na.rm = TRUE) < 90) {
      if (requireNamespace("geosphere", quietly = TRUE)) {
        tmp$dist_m <- geosphere::distHaversine(cbind(tmp$x, tmp$y), cbind(tmp$rx, tmp$ry))
      }
    }
    flagged <- tmp %>% filter(is.finite(dist_m), dist_m > thr)
    if (nrow(flagged) > 0) {
      flagged$.v <- as.character(round1(flagged$dist_m))
      findings <- mk_findings(
        flagged, "gps_distance", "M8", "gps_distance",
        sprintf("Distance between reference and survey coordinates is %.1f meters", round1(flagged$dist_m)),
        roles, ".v", sort_value_col = "dist_m"
      )
    }
  }
  list(findings = findings)
}

# ---- M9 Straightlining -------------------------------------------------------
check_m9 <- function(ds, roles, modules) {
  ordinal_vars <- modules$M9$ordinal_vars %||% character()
  ordinal_vars <- ordinal_vars[!is.na(ordinal_vars) & ordinal_vars %in% names(ds)]
  enum_thr <- modules$M9$enum_threshold_pct %||% 0.9
  survey_thr <- modules$M9$survey_threshold_pct %||% 0.9
  min_n_per_enum <- 10L
  parts <- list()

  if (length(ordinal_vars) && !is.na(roles$enum) && roles$enum %in% names(ds)) {
    enum_vec <- as.character(ds[[roles$enum]])
    enum_lookup <- enum_name_lookup(ds, roles)
    flagged_rows <- list()
    for (vc in ordinal_vars) {
      v <- decode_labelled_chr(ds[[vc]])
      ok <- !is.na(v) & nzchar(v) & !is.na(enum_vec) & nzchar(enum_vec)
      if (!any(ok)) next
      tab <- tibble(enum = enum_vec[ok], v = v[ok]) %>%
        group_by(enum) %>%
        summarise(
          n = n(),
          top_val = names(sort(table(v), decreasing = TRUE))[1],
          top_share = max(table(v)) / n(),
          .groups = "drop"
        ) %>%
        filter(n >= min_n_per_enum, top_share >= enum_thr)
      if (!nrow(tab)) next
      # Clean label - this feeds the aggregate finding's sentence below,
      # not a DIME-facing raw-name column.
      flagged_rows[[vc]] <- tab %>% mutate(variable = var_label(vc, roles))
    }
    # One row per enumerator, not one per (enumerator, variable) pair: an
    # enumerator flagged on several variables gets every variable listed in
    # the issue text and every straightlined answer joined with " & " in
    # value, instead of a separate finding per variable.
    if (length(flagged_rows)) {
      by_enum <- bind_rows(flagged_rows) %>%
        group_by(enum) %>%
        summarise(
          vars = paste(variable, collapse = ", "),
          top_vals = paste(top_val, collapse = " & "),
          worst_share = max(top_share),
          .groups = "drop"
        )
      ename <- if (!is.null(enum_lookup)) enum_lookup$.ename[match(by_enum$enum, enum_lookup$.enum)] else NA_character_
      unit_df <- tibble::tibble(
        unit_id = by_enum$enum,
        unit_name = ename,
        .issue = sprintf("Enumerator gave the same answer on %s in %.0f%%+ of their surveys", by_enum$vars, enum_thr * 100),
        .value_display = by_enum$top_vals,
        .share_sort = by_enum$worst_share
      )
      parts$enum <- mk_aggregate_finding(
        unit_df, "straightlining_enum", "M9", "straightlining_enum", unit_df$.issue,
        roles, unit_type = "enumerator", value_col = ".value_display", sort_value_col = ".share_sort"
      )
    }
  }

  if (length(ordinal_vars) >= 2) {
    sub_mat <- as.data.frame(lapply(ds[ordinal_vars], as.character), stringsAsFactors = FALSE)
    share <- apply(sub_mat, 1, function(row) {
      row <- row[!is.na(row) & nzchar(row)]
      if (length(row) < 2) return(0)
      max(table(row)) / length(row)
    })
    flag <- share >= survey_thr
    if (any(flag)) {
      tmp <- ds[flag, , drop = FALSE]
      # Reported as a percentage (matching M7's pct_missing convention),
      # not the raw 0-1 fraction - a bare 1-decimal fraction (e.g. 0.9)
      # would lose the precision a percentage keeps (85.3%). .sortv keeps
      # the plain numeric share for ordering, separate from the display string.
      tmp$.sortv <- share[flag]
      tmp$.v <- sprintf("%s%%", round1(share[flag] * 100))
      parts$survey <- mk_findings(
        tmp, "straightlining_survey", "M9", "straightlining_survey",
        sprintf("%.0f%%+ of this submission's ordinal answers are identical", survey_thr * 100),
        roles, ".v", sort_value_col = ".sortv"
      )
    }
  }
  findings <- if (length(parts)) bind_rows(parts) else empty_findings()
  list(findings = findings)
}

# ---- M13 Summary Statistics (descriptive only, never produces findings) ----
# Returns a named list of tables: "Overall" (all rows, unchanged shape) plus
# one additional table per enumerator when modules$M13$by_enum is on (default
# TRUE) — full Variable/Mean/SD/Min/Max/Missing(displayed "NA")/Obs breakdown
# per enumerator, not a replacement for Overall. Missing + Obs = total rows
# considered. Uses roles$enum_name (PII/display name) as the table label when
# available, falling back to the raw enumerator ID.
check_m13 <- function(ds, roles, modules) {
  vars <- modules$M13$vars %||% character()
  vars <- vars[!is.na(vars) & vars %in% names(ds)]
  # SurveyCTO's duration export is always in seconds; if the M4 duration
  # column happens to be in this shortlist, convert it here too - same
  # seconds->minutes convention check_m4() already applies to its own
  # tables, so M13 doesn't show a raw, unconverted (and much larger) number
  # for the same variable.
  duration_col <- modules$M4$duration %||% roles$duration

  mk_table <- function(sub_ds) {
    rows <- lapply(vars, function(vc) {
      v <- safe_num(sub_ds[[vc]])
      if (!is.na(duration_col) && identical(vc, duration_col)) v <- v / 60
      ok <- is.finite(v)
      tibble(Variable = var_label(vc, roles), Mean = round1(mean(v[ok])), SD = round1(stats::sd(v[ok])),
            Min = round1(suppressWarnings(min(v[ok]))), Max = round1(suppressWarnings(max(v[ok]))),
            Missing = sum(!ok), Obs = sum(ok))
    })
    if (length(rows)) bind_rows(rows) else tibble()
  }

  stats <- list(Overall = mk_table(ds))

  by_enum <- isTRUE(modules$M13$by_enum %||% TRUE) && !is.na(roles$enum) && roles$enum %in% names(ds)
  if (by_enum && length(vars)) {
    enum_vals <- as.character(ds[[roles$enum]])
    # resolve_unit_name() decodes a value-labelled ID column when there's no
    # separate name column - falls back to the bare ID string when the
    # column isn't labelled either, filtered out below via `nm != ev` so
    # that case still renders a plain ID label, not a redundant "3 (3)".
    enum_names <- resolve_unit_name(ds, roles$enum, roles$enum_name)
    # Default ("name"): "Name (ID)" label, both visible. Override ("id"):
    # bare ID only, honoring roles$enumerator_display — see
    # resolve_display_vec()'s de-identification-by-default policy.
    show_name <- identical(roles$enumerator_display %||% "name", "name")
    for (ev in sort(unique(enum_vals[!is.na(enum_vals) & nzchar(enum_vals)]))) {
      idx <- which(enum_vals == ev)
      label <- if (show_name) {
        nm <- unique(enum_names[idx]); nm <- nm[!is.na(nm) & nzchar(nm) & nm != ev]
        if (length(nm)) sprintf("%s (%s)", nm[[1]], ev) else ev
      } else ev
      stats[[label]] <- mk_table(ds[idx, , drop = FALSE])
    }
  }
  list(stats = stats)
}

# ---- M12 Consent / assent / audio flags -------------------------------------
check_m12 <- function(ds, roles, modules) {
    form_map <- attr(ds, "hfc_form_map")
    flag_miss <- function(col, check_id, category, issue) {
        if (is.na(col) || !col %in% names(ds)) return(NULL)
        miss <- ds %>% filter(is.na(.data[[col]]) |
                                as.character(.data[[col]]) %in% c("", "0", "No", "no"))
        if (exists("filter_expected_skips", mode = "function") && !is.null(form_map)) {
        miss <- filter_expected_skips(miss, ds, col, form_map)
        }
        # If EVERY surveyed row is flagged, this is one structural problem
        # (the wrong column was detected, or the field was never actually
        # captured for this survey) — a single dataset-level finding, not
        # one per row. Same treatment M11 already gives a completely-empty
        # media column (see media.R's run_m11_media_checks()).
        if (nrow(ds) > 0 && nrow(miss) == nrow(ds)) {
        return(tibble(
            finding_id = paste0("m12:column_empty:", col),
            check_id = paste0(check_id, "_column_empty"),
            check_module = "M12",
            category = paste0(category, "_column_empty"),
            issue = sprintf(
            "%s. Every one of %d surveyed rows is missing/0/No on column '%s'. Likely the wrong column was detected, or this field was never actually captured, not a per-row gap.",
            issue, nrow(ds), var_label(col, roles)
            ),
            submission_id = "", group_id = "", enumerator = "", start_date = "", end_date = "",
            key = "", value = "", variable = col, entity_name = "", group_name = "", enumerator_name = "",
            sort_value = NA_real_
        ))
        }
        mk_findings(miss, check_id, "M12", category, sprintf("%s (column '%s')", issue, var_label(col, roles)), roles)
    }
    parts <- list()
    if (!is.na(roles$assent)) {
        parts$a <- flag_miss(roles$assent, "missing_assent", "assent",
                            "Missing, 0, or No assent flag")
    }
    if (!is.na(roles$consent)) {
        parts$c <- flag_miss(roles$consent, "missing_consent", "consent",
                            "Missing, 0, or No consent flag")
    }
    audio_flag <- modules$M12$audio %||% roles$audio_flag %||% roles$audio
    media_files <- unique(c(roles$audio_file_cols %||% character(),
                            roles$image_file_cols %||% character()))
    if (!is.na(audio_flag) && audio_flag %in% names(ds) && !audio_flag %in% media_files) {
        parts$aud <- flag_miss(audio_flag, "missing_audio_flag", "audio",
                                "Missing, 0, or No audio consent flag")
    }
    parts <- Filter(Negate(is.null), parts)
    findings <- if (length(parts)) bind_rows(parts) else empty_findings()
    list(findings = findings)
}

run_check_modules <- function(ds, roles, modules, code_output_dir = NULL, target_ds = NULL) {
  ds_full <- prepare_ds_for_checks(ds, roles, code_output_dir, target_ds = target_ds)
  # M1 alone sees the FULL, unfiltered ds_full (it needs the complete
  # picture — every row, target-list or all primary+secondary rows — to
  # compute completion rates). Every other module below (M2-M13) sees
  # only the completed/surveyed subset, per the completion redesign: once a
  # "status" completion signal filters out Incomplete/Refused rows, those
  # rows shouldn't be checked for duplicates, outliers, timing, etc.
  ds <- if (any(!ds_full$.hfc_completed)) {
    filtered <- ds_full[ds_full$.hfc_completed, , drop = FALSE]
    attr(filtered, "hfc_form_map") <- attr(ds_full, "hfc_form_map")
    filtered
  } else {
    ds_full
  }
  findings_list <- list()
  stats_list <- list()

  if (isTRUE(modules$M1$on)) {
    tryCatch({
      r <- check_m1(ds_full, roles, modules)
      findings_list$m1 <- r$findings
      stats_list$M1 <- r$stats
    }, error = function(e) message("M1: ", e$message))
  }

  if (isTRUE(modules$M2$on)) {
    tryCatch({
      findings_list$m2 <- check_m2(ds, roles, modules)$findings
    }, error = function(e) message("M2: ", e$message))
  }

  if (isTRUE(modules$M3$on)) {
    tryCatch({
      r <- check_m3(ds, roles, modules)
      findings_list$m3 <- r$findings
      stats_list$M3 <- r$stats
    }, error = function(e) message("M3: ", e$message))
  }

  if (isTRUE(modules$M4$on)) {
    tryCatch({
      r <- check_m4(ds, roles, modules)
      findings_list$m4 <- r$findings
      stats_list$M4 <- r$stats
    }, error = function(e) message("M4: ", e$message))
  }

  if (isTRUE(modules$M5$on)) {
    tryCatch({
      findings_list$m5 <- check_m5(ds, roles, modules)$findings
    }, error = function(e) message("M5: ", e$message))
  }

  if (isTRUE(modules$M6$on)) {
    tryCatch({
      findings_list$m6 <- check_m6(ds, roles, modules)$findings
    }, error = function(e) message("M6: ", e$message))
  }

  if (isTRUE(modules$M7$on)) {
    tryCatch({
      r <- check_m7(ds, roles, modules)
      findings_list$m7 <- r$findings
      stats_list$M7 <- r$stats
    }, error = function(e) message("M7: ", e$message))
  }

  if (isTRUE(modules$M8$on)) {
    tryCatch({
      findings_list$m8 <- check_m8(ds, roles, modules)$findings
    }, error = function(e) message("M8: ", e$message))
  }

  if (isTRUE(modules$M9$on)) {
    tryCatch({
      findings_list$m9 <- check_m9(ds, roles, modules)$findings
    }, error = function(e) message("M9: ", e$message))
  }

  if (isTRUE(modules$M13$on)) {
    tryCatch({
      stats_list$M13 <- check_m13(ds, roles, modules)$stats
    }, error = function(e) message("M13: ", e$message))
  }

  # ---- M10 Survey-specific: custom checks only (fully AI-authored per project) ---
  if (isTRUE(modules$M10$on) || length(modules$M10$custom %||% character()) > 0) {
    custom <- modules$M10$custom %||% character()
    if (!is.null(code_output_dir) && length(custom)) {
      for (cname in custom) {
        if (!nzchar(cname)) next
        cfile <- hfc_path(code_output_dir, "code", "checks", paste0(cname, ".R"))
        if (!file.exists(cfile)) {
          message("Custom check missing: ", cfile)
          next
        }
        tryCatch({
          env <- new.env(parent = globalenv())
          sys.source(cfile, envir = env)
          fn_name <- paste0("run_", cname)
          if (!exists(fn_name, envir = env, mode = "function")) {
            message("Custom check ", cname, " has no ", fn_name, "()")
            next
          }
          out <- env[[fn_name]](ds, roles)
          if (!is.null(out) && nrow(out) > 0) {
            if (!"check_module" %in% names(out)) out$check_module <- "M10"
            findings_list[[paste0("custom_", cname)]] <- out
          }
        }, error = function(e) message("Custom ", cname, ": ", e$message))
      }
    }
  }

  # ---- M11 Media files (delegated to media.R) --------------------------
  if (isTRUE(modules$M11$on) && exists("run_m11_media_checks", mode = "function")) {
    tryCatch({
      findings_list$m11 <- run_m11_media_checks(ds, roles, modules)
    }, error = function(e) message("M11: ", e$message))
  }

  if (isTRUE(modules$M12$on)) {
    tryCatch({
      findings_list$m12 <- check_m12(ds, roles, modules)$findings
    }, error = function(e) message("M12: ", e$message))
  }

  findings <- bind_rows(findings_list)
  if (nrow(findings) == 0) findings <- empty_findings()
  findings <- dedupe_finding_ids(findings)
  list(findings = findings, stats = stats_list)
}
