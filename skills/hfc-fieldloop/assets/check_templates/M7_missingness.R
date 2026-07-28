# M7 — Missingness
# By up to 10 confirmed important variables, and by enumerator. Sentinel
# "missing" codes (e.g. 99, -9999) are confirmed AFTER the variable list is
# confirmed, and the confirm question references those specific variable
# names — a genuine sequential-question dependency, not a static card set.
# Full implementation: scripts/lib/run_checks.R M7 block.

check_m7_missingness <- function(ds, roles, vars = character(), sentinel_codes = character()) {
  vars <- vars[!is.na(vars) & vars %in% names(ds)]
  if (!length(vars)) return(list(by_variable = tibble::tibble(), by_enumerator = tibble::tibble(),
                                 findings = empty_findings()))
  # sentinel_codes: either one shared character vector for every var, or a
  # named list (var -> codes) when the user confirmed per-variable codes.
  # See scripts/lib/run_checks.R M7 for the missingness-% stats and the
  # "enumerator far above the survey-wide average" finding.
  list(by_variable = tibble::tibble(), by_enumerator = tibble::tibble(), findings = empty_findings())
}
