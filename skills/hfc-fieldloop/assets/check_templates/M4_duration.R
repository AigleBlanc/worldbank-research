# M4 — Survey Duration
# Reports summary stats (overall, by section, by enumerator) AND flags
# individual interviews more than sd_rule SD above/below the mean (both
# directions). Early-start / time-of-day checks live in M5 instead.

check_m4_duration <- function(ds, roles, sd_rule = 3) {
  dc <- roles$duration
  if (is.null(dc) || is.na(dc) || !dc %in% names(ds)) return(empty_findings())
  out <- list()
  dur <- safe_num(ds[[dc]])
  mu <- mean(dur, na.rm = TRUE); sdv <- sd(dur, na.rm = TRUE)
  if (is.finite(mu) && is.finite(sdv) && sdv > 0) {
    tmp <- ds %>% dplyr::mutate(.dur = safe_num(.data[[dc]])) %>%
      dplyr::filter(is.finite(.dur), .dur > mu + sd_rule * sdv)
    out$long <- mk_findings(tmp, "long_duration", "M4", "long_duration",
                            sprintf("Interview duration more than %s SD above the mean", sd_rule),
                            roles, ".dur")
    tmp2 <- ds %>% dplyr::mutate(.dur = safe_num(.data[[dc]])) %>%
      dplyr::filter(is.finite(.dur), .dur > 0, .dur < mu - sd_rule * sdv)
    out$short <- mk_findings(tmp2, "short_duration", "M4", "short_duration",
                             sprintf("Interview duration more than %s SD below the mean", sd_rule),
                             roles, ".dur")
  }
  # Descriptive stats (overall / by section / by enumerator): see
  # scripts/lib/run_checks.R M4 block — stats aren't findings rows, so they
  # aren't produced by this per-check-file pattern.
  dplyr::bind_rows(out)
}
