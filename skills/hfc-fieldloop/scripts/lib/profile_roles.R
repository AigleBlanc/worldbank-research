# Heuristic column role profiling (no LLM required).
# Returns roles list + option cards for module confirmation.

pick_first <- function(nms, patterns) {
    for (p in patterns) {
        hit <- grep(p, nms, ignore.case = TRUE, value = TRUE)
        if (length(hit)) return(hit[[1]])
    }
    NA_character_
}

col_label <- function(x) {
    lab <- tryCatch(attr(x, "label"), error = function(e) NULL)
    if (is.null(lab) || !nzchar(as.character(lab))) return(NA_character_)
    as.character(lab)[[1]]
}

# Shared regex vocabulary for ID-like columns, reused by both the single-column
# and composite-ID shortlist functions so they don't drift apart.
# The following should never be candidates for unique ID
ID_NOISE_PATTERN <- paste0(
    "duration|light|sound|movement|latitude|longitude|^lat$|^lon$|",
    "coord|gps|audio|photo|picture|image|consent_pic|track_|",
    "mean_|sd_|raven|stroop|score|age$|starttime|endtime"
)
ID_NAME_PATTERN <- "studentid|hhid|household|respondent|farmerid|^id$|uuid|submission|key$|instanceid|caseid|interview"
ID_LABEL_PATTERN <- "student|household|respondent|submission|unique|interview|case id|id number"
COMPOSITE_ID_NAME_PATTERN <- "roster|member|line|index|child|hh_member|person|individual"

# Score columns as Entity ID candidates (higher = better) — the analysis-
# unit identifier (person/household/school/...), not necessarily row-unique
# (see roles$dup_key_extra for the separate duplicate-check key).
# Uses name patterns, haven labels, uniqueness ratio, missingness.
# Excludes high-cardinality noise (duration, sensors, GPS, media filenames).
shortlist_entity_ids <- function(ds, n = 3L) {
    nms <- names(ds)
    n_row <- nrow(ds)
    noise <- grepl(ID_NOISE_PATTERN, nms, ignore.case = TRUE)
    id_name_pat <- grepl(ID_NAME_PATTERN, nms, ignore.case = TRUE)
    label_pat <- vapply(nms, function(col) {
        lab <- col_label(ds[[col]])
        if (is.na(lab)) return(FALSE)
        grepl(ID_LABEL_PATTERN, lab, ignore.case = TRUE)
    }, logical(1))

    score_one <- function(col) {
        x <- ds[[col]]
        non_na <- x[!is.na(x) & as.character(x) != ""]
        n_obs <- length(non_na)
        if (n_obs < max(10, 0.5 * n_row)) return(-Inf)
        n_unique <- length(unique(as.character(non_na)))
        uniq <- n_unique / max(1, n_obs)
        miss <- 1 - n_obs / max(1, n_row)
        s <- 0
        if (id_name_pat[match(col, nms)]) s <- s + 5
        if (label_pat[match(col, nms)]) s <- s + 3
        if (uniq >= 0.95) s <- s + 4 else if (uniq >= 0.8) s <- s + 2 else if (uniq >= 0.5) s <- s + 0.5
        s <- s - miss * 3
        if (noise[match(col, nms)]) s <- s - 8
        v <- suppressWarnings(as.numeric(non_na))
        if (sum(is.finite(v)) > 0.9 * n_obs && length(unique(v[is.finite(v)])) > 0.9 * n_obs &&
            !id_name_pat[match(col, nms)]) {
        s <- s - 2
        }
        s
    }

    scores <- vapply(nms, score_one, numeric(1))
    # Prefer non-noise columns; only fall back to noise if shortlist is empty
    non_noise <- nms[!noise & scores > -Inf]
    pool <- if (length(non_noise) >= 1) non_noise else nms[scores > -Inf]
    pool_scores <- scores[match(pool, nms)]
    ord <- order(pool_scores, decreasing = TRUE)
    # Require a minimally positive score when possible
    positive <- pool[ord][pool_scores[ord] > 0]
    cands <- if (length(positive)) positive else pool[ord]
    cands <- unique(cands)[seq_len(min(n, length(unique(cands))))]

    rationale <- vapply(cands, function(col) {
        x <- ds[[col]]
        non_na <- x[!is.na(x) & as.character(x) != ""]
        n_unique <- length(unique(as.character(non_na)))
        lab <- col_label(x)
        lab_bit <- if (!is.na(lab)) sprintf(" label=\"%s\"", substr(lab, 1, 60)) else ""
        sprintf("%s: %s unique / %s rows%s", col, n_unique, n_row, lab_bit)
    }, character(1))

    list(entity_id_options = cands, entity_id_rationale = unname(rationale), entity_id = cands[[1]] %||% NA_character_)
}

# Candidates for a COMPOSITE Entity ID (e.g. household_id + member_id).
# Pools moderate-uniqueness columns plus roster/member-like columns, since
# those typically combine with a household/site id to form a compound key.
# Returns the same shape as shortlist_entity_ids() for card symmetry.
shortlist_composite_entity_ids <- function(ds, n = 4L) {
    nms <- names(ds)
    n_row <- nrow(ds)
    noise <- grepl(ID_NOISE_PATTERN, nms, ignore.case = TRUE)
    id_name_pat <- grepl(ID_NAME_PATTERN, nms, ignore.case = TRUE)
    roster_pat <- grepl(COMPOSITE_ID_NAME_PATTERN, nms, ignore.case = TRUE)

    score_one <- function(col) {
        x <- ds[[col]]
        non_na <- x[!is.na(x) & as.character(x) != ""]
        n_obs <- length(non_na)
        if (n_obs < max(10, 0.3 * n_row)) return(-Inf)
        n_unique <- length(unique(as.character(non_na)))
        uniq <- n_unique / max(1, n_obs)
        s <- 0
        if (id_name_pat[match(col, nms)]) s <- s + 4
        if (roster_pat[match(col, nms)]) s <- s + 5
        # Composite components are typically only *moderately* unique on their
        # own (e.g. member_id repeats 1..N within each household) — reward
        # low-to-moderate cardinality here rather than near-100% uniqueness.
        if (uniq >= 0.02 && uniq <= 0.6) s <- s + 3
        if (noise[match(col, nms)]) s <- s - 8
        s
    }

    scores <- vapply(nms, score_one, numeric(1))
    non_noise <- nms[!noise & scores > -Inf]
    pool <- if (length(non_noise) >= 1) non_noise else nms[scores > -Inf]
    pool_scores <- scores[match(pool, nms)]
    ord <- order(pool_scores, decreasing = TRUE)
    positive <- pool[ord][pool_scores[ord] > 0]
    cands <- if (length(positive)) positive else pool[ord]
    cands <- unique(cands)[seq_len(min(n, length(unique(cands))))]

    rationale <- vapply(cands, function(col) {
        x <- ds[[col]]
        non_na <- x[!is.na(x) & as.character(x) != ""]
        n_unique <- length(unique(as.character(non_na)))
        sprintf("%s: %s distinct values / %s rows", col, n_unique, n_row)
    }, character(1))

    list(composite_entity_id_options = cands, composite_entity_id_rationale = unname(rationale))
}

#' Shortlist candidate country-indicator columns for multi-country surveys.
shortlist_country_columns <- function(ds, n = 3L) {
    nms <- names(ds)
    n_row <- nrow(ds)
    name_hit <- grepl("country|nation|ctry", nms, ignore.case = TRUE)
    label_hit <- vapply(nms, function(col) {
        lab <- col_label(ds[[col]])
        !is.na(lab) && grepl("country|nation", lab, ignore.case = TRUE)
    }, logical(1))
    cand_idx <- which(name_hit | label_hit)
    if (!length(cand_idx)) return(list(country_col_options = character(), country_col_rationale = character()))
    score_one <- function(col) {
        x <- as.character(ds[[col]])
        non_na <- x[!is.na(x) & nzchar(x)]
        if (!length(non_na)) return(-Inf)
        n_unique <- length(unique(non_na))
        s <- 0
        if (n_unique <= 20) s <- s + 3 else s <- s - 5
        s
    }
    cols <- nms[cand_idx]
    scores <- vapply(cols, score_one, numeric(1))
    ord <- order(scores, decreasing = TRUE)
    cands <- cols[ord][seq_len(min(n, length(cols)))]
    rationale <- vapply(cands, function(col) {
        vals <- unique(as.character(ds[[col]]))
        vals <- vals[!is.na(vals) & nzchar(vals)]
        sprintf("%s: %s", col, paste(utils::head(vals, 5), collapse = ", "))
    }, character(1))
    list(country_col_options = cands, country_col_rationale = unname(rationale))
}

#' Candidate completion-indicator columns (M1).
detect_completion_candidates <- function(ds, n = 3L) {
    nms <- names(ds)
    hit <- grep("complete|submitted|finished", nms, ignore.case = TRUE, value = TRUE)
    utils::head(hit, n)
}

#' Candidate grouping columns for completion-by-group (M1): low-cardinality
#' columns matching common study-design terms (treatment arm, admin unit).
detect_grouping_vars <- function(ds, n = 4L) {
    nms <- names(ds)
    hit <- grep("treat|arm|group|state|region|district|stratum", nms, ignore.case = TRUE, value = TRUE)
    hit <- hit[vapply(hit, function(col) {
        x <- as.character(ds[[col]])
        nu <- length(unique(x[!is.na(x) & nzchar(x)]))
        nu >= 2 && nu <= 30
    }, logical(1))]
    utils::head(hit, n)
}

#' Candidate disambiguating columns for the M2 duplicate-check key
#' (round/wave/time-like) — only relevant once Entity ID is confirmed AND
#' found to repeat (e.g. a household surveyed across multiple rounds).
#' Excludes the Entity ID column(s) themselves.
DUP_KEY_NAME_PATTERN <- "round|wave|phase|period|visit|time|endline|baseline|midline|survey_round"
detect_duplicate_key_candidates <- function(ds, entity_id_cols, n = 4L) {
    nms <- setdiff(names(ds), entity_id_cols)
    hit <- grep(DUP_KEY_NAME_PATTERN, nms, ignore.case = TRUE, value = TRUE)
    hit <- hit[vapply(hit, function(col) {
        x <- as.character(ds[[col]])
        nu <- length(unique(x[!is.na(x) & nzchar(x)]))
        nu >= 2 && nu <= 30
    }, logical(1))]
    utils::head(hit, n)
}

#' Candidate form-version column (M3). If found, the agent proposes a
#' date-range<->version mapping directly from the data.
detect_form_version_col <- function(ds) {
    nms <- names(ds)
    pick_first(nms, c("formdef_version", "form_version", "survey_version", "version$"))
}

#' Best-effort version-cutover inference when no version column exists (M3).
#' Bins submissions by month of `start_col` and looks for columns whose
#' non-missing rate jumps sharply between adjacent bins — a signal that the
#' instrument changed around that date. Explicitly fuzzy: propose, don't trust.
infer_version_cutovers <- function(ds, start_col, max_versions = 3L) {
    if (is.na(start_col) || !start_col %in% names(ds)) return(list())
    dt <- suppressWarnings(as.Date(as.character(ds[[start_col]])))
    if (all(is.na(dt))) return(list())
    bins <- format(dt, "%Y-%m")
    bin_levels <- sort(unique(bins[!is.na(bins)]))
    if (length(bin_levels) < 2) return(list())
    rate_by_bin <- sapply(names(ds), function(col) {
        tapply(!is.na(ds[[col]]) & as.character(ds[[col]]) != "", bins, mean)[bin_levels]
    })
    jumps <- character()
    for (i in seq_len(nrow(rate_by_bin) - 1)) {
        delta <- abs(rate_by_bin[i + 1, ] - rate_by_bin[i, ])
        if (any(delta > 0.9, na.rm = TRUE)) jumps <- c(jumps, bin_levels[i + 1])
    }
    jumps <- unique(jumps)
    if (!length(jumps)) return(list())
    # Cluster cutover months that are adjacent/close together
    jumps <- sort(jumps)
    clustered <- jumps[c(TRUE, diff(as.Date(paste0(jumps, "-01"))) > 14)]
    clustered <- utils::head(clustered, max_versions - 1)
    cutoffs <- c(bin_levels[1], clustered, bin_levels[length(bin_levels)])
    versions <- list()
    for (i in seq_len(length(cutoffs) - 1)) {
        versions[[i]] <- list(
            version_label = paste0("v", i),
            date_start = paste0(cutoffs[i], "-01"),
            date_end = paste0(cutoffs[i + 1], "-28")
        )
    }
    versions
}

#' Candidate ordinally-coded categorical variables for straightlining (M9):
#' numeric columns with a small number of distinct integer values (Likert /
#' single-select-style), excluding binary yes/no and structural columns.
detect_ordinal_vars <- function(ds, exclude = character(), n = 20L) {
    nms <- setdiff(names(ds), exclude)
    hit <- nms[vapply(nms, function(col) {
        v <- safe_num(ds[[col]])
        v <- v[is.finite(v)]
        if (length(v) < 10) return(FALSE)
        if (any(v != round(v))) return(FALSE)
        nu <- length(unique(v))
        nu >= 3 && nu <= 7
    }, logical(1))]
    utils::head(hit, n)
}

#' Detect the Unique Submission ID column (SurveyCTO/ODK KEY/uuid/instanceID)
#' — the machine-generated, guaranteed-unique-per-row identifier, distinct
#' from Entity ID (which is chosen by the user and may legitimately repeat).
#' Tries the usual name pattern first, but only accepts it if it's actually
#' 100% unique + non-missing; otherwise scans remaining columns for one that
#' is. Fully automatic — no user confirmation (contrast with the Entity ID /
#' duplicate-check-key gates, which are explicit AskUserQuestion steps).
detect_unique_key_column <- function(ds, exclude = character()) {
    nms <- setdiff(names(ds), exclude)
    is_fully_unique <- function(col) {
        x <- ds[[col]]
        x_chr <- as.character(x)
        if (any(is.na(x) | !nzchar(x_chr))) return(FALSE)
        length(unique(x_chr)) == nrow(ds)
    }
    name_cand <- pick_first(nms, c("^key$", "uuid", "instanceid"))
    if (!is.na(name_cand) && is_fully_unique(name_cand)) return(name_cand)

    candidates <- nms[vapply(nms, is_fully_unique, logical(1))]
    if (!length(candidates)) return(NA_character_)
    pref <- candidates[grepl(ID_NAME_PATTERN, candidates, ignore.case = TRUE)]
    if (length(pref)) return(pref[[1]])
    candidates[[1]]
}

# Profile roles. Optional media_folder from discover_media_folder().
profile_roles <- function(ds, media_folder = NA_character_) {
    nms <- names(ds)

    id_info <- shortlist_entity_ids(ds, n = 3L)
    id_cands <- id_info$entity_id_options
    composite_info <- shortlist_composite_entity_ids(ds, n = 4L)
    country_col_info <- shortlist_country_columns(ds, n = 3L)

    media <- if (exists("detect_media_vars", mode = "function")) {
        detect_media_vars(ds)
    } else {
        list(audio = character(), images = character())
    }
    audio_file_cols <- media$audio %||% character()
    image_file_cols <- media$images %||% character()

    audio_flag_cands <- grep("consent_audio|assent_audio|audio_consent|^audio_flag$",
                            nms, ignore.case = TRUE, value = TRUE)
    audio_flag_cands <- setdiff(audio_flag_cands, c(audio_file_cols, image_file_cols))
    audio_flag <- if (length(audio_flag_cands)) audio_flag_cands[[1]] else NA_character_

    roles <- list(
        entity_id = id_info$entity_id,
        entity_id_options = id_cands,
        entity_id_rationale = id_info$entity_id_rationale,
        entity_id_sep = " / ",
        dup_key_extra = character(),
        composite_entity_id_candidates = composite_info$composite_entity_id_options,
        composite_entity_id_rationale = composite_info$composite_entity_id_rationale,
        country_mode = "single",
        country_col_candidates = country_col_info$country_col_options,
        country_col_rationale = country_col_info$country_col_rationale,
        group = pick_first(nms, c(
            "group_id", "groupid", "site_id", "siteid", "facility_id", "facilityid",
            "unit_id", "unitid", "schoolid", "school_id", "cluster", "ea_id", "village"
        )),
        enum = pick_first(nms, c("enumeratorid", "enumerator", "enum_id", "interviewer")),
        start = pick_first(nms, c("^starttime$", "startdate", "^start$", "SubmissionDate")),
        end = pick_first(nms, c("^endtime$", "enddate", "^end$")),
        duration = pick_first(nms, c("^duration$", "interview_duration")),
        x = pick_first(nms, c("x_coord", "longitude", "^lon$", "gps.*lon")),
        y = pick_first(nms, c("y_coord", "latitude", "^lat$", "gps.*lat")),
        age = pick_first(nms, c("^age$", "student_age", "respondent_age")),
        assent = pick_first(nms, c("^assent$", "child_assent")),
        consent = pick_first(nms, c("consent_sign", "^consent$", "parental_consent")),
        audio = audio_flag,
        audio_flag = audio_flag,
        audio_file_cols = audio_file_cols,
        image_file_cols = image_file_cols,
        media_folder = if (!is.null(media_folder) && length(media_folder) && !is.na(media_folder[[1]]) &&
                        nzchar(as.character(media_folder[[1]]))) {
        as.character(media_folder[[1]])
        } else {
        NA_character_
        },
        completion_var_candidates = detect_completion_candidates(ds, n = 3L),
        group_var_candidates = detect_grouping_vars(ds, n = 4L),
        form_version_col = detect_form_version_col(ds)
    )

    # Human-readable name fields for the issue-tracking Entity/Group/Enumerator
    # columns — distinct from their ID/code roles above. NA (blank) when no
    # name-like column exists; never falls back to duplicating the ID.
    pick_name_field <- function(patterns, taken) pick_first(setdiff(nms, taken), patterns)
    roles$entity_name_field <- pick_name_field(
        c("respondent_name", "student_name", "participant_name", "hh_head_name",
          "beneficiary_name", "full_name", "^name$"),
        taken = c(roles$entity_id, roles$group, roles$enum, roles$country_col_candidates)
    )
    roles$group_name <- pick_name_field(
        c("village_name", "site_name", "facility_name", "school_name",
          "community_name", "group_name", "location_name"),
        taken = c(roles$entity_id, roles$entity_name_field, roles$group, roles$enum, roles$country_col_candidates)
    )
    roles$enum_name <- pick_name_field(
        c("enumerator_name", "interviewer_name", "surveyor_name", "enum_name", "fieldworker_name"),
        taken = c(roles$entity_id, roles$entity_name_field, roles$group, roles$group_name, roles$enum, roles$country_col_candidates)
    )

    # Unique Submission ID: must run after entity_id/group/enum/name fields
    # are known, so it can exclude them from its uniqueness scan.
    roles$key <- detect_unique_key_column(ds, exclude = c(
        roles$entity_id, roles$group, roles$enum, roles$x, roles$y,
        roles$entity_name_field, roles$group_name, roles$enum_name,
        audio_file_cols, image_file_cols
    ))

    img <- image_file_cols
    roles$consent_image <- {
        hit <- grep("consent|parent|sign", img, ignore.case = TRUE, value = TRUE)
        if (length(hit)) hit[[1]] else if (length(img)) img[[1]] else NA_character_
    }
    roles$assent_image <- {
        hit <- grep("assent|child", img, ignore.case = TRUE, value = TRUE)
        if (length(hit)) hit[[1]] else NA_character_
    }

    num_cols <- nms[vapply(ds, function(x) {
        v <- safe_num(x)
        sum(is.finite(v)) > 30 && length(unique(v[is.finite(v)])) > 10
    }, logical(1))]
    exclude <- unique(c(roles$entity_id, roles$group, roles$enum, roles$key, roles$x, roles$y,
                        roles$entity_name_field, roles$group_name, roles$enum_name,
                        grep("id$|_id$|^key$", nms, ignore.case = TRUE, value = TRUE)))
    num_cols <- setdiff(num_cols, exclude)
    prefer <- intersect(c(roles$age, roles$duration, "age", "duration"), num_cols)
    roles$numeric_shortlist <- unique(c(prefer, num_cols))[seq_len(min(10, length(unique(c(prefer, num_cols)))))]
    roles$sumstats_var_candidates <- utils::head(roles$numeric_shortlist, 10)
    roles$missingness_var_candidates <- unique(c(
        utils::head(roles$numeric_shortlist, 10),
        Filter(Negate(is.na), c(roles$consent, roles$assent))
    ))
    roles$missingness_var_candidates <- utils::head(roles$missingness_var_candidates, 10)

    ordinal_exclude <- unique(c(roles$entity_id, roles$group, roles$enum, roles$key, roles$x, roles$y,
                                roles$start, roles$end, roles$duration,
                                roles$entity_name_field, roles$group_name, roles$enum_name,
                                roles$composite_entity_id_candidates,
                                grep("id$|_id$|^key$|date|time|member|roster|line|index", nms, ignore.case = TRUE, value = TRUE)))
    roles$ordinal_vars <- detect_ordinal_vars(ds, exclude = ordinal_exclude, n = 20L)

    roles$has_gps <- !is.na(roles$x) && !is.na(roles$y)
    roles$has_enum <- !is.na(roles$enum)
    roles$has_unit <- !is.na(roles$group)
    roles$has_consentish <- !is.na(roles$assent) || !is.na(roles$consent) || !is.na(roles$audio_flag)
    roles$has_media <- length(audio_file_cols) > 0 || length(image_file_cols) > 0
    roles$media_folder_found <- !is.na(roles$media_folder) && nzchar(roles$media_folder) &&
        dir.exists(roles$media_folder)

    # Candidate "last date of data collection" — max of start/end date columns.
    date_col <- if (!is.na(roles$end)) roles$end else roles$start
    roles$last_date_candidate <- if (!is.na(date_col) && date_col %in% nms) {
        dt <- suppressWarnings(as.Date(as.character(ds[[date_col]])))
        if (all(is.na(dt))) NA_character_ else as.character(max(dt, na.rm = TRUE))
    } else NA_character_

    # Candidate single-country value, when a country-like column has exactly
    # one distinct non-missing value (common single-country survey case).
    roles$country_value_candidate <- NA_character_
    if (length(roles$country_col_candidates)) {
        col1 <- roles$country_col_candidates[[1]]
        vals <- unique(as.character(ds[[col1]]))
        vals <- vals[!is.na(vals) & nzchar(vals)]
        if (length(vals) == 1) roles$country_value_candidate <- vals[[1]]
    }

    roles
}

default_modules <- function(roles) {
    audio_cols <- roles$audio_file_cols %||% character()
    image_cols <- roles$image_file_cols %||% character()
    audio_cols <- utils::head(audio_cols, 5)
    image_cols <- utils::head(image_cols, 5)

    list(
        M1 = list(
        on = TRUE,
        completion_var = if (length(roles$completion_var_candidates)) roles$completion_var_candidates[[1]] else NA_character_,
        group_vars = roles$group_var_candidates %||% character(),
        by_enum = TRUE,
        by_date = TRUE,
        low_completion_on = isTRUE(roles$has_unit),
        pct_median = 0.5
        ),
        M2 = list(on = TRUE, id = roles$entity_id, extra_keys = roles$dup_key_extra %||% character()),
        M3 = list(
        on = TRUE,
        version_col = roles$form_version_col %||% NA_character_,
        version_map = list()
        ),
        M4 = list(
        on = TRUE,
        duration = roles$duration,
        sd_rule = 3,
        section_map = list(),
        by_enum = TRUE
        ),
        M5 = list(
        on = TRUE,
        flag_weekend = TRUE,
        evening_hour = 19,
        morning_hour = 7
        ),
        M6 = list(on = TRUE, vars = utils::head(roles$numeric_shortlist, 10), sd_rule = 3),
        M7 = list(
        on = TRUE,
        vars = roles$missingness_var_candidates %||% character(),
        sentinel_codes = character(),
        by_enum = TRUE
        ),
        M8 = list(on = isTRUE(roles$has_gps), x = roles$x, y = roles$y, threshold_m = 300),
        M9 = list(
        on = length(roles$ordinal_vars %||% character()) > 0,
        ordinal_vars = utils::head(roles$ordinal_vars %||% character(), 15),
        enum_threshold_pct = 0.8,
        survey_threshold_pct = 0.8
        ),
        M10 = list(on = TRUE, vars = roles$sumstats_var_candidates %||% character(), max_n = 10L),
        M11 = list(on = FALSE, enabled = character(), custom = character()),
        M12 = list(
        on = isTRUE(roles$has_media),
        audio_cols = audio_cols,
        image_cols = image_cols,
        media_folder = roles$media_folder %||% NA_character_,
        min_audio_bytes = 1024L,
        min_image_bytes = 2048L,
        min_duration_sec = 5,
        max_duration_sec = 3600,
        audio_flag = roles$audio_flag %||% NA_character_,
        flag_file_col = if (length(audio_cols)) audio_cols[[1]] else NA_character_
        ),
        M13 = list(
        on = isTRUE(roles$has_consentish),
        assent = roles$assent,
        consent = roles$consent,
        audio = roles$audio_flag
        )
    )
}

format_module_cards <- function(roles) {
    opt_letters <- function(opts) {
        if (!length(opts) || all(is.na(opts))) return("(none found)")
        paste(sprintf("%s%s %s", LETTERS[seq_along(opts)],
                    ifelse(seq_along(opts) == 1, "*", ""), opts), collapse = "  ")
    }
    m11_line <- "M11 Survey-specific [none*]  (fully custom — describe any survey-specific checks you want in the Additional checks step)"

    audio_f <- roles$audio_file_cols %||% character()
    image_f <- roles$image_file_cols %||% character()
    mf <- roles$media_folder %||% NA_character_
    m12_line <- if (isTRUE(roles$has_media)) {
        sprintf(
        "M12 Media files [Y*]  audio: %s  images: %s  media_folder=%s  duration=[5*,3600]s",
        opt_letters(utils::head(audio_f, 5)),
        opt_letters(utils::head(image_f, 5)),
        if (!is.na(mf) && nzchar(mf)) mf else "(missing - column-only checks)"
        )
    } else {
        "M12 Media files [skip*]  (no audio/image filename columns detected)"
    }

    id_lines <- if (length(roles$entity_id_rationale)) {
        paste0("Entity ID shortlist: ", paste(roles$entity_id_rationale, collapse = " | "))
    } else {
        sprintf("Entity ID shortlist: %s", opt_letters(roles$entity_id_options))
    }
    composite_lines <- if (length(roles$composite_entity_id_rationale)) {
        paste0("Composite Entity ID candidates: ", paste(roles$composite_entity_id_rationale, collapse = " | "))
    } else {
        "Composite Entity ID candidates: (none found)"
    }
    dup_key_line <- if (length(roles$dup_key_extra)) {
        sprintf("Duplicate-check key: entity_id + %s", paste(roles$dup_key_extra, collapse = ", "))
    } else {
        "Duplicate-check key: Entity ID alone"
    }
    country_lines <- if (length(roles$country_col_rationale)) {
        paste0("Country column candidates: ", paste(roles$country_col_rationale, collapse = " | "))
    } else {
        sprintf("Country: no column detected%s",
                if (!is.na(roles$country_value_candidate)) sprintf(" (single value seen: %s)", roles$country_value_candidate) else "")
    }

    c(
        id_lines,
        composite_lines,
        dup_key_line,
        country_lines,
        sprintf("Last date of data collection (detected): %s", roles$last_date_candidate %||% "?"),
        sprintf("M1 Completion [Y*]  completion_var=%s  groups=%s  by_enum=Y*  by_date=Y*  low_completion=%s* of median",
                if (length(roles$completion_var_candidates)) roles$completion_var_candidates[[1]] else "(derive)",
                if (length(roles$group_var_candidates)) paste(roles$group_var_candidates, collapse = ",") else "none",
                "50%"),
        sprintf("M2 Duplicates [Y*/N]  Entity ID: %s  extra_keys=%s",
                opt_letters(roles$entity_id_options),
                if (length(roles$dup_key_extra)) paste(roles$dup_key_extra, collapse = ",") else "none*"),
        sprintf("M3 Form Version [%s]  version_col=%s",
                if (!is.na(roles$form_version_col)) "Y*" else "best-guess*",
                roles$form_version_col %||% "(none - will infer)"),
        sprintf("M4 Survey Duration [Y*]  duration=%s  rule=3SD* both sides  by_enum=Y*",
                roles$duration %||% "?"),
        "M5 Irregular Timing [Y*]  weekends*  7pm-7am*",
        sprintf("M6 Numeric Outliers [Y*]  pick (up to 10): %s  rule=3SD*",
                paste(sprintf("%s* %s", LETTERS[seq_along(utils::head(roles$numeric_shortlist, 10))],
                            utils::head(roles$numeric_shortlist, 10)), collapse = "  ")),
        sprintf("M7 Missingness [Y*]  pick (up to 10): %s  by_enum=Y*  sentinel codes: (confirm after vars)",
                paste(utils::head(roles$missingness_var_candidates %||% character(), 10), collapse = ", ")),
        sprintf("M8 GPS [%s]  pair=%s/%s  threshold=300*",
                if (roles$has_gps) "Y*" else "N*", roles$x %||% "?", roles$y %||% "?"),
        sprintf("M9 Straightlining [%s]  ordinal vars: %s  enum_threshold=80%%*  survey_threshold=80%%*",
                if (length(roles$ordinal_vars %||% character())) "Y*" else "skip*",
                paste(utils::head(roles$ordinal_vars %||% character(), 10), collapse = ", ")),
        sprintf("M10 Summary Stats [Y*]  pick (up to 10, expandable): %s",
                paste(utils::head(roles$sumstats_var_candidates %||% character(), 10), collapse = ", ")),
        m11_line,
        m12_line,
        sprintf("M13 Consent/assent/audio flags [%s]  assent=%s consent=%s audio_flag=%s",
                if (roles$has_consentish) "Y*" else "skip*",
                roles$assent %||% "none", roles$consent %||% "none", roles$audio_flag %||% "none")
    )
}
