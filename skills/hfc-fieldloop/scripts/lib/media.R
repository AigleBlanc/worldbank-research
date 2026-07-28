# SurveyCTO media helpers + M12 checks (audio / pictures).
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

media_basename <- function(path) {
  if (is.null(path) || length(path) == 0) return(NA_character_)
  x <- gsub("\\\\", "/", as.character(path))
  basename(x)
}

looks_like_audio_file <- function(x) {
  grepl(paste0("\\.(", AUDIO_EXTS, ")$"), as.character(x), ignore.case = TRUE)
}

looks_like_image_file <- function(x) {
  grepl(paste0("\\.(", IMAGE_EXTS, ")$"), as.character(x), ignore.case = TRUE)
}

is_empty_media_cell <- function(x) {
  is.na(x) | !nzchar(trimws(as.character(x)))
}

flag_is_positive <- function(x) {
  s <- tolower(trimws(as.character(x)))
  s %in% c("1", "yes", "y", "true", "checked")
}

#' Find SurveyCTO media folder under project / beside data file
discover_media_folder <- function(project_root, data_path = NULL) {
  project_root <- normalizePath(project_root, mustWork = FALSE)
  cands <- c(
    file.path(project_root, "data", "raw", "media"),
    file.path(project_root, "data", "media"),
    file.path(project_root, "media"),
    file.path(project_root, "data", "raw", "media_attachments"),
    file.path(project_root, "attachments")
  )
  if (!is.null(data_path) && !is.na(data_path) && nzchar(data_path)) {
    cands <- c(file.path(dirname(normalizePath(data_path, mustWork = FALSE)), "media"), cands)
  }
  cands <- unique(cands)
  existing <- cands[dir.exists(cands)]
  if (!length(existing)) {
    return(list(path = NA_character_, found = FALSE, candidates = cands))
  }
  # Prefer folder that actually contains media-like files
  score <- vapply(existing, function(d) {
    n <- length(list.files(d, pattern = paste0("\\.(", AUDIO_EXTS, "|", IMAGE_EXTS, ")$"),
                           ignore.case = TRUE, recursive = FALSE))
    n
  }, integer(1))
  best <- existing[order(score, decreasing = TRUE)][[1]]
  list(path = normalizePath(best), found = TRUE, candidates = cands)
}

resolve_media_on_disk <- function(filename, media_folder) {
  if (is.null(media_folder) || is.na(media_folder) || !nzchar(media_folder)) return(NA_character_)
  if (is_empty_media_cell(filename)) return(NA_character_)
  bn <- media_basename(filename)
  p <- file.path(media_folder, bn)
  if (file.exists(p)) return(normalizePath(p))
  # also try full relative path under media_folder parent
  alt <- file.path(media_folder, gsub("\\\\", "/", as.character(filename)))
  if (file.exists(alt)) return(normalizePath(alt))
  NA_character_
}

#' Audio duration in seconds; NA if unavailable
audio_duration_sec <- function(path) {
  if (is.null(path) || is.na(path) || !file.exists(path)) return(NA_real_)
  if (requireNamespace("av", quietly = TRUE)) {
    info <- tryCatch(av::av_media_info(path), error = function(e) NULL)
    if (!is.null(info) && !is.null(info$duration) && is.finite(info$duration)) {
      return(as.numeric(info$duration))
    }
  }
  ff <- Sys.which("ffprobe")
  if (nzchar(ff)) {
    out <- tryCatch(
      system2(ff, c("-v", "error", "-show_entries", "format=duration",
                    "-of", "default=noprint_wrappers=1:nokey=1", path),
              stdout = TRUE, stderr = FALSE),
      error = function(e) character()
    )
    if (length(out) && nzchar(out[[1]])) {
      d <- suppressWarnings(as.numeric(out[[1]]))
      if (is.finite(d)) return(d)
    }
  }
  NA_real_
}

media_duration_available <- function() {
  requireNamespace("av", quietly = TRUE) || nzchar(Sys.which("ffprobe"))
}

#' Run M12 media file checks. Returns findings tibble (may be empty).
run_m12_media_checks <- function(ds, roles, modules) {
  suppressPackageStartupMessages({ library(dplyr); library(tibble) })
  if (!isTRUE(modules$M12$on)) return(empty_findings())

  audio_cols <- modules$M12$audio_cols %||% roles$audio_file_cols %||% character()
  image_cols <- modules$M12$image_cols %||% roles$image_file_cols %||% character()
  audio_cols <- intersect(as.character(audio_cols), names(ds))
  image_cols <- intersect(as.character(image_cols), names(ds))
  all_cols <- unique(c(audio_cols, image_cols))
  if (!length(all_cols)) return(empty_findings())

  media_folder <- modules$M12$media_folder %||% roles$media_folder %||% NA_character_
  if (is.null(media_folder) || !length(media_folder)) media_folder <- NA_character_
  media_folder <- media_folder[[1]]
  disk_ok <- !is.na(media_folder) && nzchar(media_folder) && dir.exists(media_folder)

  min_audio <- as.integer(modules$M12$min_audio_bytes %||% 1024L)
  min_image <- as.integer(modules$M12$min_image_bytes %||% 2048L)
  min_dur <- as.numeric(modules$M12$min_duration_sec %||% 5)
  max_dur <- as.numeric(modules$M12$max_duration_sec %||% 3600)

  out <- list()
  id_display <- if (".hfc_id_display" %in% names(ds)) {
    ds$.hfc_id_display
  } else {
    composite_id_string(ds, roles$id, roles$id_sep %||% " / ")
  }

  # Informational: on-disk checks skipped
  if (!disk_ok) {
    out$skip <- tibble(
      finding_id = "media_no_folder-000001",
      check_id = "media_no_folder",
      check_module = "M12",
      category = "media_folder_missing",
      issue = "Media folder not found — on-disk file checks skipped; empty-cell and extension checks still run",
      submission_id = "",
      school_id = "",
      enumerator = "",
      start_date = "",
      end_date = "",
      key = "",
      value = ""
    )
  }

  for (col in all_cols) {
    is_audio <- col %in% audio_cols
    kind <- if (is_audio) "audio" else "image"
    vals <- as.character(ds[[col]])
    empty <- is_empty_media_cell(vals)

    # 1. Empty media cell
    if (any(empty)) {
      tmp <- ds[empty, , drop = FALSE]
      out[[paste0("empty_", col)]] <- mk_findings(
        tmp, sprintf("media_empty_%s", col), "M12", "media_missing_cell",
        sprintf("Empty %s filename in column %s", kind, col), roles
      )
    }

    nonempty_idx <- which(!empty)
    if (!length(nonempty_idx)) next

    # 4. Bad extension vs column type
    bad_ext <- if (is_audio) {
      !looks_like_audio_file(vals[nonempty_idx])
    } else {
      !looks_like_image_file(vals[nonempty_idx])
    }
    if (any(bad_ext)) {
      tmp <- ds[nonempty_idx[bad_ext], , drop = FALSE]
      tmp$.v <- vals[nonempty_idx[bad_ext]]
      out[[paste0("ext_", col)]] <- mk_findings(
        tmp, sprintf("media_bad_ext_%s", col), "M12", "media_bad_ext",
        sprintf("Unexpected extension for %s column %s", kind, col), roles, ".v"
      )
    }

    if (!disk_ok) next

    # 2–3. Missing / tiny on disk; 6. duration
    absent_i <- integer(); tiny_i <- integer(); dur_i <- integer()
    absent_v <- character(); tiny_v <- character(); dur_v <- character()
    thr <- if (is_audio) min_audio else min_image
    for (i in nonempty_idx) {
      fn <- vals[[i]]
      path <- resolve_media_on_disk(fn, media_folder)
      if (is.na(path)) {
        absent_i <- c(absent_i, i)
        absent_v <- c(absent_v, media_basename(fn))
        next
      }
      sz <- file.info(path)$size %||% 0
      if (!is.finite(sz) || sz < thr) {
        tiny_i <- c(tiny_i, i)
        tiny_v <- c(tiny_v, as.character(sz))
      }
      if (is_audio && media_duration_available()) {
        dur <- audio_duration_sec(path)
        if (is.finite(dur) && (dur < min_dur || dur > max_dur)) {
          dur_i <- c(dur_i, i)
          dur_v <- c(dur_v, as.character(round(dur, 1)))
        }
      }
    }
    if (length(absent_i)) {
      tmp <- ds[absent_i, , drop = FALSE]
      tmp$.v <- absent_v
      out[[paste0("abs_", col)]] <- mk_findings(
        tmp, sprintf("media_absent_%s", col), "M12", "media_file_absent",
        sprintf("%s file not found on disk (column %s)", kind, col), roles, ".v"
      )
    }
    if (length(tiny_i)) {
      tmp <- ds[tiny_i, , drop = FALSE]
      tmp$.v <- tiny_v
      out[[paste0("tiny_", col)]] <- mk_findings(
        tmp, sprintf("media_tiny_%s", col), "M12", "media_tiny",
        sprintf("%s file too small (column %s)", kind, col), roles, ".v"
      )
    }
    if (length(dur_i)) {
      tmp <- ds[dur_i, , drop = FALSE]
      tmp$.v <- dur_v
      out[[paste0("dur_", col)]] <- mk_findings(
        tmp, sprintf("media_duration_%s", col), "M12", "media_duration",
        sprintf("Audio duration outside [%s, %s]s (column %s)", min_dur, max_dur, col),
        roles, ".v"
      )
    }
  }

  # 5. Duplicate media (same basename across different IDs)
  if (any(nzchar(id_display))) {
    for (col in all_cols) {
      vals <- as.character(ds[[col]])
      bns <- media_basename(vals)
      ok <- !is_empty_media_cell(vals) & !is.na(bns) & nzchar(bns)
      if (sum(ok) < 2) next
      tab <- table(bns[ok])
      dups <- names(tab)[tab > 1]
      if (!length(dups)) next
      # Flag rows where same basename maps to >1 distinct id
      for (bn in dups) {
        idx <- which(ok & bns == bn)
        ids <- unique(id_display[idx])
        ids <- ids[!is.na(ids) & nzchar(ids)]
        if (length(ids) < 2) next
        tmp <- ds[idx, , drop = FALSE]
        tmp$.v <- bn
        out[[paste0("dup_", col, "_", bn)]] <- mk_findings(
          tmp, sprintf("media_dup_%s", col), "M12", "media_dup",
          sprintf("Same media file used by multiple IDs: %s", bn), roles, ".v"
        )
      }
    }

    # Hash-based dups when files on disk (limit to avoid slow runs)
    if (disk_ok && length(all_cols)) {
      hash_rows <- list()
      n_hashed <- 0L
      for (col in all_cols) {
        vals <- as.character(ds[[col]])
        for (i in which(!is_empty_media_cell(vals))) {
          if (n_hashed >= 500L) break
          path <- resolve_media_on_disk(vals[[i]], media_folder)
          if (is.na(path)) next
          h <- tryCatch(as.character(tools::md5sum(path)), error = function(e) NA_character_)
          if (is.na(h)) next
          hash_rows[[length(hash_rows) + 1L]] <- data.frame(
            i = i, col = col, id = id_display[[i]], hash = h,
            bn = media_basename(vals[[i]]), stringsAsFactors = FALSE
          )
          n_hashed <- n_hashed + 1L
        }
      }
      if (length(hash_rows)) {
        ht <- dplyr::bind_rows(hash_rows)
        by_h <- split(ht, ht$hash)
        for (chunk in by_h) {
          if (length(unique(chunk$id)) < 2) next
          tmp <- ds[chunk$i, , drop = FALSE]
          tmp$.v <- chunk$hash[[1]]
          out[[paste0("hash_", chunk$hash[[1]])]] <- mk_findings(
            tmp, "media_dup_hash", "M12", "media_dup",
            sprintf("Identical media content (hash) across IDs: %s", paste(unique(chunk$bn), collapse = ", ")),
            roles, ".v"
          )
        }
      }
    }
  }

  # 7. Flag ↔ file inconsistency
  audio_flag <- modules$M12$audio_flag %||% roles$audio_flag %||% NA_character_
  pair_file <- modules$M12$flag_file_col %||% roles$audio_file_cols[1] %||% NA_character_
  if (!is.na(audio_flag) && audio_flag %in% names(ds) &&
      !is.na(pair_file) && pair_file %in% names(ds)) {
    pos <- flag_is_positive(ds[[audio_flag]])
    empty_f <- is_empty_media_cell(ds[[pair_file]])
    bad <- pos & empty_f
    if (any(bad)) {
      out$flag_mismatch <- mk_findings(
        ds[bad, , drop = FALSE], "media_flag_mismatch", "M12", "media_flag_mismatch",
        sprintf("Flag %s positive but media column %s empty", audio_flag, pair_file), roles
      )
    }
  }

  # Cap per-check explosion: bind and dedupe by finding_id prefix + submission
  findings <- dplyr::bind_rows(out)
  if (is.null(findings) || nrow(findings) == 0) return(empty_findings())
  # Re-number finding_ids that share check_id for stability after bind
  findings <- findings %>%
    group_by(check_id) %>%
    mutate(finding_id = sprintf("%s-%06d", check_id[[1]], row_number())) %>%
    ungroup()
  findings
}
