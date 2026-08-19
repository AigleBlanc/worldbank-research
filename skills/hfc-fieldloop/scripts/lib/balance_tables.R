# M12 Balance Tables — descriptive-only RCT balance check, gt-rendered.
# Standard survey balance workflow: for each configured grouping (e.g.
# extension arm, data incentive), four tables in a fixed order — completed-
# interview counts, covariate balance, a differential-completion regression,
# and replacement usage. Never produces findings (report_sections.json:
# "Descriptive only, never produces findings — this section describes the
# randomization and attrition pattern, it doesn't flag a data-quality
# problem"). Sourced alongside build_outputs.R/run_checks.R by both
# run_setup_build.R and rebuild_report.R; overrides the fallback stub
# defined in build_outputs.R (CUSTOM_HTML_RENDERERS$M12).
#
# Depends on gt (rendering) and sandwich+lmtest (cluster-robust SEs for the
# completion regression) — install.R checks for these; a missing package
# degrades to a visible note rather than a build error.
# Depends on run_checks.R's compute_completion_flag() and
# compute_replacement_roster_summary() (shared with check_m1(), so M1 and
# M12 never compute completion or the roster join two different ways).

# "p = .032" / "p < .001" — p-values are exempt from the report's general
# 1-decimal rounding rule (Phase 3k): collapsing to 1 decimal would show
# "0.0" for nearly every significant result, defeating the point of the
# bold/red significance styling below.
bt_format_pval <- function(p) {
    if (is.null(p) || length(p) == 0 || is.na(p)) return(NA_character_)
    if (p < 0.001) return("< .001")
    sprintf("%.3f", p)
}

#' Table 1 — Completed interviews by <group>: Submitted/Completed/Completion
#' Rate per group value, plus a Total column. Every attempted row counts as
#' "Submitted," the completed-only subset as "Completed" — the SAME
#' complete_flag compute_completion_flag() gives check_m1(), row-aligned to
#' `ds` (under "roster" mode every ds row is a completed survey by
#' construction, same convention used throughout run_checks.R).
bt_completed_interviews_tbl <- function(ds, cf, group_col, group_label) {
    if (is.null(group_col) || is.na(group_col) || !group_col %in% names(ds)) return(NULL)
    ds_complete_flag <- if (identical(cf$sig, "roster")) rep(TRUE, nrow(ds)) else cf$complete_flag
    grp <- as.character(ds[[group_col]])
    df <- tibble::tibble(grp = grp, complete = ds_complete_flag) %>%
        dplyr::filter(!is.na(grp), nzchar(grp))
    if (!nrow(df)) return(NULL)
    counts <- df %>%
        dplyr::group_by(grp) %>%
        dplyr::summarise(submitted = dplyr::n(), completed = sum(complete, na.rm = TRUE), .groups = "drop") %>%
        dplyr::arrange(grp)
    if (nrow(counts) < 2) return(NULL)
    total_submitted <- sum(counts$submitted)
    total_completed <- sum(counts$completed)
    pct <- function(num, den) if (den > 0) sprintf("%s%%", round1(100 * num / den)) else ""
    # Column NAMES stay internal-safe (..grp1.., ..grp2.., ...), never the
    # raw group value text — a group value can collide with group_label
    # itself (e.g. group_label "Treatment" when one arm's own value is also
    # "Treatment"), which would otherwise break tibble's unique-column-name
    # requirement. Display labels are applied separately via
    # gt::cols_label() in bt_gt_simple(), decoupled from the R-level name.
    out <- tibble::tibble(.label = c("Submitted Surveys", "Completed Interviews", "Completion Rate"))
    col_labels <- character()
    for (i in seq_len(nrow(counts))) {
        cn <- sprintf("..grp%d..", i)
        out[[cn]] <- c(
            as.character(counts$submitted[i]), as.character(counts$completed[i]),
            pct(counts$completed[i], counts$submitted[i])
        )
        col_labels[cn] <- counts$grp[i]
    }
    out[[".total"]] <- c(as.character(total_submitted), as.character(total_completed), pct(total_completed, total_submitted))
    col_labels[".total"] <- "Total"
    col_labels[".label"] <- group_label
    attr(out, "bt_col_labels") <- col_labels
    out
}

#' Table 2 — By <group>: per-covariate Mean(SD)/N per group among completed
#' interviews only, plus a Welch ANOVA p-value (reduces to a Welch
#' two-sample t-test at exactly 2 groups). Returns list(df, groups) rather
#' than a plain tibble — the render step needs `groups` separately to build
#' gt's spanning column headers.
bt_balance_tbl <- function(ds, roles, cf, group_col, covariates) {
    if (is.null(group_col) || is.na(group_col) || !group_col %in% names(ds) || !length(covariates)) return(NULL)
    ds_complete_flag <- if (identical(cf$sig, "roster")) rep(TRUE, nrow(ds)) else cf$complete_flag
    ds_c <- ds[ds_complete_flag %in% TRUE, , drop = FALSE]
    grp <- as.character(ds_c[[group_col]])
    ok_grp <- !is.na(grp) & nzchar(grp)
    ds_c <- ds_c[ok_grp, , drop = FALSE]
    grp <- grp[ok_grp]
    groups <- sort(unique(grp))
    if (length(groups) < 2) return(NULL)
    rows <- list()
    for (cv in covariates) {
        if (!cv %in% names(ds_c)) next
        v <- safe_num(ds_c[[cv]])
        ok <- is.finite(v)
        if (sum(ok) < 2) next
        row <- list(Covariate = var_label(cv, roles))
        for (g in groups) {
            idx <- ok & grp == g
            n_g <- sum(idx)
            mean_g <- if (n_g >= 1) round1(mean(v[idx])) else NA_real_
            sd_g <- if (n_g >= 2) round1(stats::sd(v[idx])) else NA_real_
            row[[paste0(g, "__meansd")]] <- if (n_g >= 1) sprintf("%s<br>(%s)", mean_g, ifelse(is.na(sd_g), "-", sd_g)) else "-"
            row[[paste0(g, "__n")]] <- n_g
        }
        p <- tryCatch({
            if (length(unique(grp[ok])) < 2) NA_real_ else stats::oneway.test(v[ok] ~ factor(grp[ok]), var.equal = FALSE)$p.value
        }, error = function(e) NA_real_)
        row[["P value"]] <- p
        rows[[cv]] <- tibble::as_tibble(row)
    }
    if (!length(rows)) return(NULL)
    list(df = dplyr::bind_rows(rows), groups = groups)
}

#' Table 3 — Completion regression by <group>: does group predict whether a
#' submission was ever completed at all (not just covariate balance among
#' completers) — the standard "differential attrition" check. Linear
#' probability model of completion on the group (plus `other_group_col`, a
#' second grouping in the same joint model, when configured) with
#' respondent-group fixed effects, SEs clustered by respondent group
#' (roles$group — this survey's own stratification/site unit, NOT the
#' treatment arm itself). One row per non-reference group level.
#' sandwich+lmtest, not estimatr — already available, avoids a new
#' dependency (see install.R).
bt_completion_regression_tbl <- function(ds, roles, cf, group_col, group_label, other_group_col = NA_character_) {
    if (is.null(group_col) || is.na(group_col) || !group_col %in% names(ds)) return(NULL)
    cluster_col <- roles$group
    if (is.na(cluster_col) || !cluster_col %in% names(ds)) return(NULL)
    if (!requireNamespace("sandwich", quietly = TRUE) || !requireNamespace("lmtest", quietly = TRUE)) return(NULL)
    ds_complete_flag <- if (identical(cf$sig, "roster")) rep(TRUE, nrow(ds)) else cf$complete_flag
    grp <- as.character(ds[[group_col]])
    ok <- !is.na(grp) & nzchar(grp) & !is.na(ds[[cluster_col]]) & nzchar(as.character(ds[[cluster_col]]))
    if (sum(ok) < 10) return(NULL)
    reg_df <- data.frame(
        completion = as.integer(ds_complete_flag[ok]),
        grp = grp[ok],
        clust = as.character(ds[[cluster_col]])[ok],
        stringsAsFactors = FALSE
    )
    has_other <- !is.na(other_group_col) && other_group_col %in% names(ds)
    if (has_other) reg_df$other <- as.character(ds[[other_group_col]])[ok]
    reg_df <- reg_df[!is.na(reg_df$grp) & nzchar(reg_df$grp), , drop = FALSE]
    groups <- sort(unique(reg_df$grp))
    if (length(groups) < 2 || length(unique(reg_df$clust)) < 2) return(NULL)
    ref <- groups[1]
    reg_df$grp <- stats::relevel(factor(reg_df$grp), ref = ref)
    formula_full <- if (has_other) "completion ~ grp + other + factor(clust)" else "completion ~ grp + factor(clust)"
    formula_restricted <- if (has_other) "completion ~ other + factor(clust)" else "completion ~ factor(clust)"
    fit_full <- tryCatch(stats::lm(stats::as.formula(formula_full), data = reg_df), error = function(e) NULL)
    if (is.null(fit_full)) return(NULL)
    vc <- tryCatch(sandwich::vcovCL(fit_full, cluster = reg_df$clust, type = "HC1"), error = function(e) NULL)
    if (is.null(vc)) return(NULL)
    ct <- tryCatch(lmtest::coeftest(fit_full, vcov. = vc), error = function(e) NULL)
    if (is.null(ct)) return(NULL)
    grp_rows <- grep("^grp", rownames(ct))
    if (!length(grp_rows)) return(NULL)
    out <- tibble::tibble(
        Group = sub("^grp", "", rownames(ct)[grp_rows]),
        `Ref.` = ref,
        `Difference (pp)` = round1(ct[grp_rows, "Estimate"] * 100),
        `SE (pp)` = round1(ct[grp_rows, "Std. Error"] * 100),
        `P value` = ct[grp_rows, "Pr(>|t|)"]
    )
    names(out)[1] <- group_label
    joint_p <- tryCatch({
        fit_restricted <- stats::lm(stats::as.formula(formula_restricted), data = reg_df)
        wt <- lmtest::waldtest(fit_restricted, fit_full, vcov = vc, test = "F")
        wt[["Pr(>F)"]][2]
    }, error = function(e) NA_real_)
    n_clusters <- length(unique(reg_df$clust))
    cluster_label <- tolower(roles$group_label %||% "group")
    source_note <- sprintf(
        "Linear probability model of completion on %s%s, with %s fixed effects, SEs clustered by %s (%d groups, n=%d).%s",
        tolower(group_label), if (has_other) " and the other grouping" else "",
        cluster_label, cluster_label, n_clusters, nrow(reg_df),
        if (!is.na(joint_p)) sprintf(" Joint test that no arm differs from %s: p = %s.", ref, bt_format_pval(joint_p)) else ""
    )
    list(df = out, source_note = source_note)
}

#' Table 4 — Replacements by <group>: how successfully respondents are
#' being replaced in each group, via the roster join shared with M1
#' (compute_replacement_roster_summary(), run_checks.R). `roster_group_col`
#' lets this grouping join on a different roster column than the survey
#' data's own group_col when they're named differently; `roster_value_map`
#' remaps roster-side raw values to the data-side coding when they differ
#' (e.g. roster "1,2,3" vs data "Control,Treat1,Treat2").
bt_replacements_tbl <- function(ds, roles, modules, target_ds, cf, group_col, group_label,
                                roster_group_col = NA_character_, roster_value_map = NULL) {
    repl <- compute_replacement_roster_summary(
        ds, roles, modules, target_ds, cf$sig, cf$complete_flag,
        group_col = if (!is.na(roster_group_col)) roster_group_col else group_col,
        value_map = roster_value_map
    )
    if (is.null(repl) || !nrow(repl$by_group_repl)) return(NULL)
    out <- repl$by_group_repl %>%
        dplyr::transmute(
        group,
        `Non-Completed Primary` = n_primary - n_primary_completed,
        `Replacements N` = n_replaced,
        `Replacement Success %` = ifelse(
            (n_primary - n_primary_completed) > 0,
            sprintf("%s%%", round1(100 * n_replaced / (n_primary - n_primary_completed))),
            ""
        )
        )
    names(out)[1] <- group_label
    out
}

# ---- gt rendering -----------------------------------------------------------

bt_gt_simple <- function(df, sig_col = NULL, source_note = NULL) {
    g <- gt::gt(df)
    # Internal-safe column names (bt_completed_interviews_tbl(), when a
    # group value could otherwise collide with group_label as an R-level
    # column name) get their real display labels applied here instead.
    col_labels <- attr(df, "bt_col_labels")
    if (!is.null(col_labels)) g <- gt::cols_label(g, .list = as.list(col_labels))
    if (!is.null(sig_col) && sig_col %in% names(df)) {
        g <- gt::tab_style(
        g, style = list(gt::cell_text(weight = "bold", color = "#c0392b")),
        locations = gt::cells_body(columns = sig_col, rows = !is.na(df[[sig_col]]) & df[[sig_col]] < 0.05)
        )
        g <- gt::text_transform(
        g, locations = gt::cells_body(columns = sig_col),
        fn = function(x) vapply(as.numeric(x), bt_format_pval, character(1))
        )
    }
    if (!is.null(source_note)) g <- gt::tab_source_note(g, source_note = source_note)
    as.character(gt::as_raw_html(g))
}

bt_gt_balance <- function(bal) {
    df <- bal$df; groups <- bal$groups
    g <- gt::gt(df)
    lbl_list <- list()
    for (grp in groups) {
        g <- gt::tab_spanner(g, label = grp, columns = c(paste0(grp, "__meansd"), paste0(grp, "__n")))
        lbl_list[[paste0(grp, "__meansd")]] <- "Mean (SD)"
        lbl_list[[paste0(grp, "__n")]] <- "N"
    }
    g <- gt::cols_label(g, .list = lbl_list)
    g <- gt::fmt_markdown(g, columns = dplyr::ends_with("__meansd"))
    g <- gt::sub_missing(g, missing_text = "-")
    g <- gt::tab_style(
        g, style = list(gt::cell_text(weight = "bold", color = "#c0392b")),
        locations = gt::cells_body(columns = "P value", rows = !is.na(df[["P value"]]) & df[["P value"]] < 0.05)
    )
    g <- gt::text_transform(
        g, locations = gt::cells_body(columns = "P value"),
        fn = function(x) vapply(as.numeric(x), bt_format_pval, character(1))
    )
    as.character(gt::as_raw_html(g))
}

# ---- entry point -------------------------------------------------------------

#' M12's custom_html body (CUSTOM_HTML_RENDERERS$M12, build_outputs.R). No
#' outer <section> wrapper — the per-module render loop supplies that
#' generically. Renders each configured grouping's four tables in the
#' spec's fixed order (Completed Interviews, By <group>, Completion
#' Regression, Replacements), skipping any table whose prerequisites aren't
#' met rather than erroring the whole report build.
render_balance_tables_body <- function(ds, roles, modules, findings = NULL, target_ds = NULL, report_cfg = NULL) {
    groupings <- modules$M12$groupings %||% list()
    if (!length(groupings) || is.null(ds)) {
        return("<p class='no-issues'>Balance Tables is on, but no groupings are configured yet.</p>")
    }
    if (!requireNamespace("gt", quietly = TRUE)) {
        return("<p class='no-issues'>Balance Tables requires the 'gt' package, which isn't installed.</p>")
    }
    # compute_completion_flag() reads target_ds off ds's own "hfc_target_ds"
    # attribute (set by prepare_ds_for_checks() inside run_check_modules())
    # — but the `ds` passed to write_html_report(), and threaded through to
    # this renderer, never goes through that function. Attach it here from
    # this function's own target_ds parameter so "roster" completion_signal
    # resolves correctly instead of silently falling through with no
    # complete_flag assigned at all.
    if (is.null(attr(ds, "hfc_target_ds")) && !is.null(target_ds)) {
        attr(ds, "hfc_target_ds") <- target_ds
    }
    cf <- compute_completion_flag(ds, roles, modules)
    esc <- function(x) {
        x <- as.character(x); x[is.na(x)] <- ""
        x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE); x <- gsub(">", "&gt;", x, fixed = TRUE)
        x
    }
    parts <- character()
    for (i in seq_along(groupings)) {
        g <- groupings[[i]]
        group_col <- g$group_col %||% NA_character_
        group_label <- g$group_label %||% group_col %||% sprintf("Grouping %d", i)
        if (is.na(group_col)) next
        slug <- gsub("[^A-Za-z0-9]+", "-", tolower(group_label))

        tbl1 <- bt_completed_interviews_tbl(ds, cf, group_col, group_label)
        tbl2 <- bt_balance_tbl(ds, roles, cf, group_col, g$covariates %||% character())
        tbl3 <- bt_completion_regression_tbl(ds, roles, cf, group_col, group_label, g$other_group_col %||% NA_character_)
        tbl4 <- bt_replacements_tbl(ds, roles, modules, target_ds, cf, group_col, group_label,
                                    g$roster_group_col %||% NA_character_, g$roster_value_map %||% NULL)

        if (is.null(tbl1) && is.null(tbl2) && is.null(tbl3) && is.null(tbl4)) next

        if (!is.null(tbl1)) {
        parts <- c(parts, sprintf(
            "<h4>Completed interviews by %s</h4><div id='tbl-m12-completed-%s'>%s</div>",
            esc(tolower(group_label)), slug, bt_gt_simple(tbl1)
        ))
        }
        if (!is.null(tbl2)) {
        parts <- c(parts, sprintf(
            "<h4>By %s</h4><div id='tbl-m12-balance-%s'>%s</div>",
            esc(tolower(group_label)), slug, bt_gt_balance(tbl2)
        ))
        }
        if (!is.null(tbl3)) {
        parts <- c(parts, sprintf(
            "<h4>Completion regression by %s</h4><div id='tbl-m12-regression-%s'>%s</div>",
            esc(tolower(group_label)), slug, bt_gt_simple(tbl3$df, sig_col = "P value", source_note = tbl3$source_note)
        ))
        }
        if (!is.null(tbl4)) {
        parts <- c(parts, sprintf(
            "<h4>Replacements by %s</h4><div id='tbl-m12-replacements-%s'>%s</div>",
            esc(tolower(group_label)), slug, bt_gt_simple(tbl4)
        ))
        }
    }
    if (!length(parts)) {
        return("<p class='no-issues'>Balance Tables is on, but no configured grouping had enough data to report.</p>")
    }
    paste(parts, collapse = "")
}
