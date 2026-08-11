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
    if (is.null(lab) || length(lab) != 1 || !nzchar(as.character(lab))) return(NA_character_)
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
    hit <- grep("complete|submitted|finished|^result$|^status$|^outcome$|disposition|interview_status", nms, ignore.case = TRUE, value = TRUE)
    utils::head(hit, n)
}

#' Candidate primary/secondary sample-designation columns (M1's fallback
#' completion signal, when there's no roster and no explicit status column —
#' every row IS a completed survey, but composed of a primary + secondary
#' pool). Requires a name-pattern hit AND a plausible 2-value shape.
PRIMARY_SECONDARY_NAME_PATTERN <- "sample_type|^primary$|resp_type|respondent_type|sample_status"
PRIMARY_SECONDARY_VALUE_PATTERN <- "^(primary|secondary|1|2)$"
detect_primary_secondary_col <- function(ds) {
    nms <- names(ds)
    name_hit <- nms[grepl(PRIMARY_SECONDARY_NAME_PATTERN, nms, ignore.case = TRUE)]
    hit <- name_hit[vapply(name_hit, function(col) {
        x <- tolower(trimws(as.character(ds[[col]])))
        vals <- unique(x[!is.na(x) & nzchar(x)])
        length(vals) == 2 && all(grepl(PRIMARY_SECONDARY_VALUE_PATTERN, vals, ignore.case = TRUE))
    }, logical(1))]
    if (length(hit)) hit[[1]] else NA_character_
}

#' Values in a completion-status column that read as "this survey happened."
#' Matched against the column's own distinct values (not a fixed vocabulary
#' alone), so e.g. "Submitted" or "Yes" are recognized even though they
#' aren't literally "Complete".
COMPLETION_COMPLETE_VALUE_PATTERN <- "^(complete|completed|yes|submitted|finished|success|successful|1)$"

#' Detect which completion-signal type(s) are present in this dataset. The
#' agent surfaces ALL types found — this function does NOT silently
#' prioritize when more than one applies; the required-gate window's
#' completion tab (SKILL.md A1) is responsible for flagging that as a
#' special case rather than picking for the user.
#' `roster_candidate`: passed through from discover_project()'s roster
#' detection (NULL in the common single-file case).
#' Returns list(types = character() subset of "status"/"primary_secondary"/
#' "roster", status_col=, status_complete_values=, ps_col=, primary_value=,
#' roster_candidate=).
detect_completion_signal <- function(ds, roster_candidate = NULL) {
    status_col <- pick_first(names(ds), c(
        "^result$", "^status$", "^outcome$", "disposition", "interview_status",
        "^complete$", "^completed$", "submitted", "finished"
    ))
    status_complete_values <- character()
    if (!is.na(status_col)) {
        vals <- unique(trimws(as.character(ds[[status_col]])))
        vals <- vals[!is.na(vals) & nzchar(vals)]
        status_complete_values <- vals[grepl(COMPLETION_COMPLETE_VALUE_PATTERN, vals, ignore.case = TRUE)]
        # A status-like column only counts as a real signal if it actually
        # has BOTH complete-looking and non-complete-looking values — a
        # column where every value reads as "complete" carries no
        # filtering information (nothing to distinguish).
        if (!length(status_complete_values) || length(status_complete_values) == length(vals)) {
            status_col <- NA_character_
        }
    }

    ps_col <- detect_primary_secondary_col(ds)
    primary_value <- NA_character_
    if (!is.na(ps_col)) {
        vals <- unique(trimws(as.character(ds[[ps_col]])))
        vals <- vals[!is.na(vals) & nzchar(vals)]
        hit <- vals[grepl("primary|^1$", vals, ignore.case = TRUE)]
        primary_value <- if (length(hit)) hit[[1]] else vals[[1]]
    }

    types <- c(
        if (!is.na(status_col)) "status",
        if (!is.na(ps_col)) "primary_secondary",
        if (!is.null(roster_candidate)) "roster"
    )

    list(
        types = types,
        status_col = status_col, status_complete_values = status_complete_values,
        ps_col = ps_col, primary_value = primary_value,
        roster_candidate = roster_candidate
    )
}

#' Surfaces raw material for the AGENT to infer a country from when no
#' explicit country column exists — district/region/village/site-name-like
#' columns' sample values, plus a GPS bounding box if x/y columns exist.
#' Does NOT resolve a country itself: country inference from place names or
#' a GPS bounding box is agent judgment (documented in SKILL.md), the same
#' treatment as M10 custom-check authorship and redundant-variable
#' de-duplication — a regex/lookup table can't reliably map "Bujumbura" or
#' "Gashanga" to a country the way a general-knowledge reader can.
GEOGRAPHY_SIGNAL_NAME_PATTERN <- "district|region|province|county|village|ward|site_name|school_name|community|admin[1-4]"
shortlist_geography_signal_cols <- function(ds, x_col = NA_character_, y_col = NA_character_, n = 4L) {
    nms <- names(ds)
    hit <- grep(GEOGRAPHY_SIGNAL_NAME_PATTERN, nms, ignore.case = TRUE, value = TRUE)
    hit <- hit[vapply(hit, function(col) {
        x <- as.character(ds[[col]])
        nu <- length(unique(x[!is.na(x) & nzchar(x)]))
        nu >= 1 && nu <= 200
    }, logical(1))]
    hit <- utils::head(hit, n)
    samples <- lapply(hit, function(col) {
        x <- as.character(ds[[col]])
        x <- x[!is.na(x) & nzchar(x)]
        utils::head(unique(x), 10)
    })
    names(samples) <- hit

    gps_bbox <- NULL
    if (!is.na(x_col) && !is.na(y_col) && x_col %in% nms && y_col %in% nms) {
        xv <- safe_num(ds[[x_col]]); yv <- safe_num(ds[[y_col]])
        xv <- xv[is.finite(xv)]; yv <- yv[is.finite(yv)]
        if (length(xv) && length(yv)) {
        gps_bbox <- list(lon_min = min(xv), lon_max = max(xv), lat_min = min(yv), lat_max = max(yv))
        }
    }

    list(geo_col_options = hit, geo_col_samples = samples, gps_bbox = gps_bbox)
}

#' Scan a shortlisted set of numeric-ish variables' value distributions for
#' common sentinel/missing-code patterns (99/-99/-9999/999/88 etc.)
#' appearing disproportionately relative to the variable's apparent scale —
#' a speculative guess, always shown with a correction box, never trusted
#' silently. Lets the sentinel-code guess be stated in the SAME message as
#' the variable shortlist (SKILL.md's Variables bundle tab) instead of
#' requiring a separate follow-up question once the variables are confirmed.
SENTINEL_CANDIDATES <- c(-9999, -999, -99, -88, -9, 99, 88, 999, 9999)
guess_sentinel_codes <- function(ds, vars) {
    vars <- vars[!is.na(vars) & vars %in% names(ds)]
    if (!length(vars)) return(integer())
    hits <- integer()
    for (vc in vars) {
        v <- safe_num(ds[[vc]])
        v <- v[is.finite(v)]
        if (length(v) < 10) next
        core <- v[!v %in% SENTINEL_CANDIDATES]
        if (!length(core)) next
        core_range <- range(core)
        for (cand in SENTINEL_CANDIDATES) {
        n_cand <- sum(v == cand)
        # A sentinel candidate is "plausible" if it appears at least a
        # couple of times AND sits well outside the variable's normal
        # (non-sentinel) range — i.e. looks like an out-of-band code, not
        # a genuine data value.
        if (n_cand >= 2 && (cand < core_range[1] - 1 || cand > core_range[2] + 1)) {
            hits <- c(hits, cand)
        }
        }
    }
    sort(unique(hits))
}

#' Candidate Treatment/Control-like columns for completion-by-group (M1) —
#' the DEFAULT grouping. Requires BOTH a name-pattern hit AND a plausible
#' value shape (2-3 distinct values that look like Treatment/Control/T/C/1/0)
#' together, so an unrelated 0/1 flag that merely shares a name fragment
#' Guess a human-readable label for what roles$group actually represents
#' (e.g. "school_id" -> "School", "village" -> "Village") — used as the
#' report/issue-tracking column header in place of the generic "Group ID".
#' Confirmable/correctable like roles$entity_label (see SKILL.md's later
#' module-config window, not the required Setup gate); NA when nothing
#' matches, in which case callers fall back to the generic "Group".
derive_group_label <- function(group_col_name) {
    if (is.null(group_col_name) || length(group_col_name) == 0 || is.na(group_col_name) || !nzchar(group_col_name)) {
        return(NA_character_)
    }
    gc <- tolower(group_col_name)
    label_patterns <- c(
        "school" = "School", "village" = "Village", "facility" = "Facility",
        "cluster" = "Cluster", "ea_id|^ea$" = "Enumeration Area", "site" = "Site",
        "community" = "Community", "ward" = "Ward", "district" = "District"
    )
    for (pat in names(label_patterns)) {
        if (grepl(pat, gc)) return(unname(label_patterns[[pat]]))
    }
    NA_character_
}

#' (e.g. a "group" column that's actually a household roster grouping) isn't
#' mistaken for a study arm.
TREAT_NAME_PATTERN <- "treat|^arm$|condition|^tx$|^grp$|assignment"
TREAT_VALUE_PATTERN <- "^(treatment|control|treat|ctrl|t|c|1|0)$"
detect_treatment_control_vars <- function(ds, n = 2L) {
    nms <- names(ds)
    name_hit <- nms[grepl(TREAT_NAME_PATTERN, nms, ignore.case = TRUE)]
    hit <- name_hit[vapply(name_hit, function(col) {
        x <- toupper(trimws(as.character(ds[[col]])))
        vals <- unique(x[!is.na(x) & nzchar(x)])
        length(vals) %in% 2:3 && all(grepl(TREAT_VALUE_PATTERN, vals, ignore.case = TRUE))
    }, logical(1))]
    utils::head(hit, n)
}

#' Candidate geographic-unit columns for completion-by-group (M1) — the
#' OPT-IN secondary grouping, only offered when no Treatment/Control column
#' exists, or the user explicitly asks for it in addition.
GEO_GROUP_NAME_PATTERN <- "state|region|district|stratum|province|county|admin[1-4]"
detect_geographic_group_vars <- function(ds, n = 4L) {
    nms <- names(ds)
    hit <- grep(GEO_GROUP_NAME_PATTERN, nms, ignore.case = TRUE, value = TRUE)
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

#' Section-level start/end timestamp PAIRS (e.g. introduction_start /
#' introduction_end, training_start / training_end) — distinct from the one
#' overall roles$start/roles$end pair, which is excluded here so it isn't
#' double-counted as its own "section". Pairs columns sharing a common stem
#' under either a `<stem>_start`/`<stem>_end` or `start_<stem>`/`end_<stem>`
#' naming convention. Used by check_m4() (M4 Timing) to offer an optional
#' per-section duration breakdown (SKILL.md A2, Keys & Hours window).
#' Returns a named list: Title Case label -> list(start = col, end = col).
detect_section_time_pairs <- function(ds, exclude = character()) {
    nms <- setdiff(names(ds), exclude)
    suffix_starts <- grep("^(.+)_start$", nms, ignore.case = TRUE, value = TRUE)
    suffix_ends <- grep("^(.+)_end$", nms, ignore.case = TRUE, value = TRUE)
    prefix_starts <- grep("^start_(.+)$", nms, ignore.case = TRUE, value = TRUE)
    prefix_ends <- grep("^end_(.+)$", nms, ignore.case = TRUE, value = TRUE)

    stem_of <- function(x, pattern) sub(pattern, "\\1", x, ignore.case = TRUE)
    pairs <- list()
    for (sc in suffix_starts) {
        stem <- stem_of(sc, "^(.+)_start$")
        ec <- suffix_ends[stem_of(suffix_ends, "^(.+)_end$") == stem]
        if (length(ec)) pairs[[stem]] <- list(start = sc, end = ec[[1]])
    }
    for (sc in prefix_starts) {
        stem <- stem_of(sc, "^start_(.+)$")
        if (!is.null(pairs[[stem]])) next
        ec <- prefix_ends[stem_of(prefix_ends, "^end_(.+)$") == stem]
        if (length(ec)) pairs[[stem]] <- list(start = sc, end = ec[[1]])
    }
    if (!length(pairs)) return(list())

    title_case <- function(s) {
        s <- gsub("[_.]+", " ", s)
        s <- trimws(s)
        paste0(toupper(substring(s, 1, 1)), substring(s, 2))
    }
    stats::setNames(pairs, vapply(names(pairs), title_case, character(1)))
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
    is_fully_unique <- function(col) {
        x <- ds[[col]]
        x_chr <- as.character(x)
        if (any(is.na(x) | !nzchar(x_chr))) return(FALSE)
        length(unique(x_chr)) == nrow(ds)
    }
    # A literal `key` column (SurveyCTO's own globally-unique submission ID)
    # is trusted unconditionally, whenever it exists — checked against the
    # FULL column set first, before `exclude` is applied, since a column can
    # legitimately serve as both Entity ID and the unique submission key at
    # once. Skips the uniqueness gate deliberately: a handful of corrupted/
    # duplicate `key` values in real field data is exactly what M2
    # Duplicates exists to catch, not a reason to silently substitute a
    # different column as the reported Unique Submission ID.
    key_col <- pick_first(names(ds), "^key$")
    if (!is.na(key_col)) return(key_col)

    # uuid/instanceid aren't the literal SurveyCTO convention, so they keep
    # the stricter uniqueness-gated behavior.
    name_cand <- pick_first(names(ds), c("uuid", "instanceid"))
    if (!is.na(name_cand) && is_fully_unique(name_cand)) return(name_cand)

    nms <- setdiff(names(ds), exclude)
    candidates <- nms[vapply(nms, is_fully_unique, logical(1))]
    if (!length(candidates)) return(NA_character_)
    pref <- candidates[grepl(ID_NAME_PATTERN, candidates, ignore.case = TRUE)]
    if (length(pref)) return(pref[[1]])
    candidates[[1]]
}

# Profile roles. Optional media_folder from config.json's Media Folder
# Directory. Optional roster_candidate from discover_project()'s roster/
# target-file detection (NULL in the common single-file case) — threaded
# into detect_completion_signal() below.
profile_roles <- function(ds, media_folder = NA_character_, roster_candidate = NULL) {
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
        treatment_control_candidates = detect_treatment_control_vars(ds, n = 2L),
        geo_group_candidates = detect_geographic_group_vars(ds, n = 4L),
        form_version_col = detect_form_version_col(ds)
    )
    # Deprecated alias: default_modules()/check_modules_preview.R read
    # group_var_candidates as their M1$group_vars source, now preferring
    # Treatment/Control over geography (see default_modules() below).
    roles$group_var_candidates <- roles$treatment_control_candidates %||% roles$geo_group_candidates

    # Section-level start/end timestamp pairs, distinct from the overall
    # roles$start/roles$end — see detect_section_time_pairs(). Empty list
    # (never NULL) when the survey has no section-level timing at all.
    roles$section_time_pairs <- detect_section_time_pairs(
        ds, exclude = c(roles$start, roles$end)
    )

    # A guessed display label for roles$group (e.g. "School", "Village") —
    # confirmed later, not part of the required Setup gate; see
    # derive_group_label(). NA until confirmed/guessed successfully, in
    # which case report/issue-tracking headers fall back to "Group".
    roles$group_label <- derive_group_label(roles$group)

    # De-identification-by-default policy: HFC data never has the surveyed
    # individual's real name, but usually does have enumerator names — so
    # Entity defaults to ID-only and Enumerator/Group default to
    # name-if-available. Not guessed/detected — fixed defaults, silently
    # overridable per project (the agent edits these directly in
    # role_map.yaml only when a user explicitly asks for the opposite, e.g.
    # non-anonymized data or a preference for raw enumerator IDs — never a
    # guessed value, never a new setup question). See resolve_display_vec()
    # in utils.R for where these are actually applied.
    roles$entity_display <- "id"
    roles$enumerator_display <- "name"
    roles$group_display <- "name"

    # Completion signal (status column / roster-file / primary-secondary
    # column) — see SKILL.md A1's required-gate window Tab 2.
    completion_signal <- detect_completion_signal(ds, roster_candidate = roster_candidate)
    roles$completion_signal_types <- completion_signal$types
    roles$completion_status_col <- completion_signal$status_col
    roles$completion_status_complete_values <- completion_signal$status_complete_values
    roles$completion_primary_secondary_col <- completion_signal$ps_col
    roles$completion_primary_value <- completion_signal$primary_value
    roles$completion_roster_candidate <- completion_signal$roster_candidate
    # Tentative default when exactly one signal type is detected; when more
    # than one is found this is only a starting point — SKILL.md A1's
    # completion tab must flag the conflict explicitly rather than silently
    # trusting this pick, and role_map.yaml's saved value (once the agent
    # confirms) always wins on a rebuild. NA when no signal at all.
    roles$completion_primary_signal <- if (length(completion_signal$types) >= 1) completion_signal$types[[1]] else NA_character_

    # Country-from-geography raw material — only useful when no explicit
    # country column exists; the agent reads geo_col_samples/gps_bbox and
    # states its own best-guess country (SKILL.md A1), this function does
    # not resolve a country itself.
    geo_signal <- shortlist_geography_signal_cols(ds, x_col = roles$x %||% NA_character_, y_col = roles$y %||% NA_character_, n = 4L)
    roles$geo_signal_col_options <- geo_signal$geo_col_options
    roles$geo_signal_col_samples <- geo_signal$geo_col_samples
    roles$geo_signal_gps_bbox <- geo_signal$gps_bbox

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

    # Unified "important variables" shortlist (SKILL.md A2.10) drives M6/M9/M13
    # instead of each module picking its own independent pool. M6/M13 use it
    # directly (any variable type is fine there); M9 straightlining still
    # needs ordinal-shaped columns specifically, so it intersects the
    # confirmed list with the auto-detected ordinal pool — falling back to
    # the FULL auto ordinal pool if that intersection is empty, so a
    # variable-selection choice never silently disables the whole module.
    important_vars <- roles$important_vars %||% character()
    m6_vars <- if (length(important_vars)) important_vars else (roles$numeric_shortlist %||% character())
    m13_vars <- if (length(important_vars)) important_vars else (roles$sumstats_var_candidates %||% character())
    m9_ordinal <- if (length(important_vars)) {
        intersect(important_vars, roles$ordinal_vars %||% character())
    } else character()
    if (!length(m9_ordinal)) m9_ordinal <- roles$ordinal_vars %||% character()

    # M7 Missingness gets the unified shortlist PLUS up to ~20 more
    # variables (any type, not just numeric) the agent separately judges
    # important for missingness reporting specifically — live judgment
    # during setup, no AskUserQuestion confirmation, written directly to
    # role_map.yaml's missingness_extra_vars (see SKILL.md A2 step 4).
    # Falls back to the old auto-derived candidate pool only when neither
    # has been confirmed yet (e.g. the very first draft modules.yaml,
    # before that step has run).
    m7_vars <- unique(c(important_vars, roles$missingness_extra_vars %||% character()))
    if (!length(m7_vars)) m7_vars <- roles$missingness_var_candidates %||% character()

    # M1's completion-by-group breakdown defaults to Treatment/Control;
    # geography is only added when there's no Treatment/Control column at
    # all, or the user explicitly opted in to it alongside T/C (default:
    # declined — see roles$geo_group_opted_in, confirmed in the Media, Map
    # & Grouping window's Add geography tab).
    m1_tc <- roles$treatment_control_col %||%
        (if (length(roles$treatment_control_candidates)) roles$treatment_control_candidates[[1]] else NA_character_)
    m1_geo <- roles$geo_group_col %||%
        (if (length(roles$geo_group_candidates)) roles$geo_group_candidates[[1]] else NA_character_)
    m1_group_vars <- if (!is.na(m1_tc)) {
        c(m1_tc, if (isTRUE(roles$geo_group_opted_in)) m1_geo else NA_character_)
    } else {
        m1_geo
    }
    m1_group_vars <- m1_group_vars[!is.na(m1_group_vars)]

    list(
        M1 = list(
        on = TRUE,
        completion_var = if (length(roles$completion_var_candidates)) roles$completion_var_candidates[[1]] else NA_character_,
        # Which signal type is actually driving check_m1()'s complete_flag
        # for this project ("gating" — the preferred, instrument-read
        # signal — "roster"/"primary_secondary", or "row_missingness" when
        # none was detected) — round-tripped through modules.yaml so the
        # report's Completion section (module_desc.R's m1_desc()) can state
        # it concretely.
        completion_signal = roles$completion_primary_signal %||% "row_missingness",
        # Gating (Completion Signals window, A1): agent-confirmed screening
        # question(s), in form order, plus each one's "pass"/continue value
        # and (optional) a human label for the report/desc text. Blank
        # until the agent identifies + confirms real gates for this survey.
        gate_cols = character(),
        gate_pass_values = list(),
        gate_labels = list(),
        # Day-by-day enumerator productivity vs. a user-stated target
        # (Completion Signals window) — NA/unset skips that check entirely.
        daily_target_per_enum = NA_real_,
        # Replacement-sample analysis (Completion Signals window, A1) —
        # columns in the roster/target file (target_ds), independent of
        # completion_signal: which column marks Primary vs Secondary/
        # Replacement, which values count as "Primary", the numeric
        # position-in-the-replacement-queue column, and the roster's own
        # group column (matched by raw value against roles$group). Blank
        # until the agent identifies + confirms them for this survey; blank
        # skips the whole feature.
        replacement_status_col = NA_character_,
        replacement_primary_values = "primary",
        replacement_rank_col = NA_character_,
        replacement_group_col = NA_character_,
        group_vars = m1_group_vars,
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
        section_pairs = list(),
        by_enum = TRUE
        ),
        M5 = list(
        on = TRUE,
        flag_weekend = TRUE,
        evening_hour = 19,
        morning_hour = 7
        ),
        M6 = list(on = TRUE, vars = utils::head(m6_vars, 10), sd_rule = 3),
        M7 = list(
        on = TRUE,
        vars = m7_vars,
        sentinel_codes = character(),
        by_enum = TRUE,
        var_issue_threshold = 0.5,
        enum_pool_threshold = 0.9,
        enum_pct_threshold = 0.5
        ),
        M8 = list(on = isTRUE(roles$has_gps), x = roles$x, y = roles$y, threshold_m = 300),
        M9 = list(
        on = length(m9_ordinal) > 0,
        ordinal_vars = utils::head(m9_ordinal, 15),
        enum_threshold_pct = 0.9,
        survey_threshold_pct = 0.9
        ),
        M10 = list(on = FALSE, enabled = character(), custom = character()),
        M11 = list(
        on = isTRUE(roles$has_media),
        audio_cols = audio_cols,
        image_cols = image_cols,
        other_cols = roles$qualitative_text_cols %||% character()
        ),
        M12 = list(
        on = isTRUE(roles$has_consentish),
        assent = roles$assent,
        consent = roles$consent,
        audio = roles$audio_flag
        ),
        M13 = list(on = TRUE, vars = utils::head(m13_vars, 10), by_enum = TRUE, max_n = 10L)
    )
}

