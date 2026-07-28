# M2 — Duplicates
# Adapted from prior hfc-app checks/duplicates.R; FieldLoop findings schema.
# roles$id may be a single column name or a character vector (composite key,
# e.g. household_id + member_id) — group_by(across(all_of(.))) handles both.

check_m2_duplicates <- function(ds, roles) {
  idc <- roles$id
  idc <- idc[!is.na(idc) & nzchar(as.character(idc))]
  idc <- idc[idc %in% names(ds)]
  if (!length(idc)) return(empty_findings())
  dups <- ds %>%
    dplyr::filter(dplyr::if_all(dplyr::all_of(idc), ~ !is.na(.) & as.character(.) != "")) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(idc))) %>%
    dplyr::filter(dplyr::n() > 1) %>%
    dplyr::ungroup()
  mk_findings(dups, "duplicates_id", "M2", "duplicates", "Duplicate submission ID", roles)
}
