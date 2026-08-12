# SurveyCTO media helpers + M11 checks (audio / pictures).
# Filename columns hold paths like media\uuid.m4a; binaries live under media_folder.

AUDIO_EXTS <- "m4a|mp3|wav|ogg|aac|amr"
IMAGE_EXTS <- "jpg|jpeg|png|bmp|tif|tiff|webp"

#' Detect character columns whose sample values look like media filenames
detect_media_vars <- function(df) {
  if (is.null(df) || !ncol(df)) return(list(audio = character(), images = character()))
  char_cols <- names(df)[vapply(df, function(x) {
    is.character(x) || is.factor(x)
  }, logical(1))]
  if (!length(char_cols)) return(list(audio = character(), images = character()))

  audio_re <- paste0("\\.(", AUDIO_EXTS, ")$")
  image_re <- paste0("\\.(", IMAGE_EXTS, ")$")

  audio <- character()
  images <- character()
  for (v in char_cols) {
    x <- as.character(df[[v]])
    x <- x[!is.na(x) & nzchar(trimws(x))]
    s <- utils::head(x, 30)
    if (!length(s)) next
    n_aud <- sum(grepl(audio_re, s, ignore.case = TRUE))
    n_img <- sum(grepl(image_re, s, ignore.case = TRUE))
    if (n_aud == 0 && n_img == 0) next
    # Exclusive: majority type wins (ties → audio if any audio, else image)
    if (n_aud > n_img) {
      audio <- c(audio, v)
    } else if (n_img > n_aud) {
      images <- c(images, v)
    } else if (n_aud > 0) {
      audio <- c(audio, v)
    } else {
      images <- c(images, v)
    }
  }
  list(audio = unname(audio), images = unname(images))
}

is_empty_media_cell <- function(x) {
  is.na(x) | !nzchar(trimws(as.character(x)))
}

#' Run M11 media checks. Redesigned around a single question per
#' media-indicating column: is this column COMPLETELY empty across every
#' surveyed row? That's a strong signal of a form/coding problem — the
#' field isn't showing up in the enumerator's app, or the question was
#' misconfigured — not a per-row file-hygiene issue. No on-disk file access
#' at all (no missing/tiny/duration/duplicate/extension checks anymore);
#' `ds` is expected to already be the completion-filtered surveyed subset
#' (run_check_modules()/the standalone check templates both filter before
#' calling this). `roles$qualitative_text_cols` (agent-identified, not
#' code-detected — see profile_roles.R) covers open-ended text fields
#' expected to capture qualitative data, alongside the usual audio/image
#' filename columns.
run_m11_media_checks <- function(ds, roles, modules) {
  suppressPackageStartupMessages({ library(dplyr); library(tibble) })
  if (!isTRUE(modules$M11$on)) return(empty_findings())

  audio_cols <- modules$M11$audio_cols %||% roles$audio_file_cols %||% character()
  image_cols <- modules$M11$image_cols %||% roles$image_file_cols %||% character()
  other_cols <- modules$M11$other_cols %||% roles$qualitative_text_cols %||% character()
  audio_cols <- intersect(as.character(audio_cols), names(ds))
  image_cols <- intersect(as.character(image_cols), names(ds))
  other_cols <- intersect(as.character(other_cols), names(ds))
  all_cols <- unique(c(audio_cols, image_cols, other_cols))
  if (!length(all_cols)) return(empty_findings())

  out <- list()
  for (col in all_cols) {
    kind <- if (col %in% audio_cols) "audio" else if (col %in% image_cols) "image" else "qualitative"
    vals <- as.character(ds[[col]])
    if (nrow(ds) > 0 && all(is_empty_media_cell(vals))) {
      out[[col]] <- tibble(
        finding_id = paste0("m11:column_empty:", col),
        check_id = sprintf("media_column_empty_%s", col),
        check_module = "M11",
        category = "media_column_empty",
        issue = sprintf(
          "The %s column '%s' is empty across all %d surveyed rows. Likely a form/coding problem (the field isn't showing up in the app, or the question is misconfigured), not a data-entry gap on any one row",
          kind, var_label(col, roles), nrow(ds)
        ),
        submission_id = "", group_id = "", enumerator = "", start_date = "", end_date = "",
        key = "", value = "", variable = col, entity_name = "", group_name = "", enumerator_name = "",
        sort_value = NA_real_
      )
    }
  }

  findings <- dplyr::bind_rows(out)
  if (is.null(findings) || nrow(findings) == 0) return(empty_findings())
  findings
}
