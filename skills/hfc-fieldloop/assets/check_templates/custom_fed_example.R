# Example custom check: hfc/checks/fed.R
# Convention: export run_<name>(ds, roles) returning a findings tibble
# (same columns as empty_findings() / mk_findings()).
#
# Register in hfc/config/modules.yaml:
#   M11:
#     on: true
#     enabled: [food_receipt]
#     custom: [fed]
# Also write a <=3-sentence plain-English description to
# hfc/config/module_notes.yaml (custom.fed.label / .description) so the HTML
# report can show it under the M11 section — see references/check_modules.md.

run_fed <- function(ds, roles) {
  # Example: students in group A who were not fed
  # Adapt column names to the survey after confirming with the user.
  group_col <- grep("group|arm|treatment", names(ds), ignore.case = TRUE, value = TRUE)[1]
  fed_col <- grep("fed|food_received|receive_food|meal", names(ds), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(group_col) || is.na(fed_col)) return(empty_findings())

  tmp <- ds[
    grepl("A|^1$", as.character(ds[[group_col]]), ignore.case = TRUE) &
      (is.na(ds[[fed_col]]) | as.character(ds[[fed_col]]) %in% c("0", "No", "no", "")),
    ,
    drop = FALSE
  ]
  if (!nrow(tmp)) return(empty_findings())
  mk_findings(tmp, "fed", "M11", "fed", "Group A student not fed", roles, fed_col)
}
