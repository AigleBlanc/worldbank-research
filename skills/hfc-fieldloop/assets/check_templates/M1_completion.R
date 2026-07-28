# M1 — Completion
# Descriptive: overall completion (count + %), and by confirmed group(s),
# by enumerator, by date. No charts by default (avoid a messy report) — plain
# counts/percentages. Also an optional flag: sites with completed-submission
# counts far below the survey median (reuses the old M6 unit-completion idea).
# Full implementation (stats + optional finding): scripts/lib/run_checks.R M1
# block. This template shows the shape only.

check_m1_completion <- function(ds, roles, completion_var = NA_character_) {
  complete_flag <- if (!is.na(completion_var) && completion_var %in% names(ds)) {
    is_complete_value(ds[[completion_var]])
  } else {
    # Derive: rows with <=10% missing across substantive columns count as complete.
    row_missing_ratio(ds, setdiff(names(ds), c(".hfc_row", ".hfc_id_display"))) <= 0.1
  }
  list(
    overall = completion_summary(complete_flag),
    # by_group / by_enumerator / by_date: see scripts/lib/run_checks.R M1
    findings = empty_findings()
  )
}
