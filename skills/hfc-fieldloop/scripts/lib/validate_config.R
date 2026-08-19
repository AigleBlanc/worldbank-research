# Build-time config validation — several real Uganda-pilot failures were
# silent: a version_map with a gap in date coverage (Form Version quietly
# stopped validating for those dates, no warning), a roster whose join
# key/value coding drifted after a re-export (joins silently returned
# 0/NA instead of erroring), an agent-resolved role_map.yaml field dropped
# by an incomplete reload block (a module quietly produced zero rows).
# validate_modules_config() checks structural completeness up front and
# returns a clear warning/error list instead of letting these fail
# silently downstream as a suspiciously-empty table. Invoked at the start
# of run_setup_build.R/rebuild_report.R — errors stop() with a collected,
# readable list; warnings message() but never block the build.

#' validate_modules_config(modules, roles, ds = NULL) -> list(ok, errors, warnings)
#' `ds`, when given, enables column-existence checks (skipped, not errored,
#' when ds is NULL — e.g. called before data is loaded).
validate_modules_config <- function(modules, roles, ds = NULL) {
    errors <- character(); warnings <- character()
    has_ds <- !is.null(ds)
    col_exists <- function(col) !is.na(col) && nzchar(col) && (!has_ds || col %in% names(ds))
    missing_col <- function(label, col) {
        if (!is.na(col) && nzchar(col) && has_ds && !col %in% names(ds)) {
        errors <- c(errors, sprintf("%s: column '%s' is configured but not found in the data.", label, col))
        }
        errors
    }

    m1 <- modules$M1 %||% list()

    # Gate arrays (gate_pass_values/gate_labels/gate_min_date are named
    # lists keyed by gate column name, not positionally parallel vectors) —
    # every key should be a real, confirmed gate; an orphaned key is
    # probably a stale leftover from an earlier gate-chain edit.
    gate_cols <- m1$gate_cols %||% character()
    for (nm in c("gate_pass_values", "gate_labels", "gate_min_date")) {
        keys <- names(m1[[nm]] %||% list())
        orphan <- setdiff(keys, gate_cols)
        if (length(orphan)) {
        warnings <- c(warnings, sprintf("M1.%s has entr(y/ies) for column(s) not in gate_cols: %s.", nm, paste(orphan, collapse = ", ")))
        }
    }
    governing_gate <- m1$governing_gate %||% NA_character_
    if (!is.na(governing_gate) && !governing_gate %in% gate_cols) {
        errors <- c(errors, sprintf("M1.governing_gate ('%s') is not one of the confirmed gate_cols.", governing_gate))
    }
    if (has_ds) {
        for (gc in gate_cols) errors <- missing_col("M1.gate_cols", gc)
    }
    if (identical(m1$completion_signal, "gating") && !length(gate_cols)) {
        warnings <- c(warnings, "M1.completion_signal is 'gating' but gate_cols is empty — completion will fall back to 'always complete.'")
    }
    if (identical(m1$completion_signal, "roster") && (is.null(roles$completion_roster_candidate) || is.na(roles$completion_roster_candidate$path %||% NA_character_))) {
        errors <- c(errors, "M1.completion_signal is 'roster' but no roster/target file is configured (roles$completion_roster_candidate).")
    }

    # M6 outlier_mode / fixed_thresholds.
    m6 <- modules$M6 %||% list()
    outlier_mode <- m6$outlier_mode %||% "sd"
    if (!outlier_mode %in% c("sd", "fixed")) {
        errors <- c(errors, sprintf("M6.outlier_mode is '%s' — must be 'sd' or 'fixed'.", outlier_mode))
    }
    if (identical(outlier_mode, "fixed")) {
        ft <- m6$fixed_thresholds %||% list()
        if (!length(ft)) {
        warnings <- c(warnings, "M6.outlier_mode is 'fixed' but fixed_thresholds is empty — every variable will fall back to the SD rule.")
        }
        uncovered <- setdiff(m6$vars %||% character(), names(ft))
        if (length(uncovered) && length(ft)) {
        warnings <- c(warnings, sprintf("M6.fixed_thresholds doesn't cover: %s (falls back to the SD rule for these).", paste(uncovered, collapse = ", ")))
        }
        for (vc in names(ft)) {
        b <- ft[[vc]]
        low <- suppressWarnings(as.numeric(b$low %||% NA_real_)); high <- suppressWarnings(as.numeric(b$high %||% NA_real_))
        if (is.na(low) && is.na(high)) {
            warnings <- c(warnings, sprintf("M6.fixed_thresholds[['%s']] has neither low nor high set — this variable won't flag anything.", vc))
        } else if (!is.na(low) && !is.na(high) && low >= high) {
            errors <- c(errors, sprintf("M6.fixed_thresholds[['%s']]: low (%s) must be less than high (%s).", vc, low, high))
        }
        }
    }
    if (has_ds) for (vc in m6$vars %||% character()) errors <- missing_col("M6.vars", vc)

    # M12 Balance Tables: each grouping's group_col (and roster columns,
    # when configured) must exist.
    for (i in seq_along(modules$M12$groupings %||% list())) {
        g <- modules$M12$groupings[[i]]
        gl <- sprintf("M12.groupings[[%d]] ('%s')", i, g$group_label %||% g$group_col %||% i)
        if (is.null(g$group_col) || is.na(g$group_col)) {
        errors <- c(errors, sprintf("%s has no group_col configured.", gl))
        } else if (has_ds) {
        errors <- missing_col(gl, g$group_col)
        }
        if (!is.null(g$other_group_col) && !is.na(g$other_group_col) && has_ds) {
        errors <- missing_col(paste0(gl, ".other_group_col"), g$other_group_col)
        }
        cov <- g$covariates %||% character()
        if (has_ds) for (cv in cov) errors <- missing_col(paste0(gl, ".covariates"), cv)
    }

    # Straightforward column-existence checks across the rest of the
    # confirmed modules, when ds is available — the class of bug this
    # whole function exists to catch: a role/module column that got
    # silently dropped somewhere between profiling and the saved yaml.
    if (has_ds) {
        for (col in c(modules$M2$id %||% character(), modules$M2$extra_keys %||% character())) errors <- missing_col("M2", col)
        if (!is.null(modules$M3$version_col)) errors <- missing_col("M3.version_col", modules$M3$version_col %||% NA_character_)
        if (!is.null(modules$M4$duration)) errors <- missing_col("M4.duration", modules$M4$duration %||% NA_character_)
        for (vc in modules$M7$vars %||% character()) errors <- missing_col("M7.vars", vc)
        for (vc in modules$M8$ordinal_vars %||% character()) errors <- missing_col("M8.ordinal_vars", vc)
        for (col in c(modules$M13$audio_cols %||% character(), modules$M13$image_cols %||% character(), modules$M13$other_cols %||% character())) {
        errors <- missing_col("M13", col)
        }
        for (nm in c("assent", "consent", "audio")) {
        col <- modules$M14[[nm]] %||% NA_character_
        if (!is.na(col)) errors <- missing_col(paste0("M14.", nm), col)
        }
    }

    # M3 version_map: a gap in date coverage silently stops validating for
    # dates that fall in the gap (the real Uganda-pilot incident this
    # specifically guards against) — check every window is contiguous with
    # the next, not just individually well-formed.
    vm <- modules$M3$version_map %||% list()
    if (length(vm) >= 2) {
        starts <- suppressWarnings(as.Date(vapply(vm, function(v) as.character(v$date_start %||% NA), character(1))))
        ends <- suppressWarnings(as.Date(vapply(vm, function(v) as.character(v$date_end %||% NA), character(1))))
        ord <- order(starts)
        starts_o <- starts[ord]; ends_o <- ends[ord]
        for (i in seq_len(length(starts_o) - 1)) {
        if (!is.na(ends_o[i]) && !is.na(starts_o[i + 1]) && ends_o[i] + 1 < starts_o[i + 1]) {
            warnings <- c(warnings, sprintf(
            "M3.version_map has a gap: %s to %s falls between two configured windows and will never validate.",
            format(ends_o[i] + 1), format(starts_o[i + 1] - 1)
            ))
        }
        }
    }

    list(ok = length(errors) == 0, errors = unique(errors), warnings = unique(warnings))
}

#' Human-readable summary. `stop_on_error`: TRUE in the pipeline entry
#' scripts (fail fast, readable message instead of a downstream cryptic
#' error); FALSE for a dry-run/inspection caller that just wants the text.
format_config_validation <- function(v, stop_on_error = FALSE) {
    if (isTRUE(v$ok) && !length(v$warnings)) {
        msg <- "Config validation: OK."
        if (stop_on_error) message(msg)
        return(msg)
    }
    lines <- character()
    if (length(v$errors)) lines <- c(lines, paste0("ERROR: ", v$errors))
    if (length(v$warnings)) lines <- c(lines, paste0("Warning: ", v$warnings))
    msg <- paste0("Config validation:\n  ", paste(lines, collapse = "\n  "))
    if (stop_on_error && !isTRUE(v$ok)) stop(msg)
    if (stop_on_error) message(msg)
    msg
}
