# Example custom check: hfc/checks/example_check.R
# Convention: export run_<name>(ds, roles) returning a findings tibble
# (same columns as empty_findings() / mk_findings()).
#
# Register in hfc/config/modules.yaml:
#   M11:
#     on: true
#     custom: [example_check]
# Also write a <=3-sentence plain-English description to
# hfc/config/module_notes.yaml (custom.example_check.label / .description) so
# the HTML report can show it under the M11 section — see
# references/check_modules.md.

run_example_check <- function(ds, roles) {
  # Example: respondents in study arm A missing an expected benefit/
  # treatment-received flag. This is illustrative only — adapt the column
  # names and logic to whatever this specific survey actually needs after
  # confirming with the user.
  group_col <- grep("group|arm|treatment", names(ds), ignore.case = TRUE, value = TRUE)[1]
  received_col <- grep("received|completed|benefit", names(ds), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(group_col) || is.na(received_col)) return(empty_findings())

  tmp <- ds[
    grepl("A|^1$", as.character(ds[[group_col]]), ignore.case = TRUE) &
      (is.na(ds[[received_col]]) | as.character(ds[[received_col]]) %in% c("0", "No", "no", "")),
    ,
    drop = FALSE
  ]
  if (!nrow(tmp)) return(empty_findings())
  mk_findings(tmp, "example_check", "M11", "example_check",
              "Group A respondent missing expected benefit/treatment-received flag", roles, received_col)
}
