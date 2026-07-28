# M9 — Straightlining
# Two definitions, both confirmed thresholds default 80%:
#  - By enumerator: for a given ordinal/categorical question, one enumerator
#    gave the identical single answer in >= enum_threshold_pct of their own
#    surveys (per-question, not an overall response-pattern comparison).
#  - By survey: within one submission, >= survey_threshold_pct of the
#    confirmed ordinal variables (small integer cardinality, e.g. 1=x,2=y,...)
#    share one identical value.
# Ordinal-variable detection: detect_ordinal_vars() in
# scripts/lib/profile_roles.R (numeric, <=7 distinct integers, non-binary).
# Full implementation: scripts/lib/run_checks.R M9 block.

check_m9_straightlining <- function(ds, roles, ordinal_vars = character(),
                                    enum_threshold_pct = 0.8, survey_threshold_pct = 0.8) {
  ordinal_vars <- ordinal_vars[!is.na(ordinal_vars) & ordinal_vars %in% names(ds)]
  if (!length(ordinal_vars)) return(empty_findings())
  # See scripts/lib/run_checks.R M9 for the per-enumerator mode-share check
  # and the per-submission ordinal-answer-share check.
  empty_findings()
}
