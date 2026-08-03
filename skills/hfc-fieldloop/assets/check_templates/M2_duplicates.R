# M2 — Duplicates
# Adapted from prior hfc-app checks/duplicates.R; FieldLoop findings schema.
# roles$entity_id may be a single column name or a character vector
# (composite key, e.g. household_id + member_id) — group_by(across(all_of(.)))
# handles both. Entity ID alone may legitimately repeat (e.g. a household
# surveyed across multiple rounds) — modules$M2$extra_keys (confirmed at
# setup via the duplicate-check-key gate, e.g. a round/wave column) gets
# appended so those legitimate repeats aren't flagged as duplicates.

check_m2_duplicates <- function(ds, roles, extra_keys = character()) {
  idc <- roles$entity_id
  idc <- idc[!is.na(idc) & nzchar(as.character(idc))]
  idc <- idc[idc %in% names(ds)]
  extra_keys <- extra_keys[!is.na(extra_keys) & nzchar(as.character(extra_keys)) & extra_keys %in% names(ds)]
  full_key <- c(idc, extra_keys)
  if (!length(full_key)) return(empty_findings())
  dups <- ds %>%
    dplyr::filter(dplyr::if_all(dplyr::all_of(full_key), ~ !is.na(.) & as.character(.) != "")) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(full_key))) %>%
    dplyr::filter(dplyr::n() > 1) %>%
    dplyr::ungroup()
  mk_findings(dups, "duplicates_id", "M2", "duplicates", "Duplicate submission ID", roles)
}
