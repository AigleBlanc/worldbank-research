# M3 — Form Version
# If a form-version-like column exists (detect_form_version_col() in
# scripts/lib/profile_roles.R), profile it and propose a date-range<->version
# mapping directly from the data. Otherwise, best-effort infer cutover dates
# from when columns start/stop appearing (infer_version_cutovers()) — always
# propose-then-confirm, never trust a guessed mapping silently.
# Full implementation: scripts/lib/run_checks.R M3 block.

check_m3_form_version <- function(ds, roles, version_col = NA_character_, version_map = list()) {
  if (is.na(version_col) || !version_col %in% names(ds)) {
    # No recorded version column: version_map (if any) is a best-guess,
    # confirmed set of date windows — report only, no mismatch finding
    # possible without a real recorded version to compare against.
    return(list(stats = tibble::tibble(), findings = empty_findings()))
  }
  # See scripts/lib/run_checks.R M3 for the date<->version stats table and
  # the optional "recorded version doesn't match expected window" finding.
  list(stats = tibble::tibble(), findings = empty_findings())
}
