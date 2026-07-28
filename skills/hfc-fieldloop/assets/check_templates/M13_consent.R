# M13 — Consent / assent / audio FLAGS only (filenames -> M12)

check_m13_consent <- function(ds, roles) {
  out <- list()
  for (pair in list(
    list(col = roles$assent, id = "missing_assent", cat = "assent", msg = "Missing or negative assent flag"),
    list(col = roles$consent, id = "missing_consent", cat = "consent", msg = "Missing consent flag"),
    list(col = roles$audio_flag %||% roles$audio, id = "missing_audio_flag", cat = "audio", msg = "Missing audio flag")
  )) {
    c <- pair$col
    if (is.null(c) || is.na(c) || !c %in% names(ds)) next
    # Do not treat filename columns as flags — those are M12's job.
    media_files <- unique(c(roles$audio_file_cols %||% character(),
                            roles$image_file_cols %||% character()))
    if (c %in% media_files) next
    miss <- ds %>% dplyr::filter(is.na(.data[[c]]) |
                                   as.character(.data[[c]]) %in% c("", "0", "No", "no"))
    out[[pair$cat]] <- mk_findings(miss, pair$id, "M13", pair$cat, pair$msg, roles)
  }
  dplyr::bind_rows(out)
}
