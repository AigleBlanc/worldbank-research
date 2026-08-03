# M11 — Survey-specific: fully custom, authored per project (default none).
# There are no built-in M11 checks — every M11 finding comes from a custom
# check the AI writes for this survey's specific content.
# Custom checks (from the Additional-checks gate) register here as
# hfc/checks/<name>.R with an exported run_<name>(ds, roles) — see
# custom_check_example.R and references/check_modules.md.

check_m11_survey_specific <- function(ds, roles, custom = character()) {
  if (!length(custom)) return(empty_findings())
  # See scripts/lib/run_checks.R M11 for full implementation
  empty_findings()
}

# --- Salvaged example: enumerator daily-volume anomaly (was a default module,
# old M5, before the redesign folded default enumerator reporting into M1
# Completion's "completion by enumerator" table). Not enabled by default —
# copy/adapt into a real hfc/checks/<name>.R and register under
# modules.yaml's M11.custom if a survey specifically wants SD-based
# submission-count anomaly detection in addition to M1's descriptive table.
#
# run_enumerator_volume <- function(ds, roles, sd_rule = 2) {
#   if (is.na(roles$enum) || !roles$enum %in% names(ds)) return(empty_findings())
#   if (is.na(roles$start) || !roles$start %in% names(ds)) return(empty_findings())
#   tmp <- ds %>%
#     dplyr::mutate(.day = as.Date(.data[[roles$start]]), .enum = .data[[roles$enum]]) %>%
#     dplyr::filter(!is.na(.day), !is.na(.enum)) %>%
#     dplyr::count(.enum, .day, name = "n")
#   mu <- mean(tmp$n); sdv <- sd(tmp$n)
#   if (!is.finite(sdv) || sdv <= 0) return(empty_findings())
#   hot <- tmp %>% dplyr::filter(n > mu + sd_rule * sdv)
#   if (!nrow(hot)) return(empty_findings())
#   tibble::tibble(
#     finding_id = sprintf("enumerator_volume-%06d", seq_len(nrow(hot))),
#     check_id = "enumerator_volume", check_module = "M11", category = "enumerator_volume",
#     issue = sprintf("Enumerator daily volume outlier (n=%s)", hot$n),
#     submission_id = "", group_id = "", enumerator = as.character(hot$.enum),
#     start_date = as.character(hot$.day), end_date = "", key = "",
#     value = as.character(hot$n)
#   )
# }
