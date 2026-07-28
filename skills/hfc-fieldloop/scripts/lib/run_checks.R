# Run M1-M13 checks given ds, roles, modules config.
# Returns list(findings = <tibble>, stats = <named list of data.frames per module>).
# Optional project_root: sources custom checks from hfc/checks/*.R (run_<name>).

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

run_check_modules <- function(ds, roles, modules, project_root = NULL) {
  suppressPackageStartupMessages({
    library(dplyr); library(lubridate); library(tibble)
  })
  findings_list <- list()
  stats_list <- list()
  form_map <- attr(ds, "hfc_form_map")
  if (is.null(form_map) && !is.null(project_root)) {
    fp <- hfc_path(project_root, "instrument", "form.xlsx")
    if (file.exists(fp) && exists("parse_form_relevance", mode = "function")) {
      form_map <- parse_form_relevance(fp)
    }
  }
  ds$.hfc_row <- seq_len(nrow(ds))
  ds$.hfc_id_display <- composite_id_string(ds, roles$id, roles$id_sep %||% " / ")

  # ---- M1 Completion --------------------------------------------------------
  if (isTRUE(modules$M1$on)) {
    tryCatch({
      completion_var <- modules$M1$completion_var %||% NA_character_
      complete_flag <- if (!is.na(completion_var) && completion_var %in% names(ds)) {
        is_complete_value(ds[[completion_var]])
      } else {
        row_missing_ratio(ds, setdiff(names(ds), c(".hfc_row", ".hfc_id_display"))) <= 0.1
      }
      stats_overall <- completion_summary(complete_flag)
      group_vars <- modules$M1$group_vars %||% character()
      by_group <- lapply(group_vars[group_vars %in% names(ds)], function(gv) {
        completion_summary(complete_flag, ds[[gv]]) %>%
          mutate(group_var = gv, .before = 1) %>%
          rename(value = group)
      })
      by_group_df <- if (length(by_group)) bind_rows(by_group) else tibble()
      by_enum_df <- if (isTRUE(modules$M1$by_enum %||% TRUE) && !is.na(roles$enum) && roles$enum %in% names(ds)) {
        completion_summary(complete_flag, ds[[roles$enum]]) %>% rename(enumerator = group)
      } else tibble()
      by_date_df <- if (isTRUE(modules$M1$by_date %||% TRUE) && !is.na(roles$start) && roles$start %in% names(ds)) {
        d <- suppressWarnings(as.Date(as.character(ds[[roles$start]])))
        completion_summary(complete_flag, as.character(d)) %>% rename(date = group) %>% arrange(desc(date))
      } else tibble()
      stats_list$M1 <- list(overall = stats_overall, by_group = by_group_df,
                            by_enumerator = by_enum_df, by_date = by_date_df)

      if (isTRUE(modules$M1$low_completion_on) && !is.na(roles$school) && roles$school %in% names(ds)) {
        pct_median <- modules$M1$pct_median %||% 0.5
        counts <- ds %>% mutate(.complete = complete_flag) %>%
          filter(.complete, !is.na(.data[[roles$school]])) %>%
          group_by(.data[[roles$school]]) %>% summarise(n = n(), .groups = "drop")
        if (nrow(counts) > 1) {
          tgt <- stats::median(counts$n)
          low_units <- counts[[roles$school]][counts$n < pct_median * tgt]
          if (length(low_units)) {
            flagged <- ds[as.character(ds[[roles$school]]) %in% as.character(low_units), , drop = FALSE]
            findings_list$m1_low <- mk_findings(
              flagged, "low_completion", "M1", "low_completion",
              sprintf("Site has fewer completed submissions than %.0f%% of the median", 100 * pct_median),
              roles
            )
          }
        }
      }
    }, error = function(e) message("M1: ", e$message))
  }

  # ---- M2 Duplicates (was M1) ------------------------------------------------
  if (isTRUE(modules$M2$on)) {
    tryCatch({
      idc <- modules$M2$id %||% roles$id
      idc <- idc[!is.na(idc) & nzchar(as.character(idc)) & idc %in% names(ds)]
      if (length(idc)) {
        dups <- ds %>%
          filter(if_all(all_of(idc), ~ !is.na(.) & as.character(.) != "")) %>%
          group_by(across(all_of(idc))) %>%
          filter(n() > 1) %>%
          ungroup()
        findings_list$m2 <- mk_findings(dups, "duplicates_id", "M2", "duplicates",
                                        "Duplicate submission ID", roles)
        if (nrow(dups) == 0 && !is.na(roles$key) && roles$key %in% names(ds)) {
          dups2 <- ds %>%
            filter(!is.na(.data[[roles$key]]), as.character(.data[[roles$key]]) != "") %>%
            group_by(.data[[roles$key]]) %>%
            filter(n() > 1) %>%
            ungroup()
          findings_list$m2b <- mk_findings(dups2, "duplicates_key", "M2", "duplicates",
                                           "Duplicate survey KEY", roles)
        }
      }
    }, error = function(e) message("M2: ", e$message))
  }

  # ---- M3 Form Version --------------------------------------------------------
  if (isTRUE(modules$M3$on)) {
    tryCatch({
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
          stats_list$M3 <- by_version
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
            findings_list$m3 <- mk_findings(
              tmp, "form_version_mismatch", "M3", "form_version_mismatch",
              "Recorded form version doesn't match the expected version for this date", roles, ".v"
            )
          }
        }
      } else if (length(version_map)) {
        rows <- lapply(version_map, function(v) {
          tibble(version = v$version_label, date_start = v$date_start, date_end = v$date_end)
        })
        stats_list$M3 <- bind_rows(rows)
      }
    }, error = function(e) message("M3: ", e$message))
  }

  # ---- M4 Survey Duration (was M2's duration half) ----------------------------
  if (isTRUE(modules$M4$on)) {
    tryCatch({
      dc <- modules$M4$duration %||% roles$duration
      sd_rule <- modules$M4$sd_rule %||% 3
      if (!is.na(dc) && dc %in% names(ds)) {
        dur <- safe_num(ds[[dc]])
        ok <- is.finite(dur)
        stat_row <- function(label, vals) {
          tibble(level = label, n = sum(is.finite(vals)),
                mean = round(mean(vals, na.rm = TRUE), 1), median = round(stats::median(vals, na.rm = TRUE), 1),
                sd = round(stats::sd(vals, na.rm = TRUE), 1),
                min = round(suppressWarnings(min(vals, na.rm = TRUE)), 1),
                max = round(suppressWarnings(max(vals, na.rm = TRUE)), 1))
        }
        stats_overall <- stat_row("Overall", dur[ok])
        # Per-section duration requires the data to carry its own per-section
        # timing columns (uncommon in standard SurveyCTO exports); section_map
        # (column -> section label) is used for labeling elsewhere but there's
        # no sub-duration to split here unless such columns exist.
        section_dur_cols <- grep("_duration$", setdiff(names(ds), dc), value = TRUE)
        section_map <- modules$M4$section_map %||% list()
        stats_section <- if (length(section_dur_cols)) {
          bind_rows(lapply(section_dur_cols, function(cn) {
            label <- section_map[[cn]] %||% cn
            stat_row(label, safe_num(ds[[cn]]))
          }))
        } else tibble()
        stats_by_enum <- if (isTRUE(modules$M4$by_enum %||% TRUE) && !is.na(roles$enum) && roles$enum %in% names(ds)) {
          ds %>% mutate(.dur = dur) %>% filter(is.finite(.dur)) %>%
            group_by(enumerator = as.character(.data[[roles$enum]])) %>%
            summarise(n = n(), mean = round(mean(.dur), 1), median = round(stats::median(.dur), 1),
                      sd = round(stats::sd(.dur), 1), min = round(min(.dur), 1), max = round(max(.dur), 1),
                      .groups = "drop")
        } else tibble()
        stats_list$M4 <- list(overall = stats_overall, by_section = stats_section, by_enumerator = stats_by_enum)

        mu <- mean(dur[ok]); sdv <- stats::sd(dur[ok])
        if (is.finite(mu) && is.finite(sdv) && sdv > 0) {
          long_flag <- ok & dur > mu + sd_rule * sdv
          short_flag <- ok & dur < mu - sd_rule * sdv & dur > 0
          if (any(long_flag)) {
            tmp <- ds[long_flag, , drop = FALSE]; tmp$.v <- dur[long_flag]
            findings_list$m4_long <- mk_findings(
              tmp, "long_duration", "M4", "long_duration",
              sprintf("Interview duration more than %s SD above the mean", sd_rule), roles, ".v"
            )
          }
          if (any(short_flag)) {
            tmp <- ds[short_flag, , drop = FALSE]; tmp$.v <- dur[short_flag]
            findings_list$m4_short <- mk_findings(
              tmp, "short_duration", "M4", "short_duration",
              sprintf("Interview duration more than %s SD below the mean", sd_rule), roles, ".v"
            )
          }
        }
      }
    }, error = function(e) message("M4: ", e$message))
  }

  # ---- M5 Irregular Timing (was M2's early-start half, now tz-aware) ---------
  if (isTRUE(modules$M5$on)) {
    tryCatch({
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
          findings_list$m5 <- mk_findings(
            tmp, "irregular_time", "M5", "irregular_time",
            "Interview conducted at an irregular time (weekend or outside normal hours)", roles, ".v"
          )
        }
      }
    }, error = function(e) message("M5: ", e$message))
  }

  # ---- M6 Numeric Outliers (was M7; up to 10 vars, clean two-sided N-SD) -----
  if (isTRUE(modules$M6$on)) {
    tryCatch({
      vars <- modules$M6$vars %||% utils::head(roles$numeric_shortlist, 10)
      vars <- vars[!is.na(vars) & vars %in% names(ds)]
      sd_rule <- modules$M6$sd_rule %||% 3
      for (vc in vars) {
        v <- safe_num(ds[[vc]])
        ok <- is.finite(v)
        if (sum(ok) < 30) next
        mu <- mean(v[ok]); sdv <- stats::sd(v[ok])
        if (!is.finite(sdv) || sdv <= 0) next
        flag <- ok & abs(v - mu) > sd_rule * sdv
        if (!any(flag)) next
        tmp <- ds[flag, , drop = FALSE]
        tmp$.v <- v[flag]
        catg <- if (identical(vc, roles$age) || grepl("age", vc, ignore.case = TRUE)) "age_outlier" else "numeric_outlier"
        label <- if (catg == "age_outlier") {
          sprintf("Age outlier (beyond %s SD)", sd_rule)
        } else {
          sprintf("Numeric outlier on %s (beyond %s SD)", vc, sd_rule)
        }
        findings_list[[paste0("m6_", vc)]] <- mk_findings(
          utils::head(tmp, 200), sprintf("outlier_%s", vc), "M6", catg, label, roles, ".v"
        )
      }
    }, error = function(e) message("M6: ", e$message))
  }

  # ---- M7 Missingness ----------------------------------------------------------
  if (isTRUE(modules$M7$on)) {
    tryCatch({
      vars <- modules$M7$vars %||% character()
      vars <- vars[!is.na(vars) & vars %in% names(ds)]
      sentinel <- modules$M7$sentinel_codes %||% character()
      sentinel_is_map <- is.list(sentinel) && !is.null(names(sentinel))
      by_enum <- isTRUE(modules$M7$by_enum %||% TRUE) && !is.na(roles$enum) && roles$enum %in% names(ds)
      by_var <- list(); by_enum_list <- list()
      for (vc in vars) {
        codes <- if (sentinel_is_map) sentinel[[vc]] %||% character() else sentinel
        x <- ds[[vc]]
        miss <- is.na(x) | as.character(x) %in% as.character(codes)
        by_var[[vc]] <- tibble(variable = vc, pct_missing = round(100 * mean(miss), 1),
                                n_missing = sum(miss), n = length(miss))
        if (by_enum) {
          by_e <- tibble(enumerator = as.character(ds[[roles$enum]]), miss = miss) %>%
            filter(!is.na(enumerator), nzchar(enumerator)) %>%
            group_by(enumerator) %>%
            summarise(pct_missing = round(100 * mean(miss), 1), n = n(), .groups = "drop") %>%
            mutate(variable = vc)
          by_enum_list[[vc]] <- by_e
          global_pct <- mean(miss) * 100
          sdv <- stats::sd(by_e$pct_missing, na.rm = TRUE)
          if (is.finite(sdv) && sdv > 0) {
            hi <- by_e$enumerator[by_e$pct_missing > global_pct + 2 * sdv]
            if (length(hi)) {
              flagged <- ds[as.character(ds[[roles$enum]]) %in% hi, , drop = FALSE]
              findings_list[[paste0("m7_", vc)]] <- mk_findings(
                flagged, sprintf("high_missing_%s", vc), "M7", "high_missingness",
                sprintf("Enumerator has unusually high missingness on %s", vc), roles
              )
            }
          }
        }
      }
      stats_list$M7 <- list(
        by_variable = if (length(by_var)) bind_rows(by_var) else tibble(),
        by_enumerator = if (length(by_enum_list)) bind_rows(by_enum_list) else tibble()
      )
    }, error = function(e) message("M7: ", e$message))
  }

  # ---- M8 GPS (was M3, logic unchanged) ---------------------------------------
  if (isTRUE(modules$M8$on)) {
    tryCatch({
      xc <- modules$M8$x %||% roles$x
      yc <- modules$M8$y %||% roles$y
      thr <- modules$M8$threshold_m %||% 300
      sch <- roles$school
      if (!is.na(xc) && !is.na(yc) && !is.na(sch) && all(c(xc, yc, sch) %in% names(ds))) {
        tmp <- ds %>%
          mutate(x = safe_num(.data[[xc]]), y = safe_num(.data[[yc]]), sch = .data[[sch]]) %>%
          filter(is.finite(x), is.finite(y), !is.na(sch))
        ref <- tmp %>% group_by(sch) %>% summarise(rx = median(x), ry = median(y), .groups = "drop")
        tmp <- tmp %>% left_join(ref, by = "sch") %>%
          mutate(dist_m = sqrt((x - rx)^2 + (y - ry)^2))
        if (median(abs(tmp$x), na.rm = TRUE) < 180 && median(abs(tmp$y), na.rm = TRUE) < 90) {
          if (requireNamespace("geosphere", quietly = TRUE)) {
            tmp$dist_m <- geosphere::distHaversine(cbind(tmp$x, tmp$y), cbind(tmp$rx, tmp$ry))
          }
        }
        flagged <- tmp %>% filter(is.finite(dist_m), dist_m > thr)
        if (nrow(flagged) > 0) {
          flagged$.v <- as.character(round(flagged$dist_m))
          findings_list$m8 <- mk_findings(
            flagged, "gps_distance", "M8", "gps_distance",
            sprintf("Distance between reference and survey coordinates is %.0f meters", flagged$dist_m),
            roles, ".v"
          )
        }
      }
    }, error = function(e) message("M8: ", e$message))
  }

  # ---- M9 Straightlining -------------------------------------------------------
  if (isTRUE(modules$M9$on)) {
    tryCatch({
      ordinal_vars <- modules$M9$ordinal_vars %||% character()
      ordinal_vars <- ordinal_vars[!is.na(ordinal_vars) & ordinal_vars %in% names(ds)]
      enum_thr <- modules$M9$enum_threshold_pct %||% 0.8
      survey_thr <- modules$M9$survey_threshold_pct %||% 0.8
      min_n_per_enum <- 10L

      if (length(ordinal_vars) && !is.na(roles$enum) && roles$enum %in% names(ds)) {
        enum_vec <- as.character(ds[[roles$enum]])
        for (vc in ordinal_vars) {
          v <- as.character(ds[[vc]])
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
          keep <- rep(FALSE, length(v))
          for (i in seq_len(nrow(tab))) {
            keep <- keep | (ok & enum_vec == tab$enum[i] & v == tab$top_val[i])
          }
          if (!any(keep)) next
          tmp <- ds[keep, , drop = FALSE]
          tmp$.v <- v[keep]
          findings_list[[paste0("m9_enum_", vc)]] <- mk_findings(
            tmp, sprintf("straightlining_enum_%s", vc), "M9", "straightlining_enum",
            sprintf("Enumerator gave the same answer on %s in %.0f%%+ of their surveys", vc, enum_thr * 100),
            roles, ".v"
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
          tmp$.v <- round(share[flag], 2)
          findings_list$m9_survey <- mk_findings(
            tmp, "straightlining_survey", "M9", "straightlining_survey",
            sprintf("%.0f%%+ of this submission's ordinal answers are identical", survey_thr * 100),
            roles, ".v"
          )
        }
      }
    }, error = function(e) message("M9: ", e$message))
  }

  # ---- M10 Summary Statistics (descriptive only, no findings rows) -----------
  if (isTRUE(modules$M10$on)) {
    tryCatch({
      vars <- modules$M10$vars %||% character()
      vars <- vars[!is.na(vars) & vars %in% names(ds)]
      rows <- lapply(vars, function(vc) {
        v <- safe_num(ds[[vc]]); ok <- is.finite(v)
        tibble(Variable = vc, Mean = round(mean(v[ok]), 3), SD = round(stats::sd(v[ok]), 3),
              Min = round(suppressWarnings(min(v[ok])), 3), Max = round(suppressWarnings(max(v[ok])), 3),
              Obs = sum(ok))
      })
      stats_list$M10 <- if (length(rows)) bind_rows(rows) else tibble()
    }, error = function(e) message("M10: ", e$message))
  }

  # ---- M11 Survey-specific + custom checks (was M8) ---------------------------
  if (isTRUE(modules$M11$on) || length(modules$M11$custom %||% character()) > 0) {
    enabled <- modules$M11$enabled %||% character()
    tryCatch({
      if ("food_receipt" %in% enabled && !is.na(roles$food) && !is.na(roles$meal) &&
          all(c(roles$food, roles$meal) %in% names(ds))) {
        tmp <- ds %>%
          mutate(.food = safe_num(.data[[roles$food]]), .meal = safe_num(.data[[roles$meal]])) %>%
          filter(!is.na(.meal), !is.na(.food), .meal == 1, .food == 0)
        findings_list$m11f <- mk_findings(tmp, "food_receipt", "M11", "food_receipt",
                                          "Student did not receive food, but was supposed to receive food", roles)
      }
      if ("cognitive" %in% enabled) {
        cog_cols <- unique(c(roles$ravens,
                             grep("ravens_cpm_correct|stroop|cognitive", names(ds), value = TRUE)))
        cog_cols <- cog_cols[!is.na(cog_cols) & cog_cols %in% names(ds)]
        for (rc in head(cog_cols, 6)) {
          v <- safe_num(ds[[rc]])
          ok <- is.finite(v)
          if (sum(ok) < 30) next
          mu <- mean(v[ok]); sdv <- stats::sd(v[ok])
          q <- stats::quantile(v[ok], c(0.01, 0.99), names = FALSE)
          flag <- ok & (v <= q[1] | v >= q[2] |
                          (is.finite(sdv) & sdv > 0 & abs(v - mu) > 1.5 * sdv))
          if (!any(flag)) next
          tmp <- ds[flag, , drop = FALSE]
          tmp$.v <- v[flag]
          findings_list[[paste0("m11c_", rc)]] <- mk_findings(
            utils::head(tmp, 200), "cognitive_outlier", "M11", "cognitive_outlier",
            "Cognitive / test score outlier (beyond ~1.5 SD or tails)", roles, ".v"
          )
          break
        }
      }
      if ("enrolment" %in% enabled) {
        encol <- grep("enroll|enrolled", names(ds), ignore.case = TRUE, value = TRUE)[1]
        if (!is.na(encol)) {
          tmp <- ds %>% filter(as.character(.data[[encol]]) %in% c("0", "No", "no", "2"))
          if (exists("filter_expected_skips", mode = "function") && !is.null(form_map)) {
            tmp <- filter_expected_skips(tmp, ds, encol, form_map)
          }
          findings_list$m11e <- mk_findings(tmp, "enrolment", "M11", "enrolment",
                                            "Child not enrolled / enrolment issue", roles)
        }
      }
    }, error = function(e) message("M11: ", e$message))

    custom <- modules$M11$custom %||% character()
    custom <- unique(c(custom, setdiff(enabled, c("food_receipt", "cognitive", "enrolment"))))
    if (!is.null(project_root) && length(custom)) {
      for (cname in custom) {
        if (!nzchar(cname) || cname %in% c("food_receipt", "cognitive", "enrolment")) next
        cfile <- hfc_path(project_root, "checks", paste0(cname, ".R"))
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
            if (!"check_module" %in% names(out)) out$check_module <- "M11"
            findings_list[[paste0("custom_", cname)]] <- out
          }
        }, error = function(e) message("Custom ", cname, ": ", e$message))
      }
    }
  }

  # ---- M12 Media files (was M9, delegated to media.R) --------------------------
  if (isTRUE(modules$M12$on) && exists("run_m12_media_checks", mode = "function")) {
    tryCatch({
      findings_list$m12 <- run_m12_media_checks(ds, roles, modules)
    }, error = function(e) message("M12: ", e$message))
  }

  # ---- M13 Consent / assent / audio flags (was M4) -----------------------------
  if (isTRUE(modules$M13$on)) {
    tryCatch({
      flag_miss <- function(col, check_id, category, issue) {
        if (is.na(col) || !col %in% names(ds)) return(NULL)
        miss <- ds %>% filter(is.na(.data[[col]]) |
                                as.character(.data[[col]]) %in% c("", "0", "No", "no"))
        if (exists("filter_expected_skips", mode = "function") && !is.null(form_map)) {
          miss <- filter_expected_skips(miss, ds, col, form_map)
        }
        mk_findings(miss, check_id, "M13", category, issue, roles)
      }
      if (!is.na(roles$assent)) {
        findings_list$m13a <- flag_miss(roles$assent, "missing_assent", "assent",
                                        "Missing or negative assent flag")
      }
      if (!is.na(roles$consent)) {
        findings_list$m13c <- flag_miss(roles$consent, "missing_consent", "consent",
                                        "Consent flag missing or negative")
      }
      audio_flag <- modules$M13$audio %||% roles$audio_flag %||% roles$audio
      media_files <- unique(c(roles$audio_file_cols %||% character(),
                              roles$image_file_cols %||% character()))
      if (!is.na(audio_flag) && audio_flag %in% names(ds) && !audio_flag %in% media_files) {
        findings_list$m13aud <- flag_miss(audio_flag, "missing_audio_flag", "audio",
                                          "Audio consent flag missing or negative")
      }
    }, error = function(e) message("M13: ", e$message))
  }

  findings <- bind_rows(findings_list)
  if (nrow(findings) == 0) findings <- empty_findings()
  list(findings = findings, stats = stats_list)
}
