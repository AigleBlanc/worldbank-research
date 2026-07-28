# M5 — Irregular Timing (was M2's early-start half)
# Flags interviews conducted at irregular times: weekends and/or outside a
# confirmed hour window (default 7pm-7am). Timezone-aware: resolves each
# row's local time using the country/timezone confirmed at setup (single
# global timezone, or a per-row lookup via a confirmed country column for
# multi-country surveys) — see scripts/lib/geo_timezone.R and
# resolve_row_timezone()/local_daypart() in scripts/lib/run_checks.R.

check_m5_date_issues <- function(ds, roles, evening_hour = 19, morning_hour = 7, flag_weekend = TRUE) {
  st <- roles$start
  if (is.null(st) || is.na(st) || !st %in% names(ds)) return(empty_findings())
  # Full timezone-aware implementation: scripts/lib/run_checks.R M5 block
  # (parse_datetime_col(), resolve_row_timezone(), local_daypart()).
  empty_findings()
}
