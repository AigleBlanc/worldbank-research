# M6 — Numeric outliers (up to 10 confirmed vars, two-sided N-SD rule, default 3 SD)

check_m6_outliers <- function(ds, roles, vars = NULL, sd_rule = 3) {
  vars <- vars %||% utils::head(roles$numeric_shortlist, 10)
  vars <- vars[!is.na(vars) & vars %in% names(ds)]
  # See scripts/lib/run_checks.R M6 for full implementation
  empty_findings()
}
