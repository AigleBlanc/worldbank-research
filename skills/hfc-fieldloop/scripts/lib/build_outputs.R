# Build the issue-tracking workbook (tracking + feedback in one), HTML report,
# project scaffold under hfc/. Single output replaces the old separate
# tracking.xlsx + feedback twin.

# Single source of truth for the issue-tracking schema: internal snake_case
# name (used everywhere in R) -> assets/issue_tracking_template.csv header
# label (used only at the file read/write boundary). Column order here is
# the column order in every written file. `finding_id` (displayed as "Issue
# ID") isn't part of the literal template — it's a stable, content-derived
# tracking key (<module>:<entity>[:<variable>][:N], or <module>:enumerator|
# group:<unit>[:<variable>] for an aggregate finding; see mk_findings()/
# mk_aggregate_finding()/dedupe_finding_ids() in utils.R), needed because one
# submission can produce several findings, so `unique_submission_id` alone
# can't key rows. `entity_label`/`group_label`: the project's configured
# labels (role_map.yaml), so the xlsx/csv header never shows the generic
# "Entity ID"/"Group" when a real label (e.g. "Farmer ID"/"School") is
# configured — same substitution the HTML report's findings tables apply.
# There is no separate Entity Name / Enumerator ID / Group ID column: Entity
# is ID-only by default (we never have the respondent's real name — see
# roles$entity_display, default "id"), and Enumerator/Group are each a
# single name-if-available-else-ID column by default (see
# roles$enumerator_display/group_display, default "name") — resolved via
# resolve_display_vec() (utils.R). Either default is a silent, per-project
# role_map.yaml override, never guessed.
issue_tracking_header_map <- function(entity_label = NA_character_, group_label = NA_character_) {
    eid <- if (!is.na(entity_label) && nzchar(entity_label)) entity_label else "Entity ID"
    grp <- if (!is.na(group_label) && nzchar(group_label)) group_label else "Group"
    c(
        today_date            = "Today's Date",
        entity_id             = eid,
        group                 = grp,
        enumerator            = "Enumerator",
        startdate             = "Startdate",
        enddate               = "Enddate",
        issue                 = "Issue",
        value                 = "Value",
        comment               = "Comment",
        corrections           = "Corrections",
        correction_author     = "Correction Author",
        status                = "Status",
        issue_category        = "Issue Category",
        variable              = "Variable (DIME use)",
        unique_submission_id  = "Unique Submission ID",
        finding_id            = "Issue ID"
    )
}

# Rename internal snake_case columns to their display header labels, for
# writing to disk in the shared sync folder. Columns not in the map pass
# through unchanged.
rename_to_issue_tracking_headers <- function(tbl, entity_label = NA_character_, group_label = NA_character_) {
    tbl <- as.data.frame(tbl, stringsAsFactors = FALSE)
    hmap <- issue_tracking_header_map(entity_label, group_label)
    present <- intersect(names(hmap), names(tbl))
    names(tbl)[match(present, names(tbl))] <- hmap[present]
    tbl
}

# Inverse of rename_to_issue_tracking_headers() — for reading from disk
# back into internal snake_case names.
rename_from_issue_tracking_headers <- function(tbl, entity_label = NA_character_, group_label = NA_character_) {
    tbl <- as.data.frame(tbl, stringsAsFactors = FALSE)
    hmap <- issue_tracking_header_map(entity_label, group_label)
    inv <- setNames(names(hmap), hmap)
    present <- intersect(names(inv), names(tbl))
    names(tbl)[match(present, names(tbl))] <- inv[present]
    tbl
}

# Findings -> the issue-tracking shape (internal snake_case names), ready to
# write or push. `roles`: supplies the entity_display/group_display/
# enumerator_display overrides (default "id"/"name"/"name" respectively —
# see resolve_display_vec()); NULL reproduces the defaults. Entity ID stays
# the raw ID by default — blank for an aggregate finding (enumerator/site-
# level), never a respondent name unless entity_display is explicitly set to
# "name". Group/Enumerator resolve to name-if-available-else-ID by default,
# so the sheet never carries a separate ID+Name pair.
findings_to_issue_tracking <- function(findings, roles = NULL) {
    suppressPackageStartupMessages({ library(dplyr); library(tibble) })
    cols <- names(issue_tracking_header_map())
    if (nrow(findings) == 0) {
        return(as_tibble(setNames(rep(list(character()), length(cols)), cols)))
    }
    entity_mode <- roles$entity_display %||% "id"
    group_mode <- roles$group_display %||% "name"
    enum_mode <- roles$enumerator_display %||% "name"
    findings %>%
        transmute(
            today_date = format(Sys.time(), "%Y%m%d%H%M"),
            entity_id = resolve_display_vec(submission_id, entity_name, entity_mode),
            group = resolve_display_vec(group_id, group_name, group_mode),
            enumerator = resolve_display_vec(enumerator, enumerator_name, enum_mode),
            startdate = start_date,
            enddate = end_date,
            issue,
            value,
            comment = "",
            corrections = "",
            correction_author = "",
            status = "Open",
            issue_category = category_label(category),
            variable,
            unique_submission_id = key,
            finding_id
        )
}

# The single shared Status normalizer (internal snake_case `status` column).
# Migrates the old status(Open/accepted/revise)+resolved(No/yes/partial)
# pair into the current 5-value vocabulary (Open/Accepted/Revise/Resolved/
# Needs Review), then canonicalizes casing for known values. Unrecognized
# non-blank Status values pass through unchanged.
normalize_issue_tracking_status <- function(tbl) {
    suppressPackageStartupMessages({ library(dplyr) })
    tbl <- as.data.frame(tbl, stringsAsFactors = FALSE)
    n <- nrow(tbl)
    if (!"status" %in% names(tbl) && "ra_status" %in% names(tbl)) {
        tbl$status <- tbl$ra_status
    }
    if (!"status" %in% names(tbl)) tbl$status <- rep("Open", n)
    tbl$status[is.na(tbl$status) | !nzchar(as.character(tbl$status))] <- "Open"

    if ("resolved" %in% names(tbl)) {
        st <- tolower(as.character(tbl$status))
        rs <- tolower(as.character(tbl$resolved))
        rs[is.na(rs) | !nzchar(rs)] <- "no"
        tbl$status <- dplyr::case_when(
        st == "accepted" & rs == "yes" ~ "Resolved",
        st == "accepted" & rs == "partial" ~ "Needs Review",
        st == "accepted" ~ "Accepted",
        st == "revise" ~ "Revise",
        TRUE ~ "Open"
        )
        tbl$resolved <- NULL
    } else {
        known <- c("Open", "Accepted", "Revise", "Resolved", "Needs Review")
        hit <- match(tolower(as.character(tbl$status)), tolower(known))
        tbl$status[!is.na(hit)] <- known[hit[!is.na(hit)]]
    }
    tbl$ra_status <- NULL
    tbl$check_module <- NULL
    tbl
}

# Normalize Status, fill/reorder to the canonical column set, and rename to
# display header labels — the one shared prep step every writer (local xlsx,
# local csv) must apply identically so the live file stays consistent.
prepare_tracking_display <- function(tbl, entity_label = NA_character_, group_label = NA_character_) {
    tbl <- normalize_issue_tracking_status(tbl)
    cols <- names(issue_tracking_header_map())
    for (c in cols) if (!c %in% names(tbl)) tbl[[c]] <- ""
    tbl <- tbl[, cols, drop = FALSE]
    rename_to_issue_tracking_headers(tbl, entity_label, group_label)
}

# Write the issue-tracking csv + xlsx (Tracking/Findings/Instructions tabs).
write_issue_tracking <- function(tbl, findings, xlsx_path, csv_path, entity_label = NA_character_, group_label = NA_character_) {
    suppressPackageStartupMessages({ library(openxlsx); library(readr) })
    display <- prepare_tracking_display(tbl, entity_label, group_label)

    dir.create(dirname(csv_path), recursive = TRUE, showWarnings = FALSE)
    dir.create(dirname(xlsx_path), recursive = TRUE, showWarnings = FALSE)
    write_csv(display, csv_path)

    wb <- createWorkbook()
    addWorksheet(wb, "Tracking")
    writeData(wb, "Tracking", display)
    if (!is.null(findings) && nrow(findings) > 0) {
        addWorksheet(wb, "Findings")
        writeData(wb, "Findings", findings)
    }
    addWorksheet(wb, "Instructions")
    writeData(wb, "Instructions", data.frame(
        step = 1:4,
        action = c(
        "Field: fill Comment and Corrections",
        "RA: set Status to Accepted | Revise | leave Open",
        "RA: set Correction Author",
        "When ready in chat: Process HFC feedback"
        )
    ))
    saveWorkbook(wb, xlsx_path, overwrite = TRUE)
}

# Read a raw xlsx sheet with header cells taken verbatim (no `.`-for-space
# mangling). `openxlsx::read.xlsx(colNames = TRUE)` silently replaces spaces
# in header cells regardless of its `check.names`/`sep.names` args, which
# breaks label-based matching against issue_tracking_header_map() — reading
# with colNames = FALSE and setting names from row 1 ourselves sidesteps it.
read_xlsx_verbatim_headers <- function(path, sheet) {
    raw <- openxlsx::readWorkbook(path, sheet = sheet, colNames = FALSE)
    if (nrow(raw) < 1) return(as.data.frame(raw, stringsAsFactors = FALSE))
    hdr <- as.character(unlist(raw[1, ]))
    body <- raw[-1, , drop = FALSE]
    names(body) <- hdr
    as.data.frame(body, stringsAsFactors = FALSE, check.names = FALSE)
    }

# Blank cells come back as NA from readr (default na = c("", "NA")) but as ""
# from the xlsx path — normalize both to "" so downstream `nzchar()`/`%||%`
# checks behave the same regardless of source (nzchar(NA) is TRUE in R, so
# leaving blanks as NA would make blank-ID rows look non-blank).
blank_na_to_empty <- function(tbl) {
    as.data.frame(lapply(tbl, function(col) {
        if (!is.character(col)) col <- as.character(col)
        col[is.na(col)] <- ""
        col
    }), stringsAsFactors = FALSE, check.names = FALSE)
}

# Read the issue-tracking csv/xlsx back into internal snake_case columns.
read_issue_tracking <- function(path, sheet = "Tracking", entity_label = NA_character_, group_label = NA_character_) {
    suppressPackageStartupMessages({ library(readr); library(openxlsx) })
    ext <- tolower(tools::file_ext(path))
    raw <- if (ext == "csv") {
        as.data.frame(read_csv(path, show_col_types = FALSE), stringsAsFactors = FALSE)
    } else {
        read_xlsx_verbatim_headers(path, sheet)
    }
    normalize_issue_tracking_status(blank_na_to_empty(rename_from_issue_tracking_headers(raw, entity_label, group_label)))
}

# Incrementally merge a freshly-computed snapshot (e.g. today's
# intermediate/<date>_issue_tracking.xlsx) into the live issue_tracking.xlsx
# (`current`), preserving field/RA work rather than refreshing it:
#   - Issue ID in both -> `current`'s row is kept EXACTLY as-is, every
#     column, no refresh from the snapshot.
#   - Issue ID only in the snapshot -> genuinely new finding, appended as-is.
#   - Issue ID only in `current` -> kept (never dropped), even if the
#     underlying check no longer reproduces it this run — its resolution
#     trail lives in hfc/code/resolutions/ and data/intermediate/, but the row itself
#     stays visible in the tracking file until a human clears it.
# `current` may be NULL (first-ever run — nothing to merge against).
merge_preserve_existing <- function(current, new_snapshot) {
    if (is.null(current) || !nrow(current)) return(new_snapshot)
    new_only <- new_snapshot[!new_snapshot$finding_id %in% current$finding_id, , drop = FALSE]
    dplyr::bind_rows(current, new_only)
}

# Merge a resolutions/<date>_issues_resolution.xlsx working clone (Status/
# Corrections/Correction Author edits from a "Process HFC feedback" pass)
# back into whatever issue_tracking.xlsx currently contains (`current`) —
# in case field/RA edited something else concurrently while the agent worked:
#   - Issue ID in both -> take the CLONE's status/corrections/correction_author,
#     keep every other column from `current`.
#   - Issue ID only in `current` -> untouched by this pass, kept as-is.
#   - Issue ID only in the clone -> shouldn't normally happen (the clone is a
#     copy of a past `current`), but appended defensively rather than lost.
merge_resolution_updates <- function(current, resolution_clone) {
    if (is.null(current) || !nrow(current)) return(resolution_clone)
    update_cols <- c("status", "corrections", "correction_author")
    idx <- match(current$finding_id, resolution_clone$finding_id)
    matched <- !is.na(idx)
    merged <- current
    for (col in update_cols) {
        if (col %in% names(resolution_clone)) {
        merged[[col]][matched] <- resolution_clone[[col]][idx[matched]]
        }
    }
    clone_only <- resolution_clone[!resolution_clone$finding_id %in% current$finding_id, , drop = FALSE]
    dplyr::bind_rows(merged, clone_only)
}

# Display-only filter for a post-resolution report rebuild (scripts/rebuild_report.R):
# drops any finding whose live-tracking row has Status == "Resolved", and any
# finding whose finding_id no longer appears in the live tracking file at
# all (re-running the checks may no longer reproduce it, even if nobody
# explicitly marked it Resolved). `issue_tracking.xlsx` itself is untouched —
# this only changes what report.html shows; the tracking file keeps its full
# history exactly as merge_preserve_existing() already guarantees elsewhere.
filter_findings_by_tracking_status <- function(findings, tracking_tbl) {
    if (is.null(findings) || nrow(findings) == 0) return(findings)
    if (is.null(tracking_tbl) || nrow(tracking_tbl) == 0 || !"finding_id" %in% names(tracking_tbl)) {
        return(findings[0, , drop = FALSE])
    }
    status <- toupper(trimws(as.character(tracking_tbl$status %||% "")))
    keep_ids <- tracking_tbl$finding_id[status != "RESOLVED"]
    findings[findings$finding_id %in% keep_ids, , drop = FALSE]
}

# Module code -> plain-English label + <=3-sentence description.
# Keep in sync with references/check_modules.md ("Report display labels & descriptions").
MODULE_ORDER <- paste0("M", 1:13)

MODULE_META <- list(
    M1 = list(label = "Completion",
                desc = "Reports how many submissions are complete overall, and by group, enumerator, and date, so gaps in fieldwork show up early. By default, also flags any group whose completed-submission count falls below 50% of the target."),
    M2 = list(label = "Duplicates",
                desc = "Flags submissions that share the same unique ID or survey key, which usually means the same interview was uploaded or entered more than once."),
    M3 = list(label = "Form Version",
                desc = "Tracks which version of the survey instrument was in use on each date, and flags any submission whose recorded version doesn't match the expected window for its date."),
    M4 = list(label = "Survey Duration",
                desc = "Reports how long interviews took, in minutes, overall and by enumerator, and flags individual interviews that were unusually long or short."),
    M5 = list(label = "Irregular Timing",
                desc = "Flags interviews conducted at unusual times — weekends or outside normal working hours — using each submission's local time zone."),
    M6 = list(label = "Numeric Outliers",
                desc = "Flags unusually high or low values on key numeric questions (e.g. ages, scores) that fall outside the normal range for this survey."),
    M7 = list(label = "Missingness",
                desc = "Flags variables and enumerators with unusually high rates of missing or sentinel-coded (e.g. 99, -9999) responses on key survey questions."),
    M8 = list(label = "GPS Location",
                desc = "Flags submissions recorded far from where other submissions at that site were recorded, which can mean the interview happened somewhere unexpected."),
    M9 = list(label = "Straightlining",
                desc = "Flags enumerators who gave the same answer on a question in most of their interviews, and submissions where most ordinal/Likert-style questions share one identical value."),
    M10 = list(label = "Survey-Specific",
                desc = "Flags logic issues specific to this survey's content (for example, a mismatch between a record saying something happened and the respondent's own answer), including any custom checks requested for this project."),
    M11 = list(label = "Media Files",
                desc = "Flags problems with recorded audio/photo files: missing files, empty filename cells, unexpectedly small files, wrong file types, or duplicates."),
    M12 = list(label = "Consent & Assent",
                desc = "Flags cases missing a required consent (guardian agreement) or assent (the child's own agreement) flag, which the survey should always capture before proceeding."),
    M13 = list(label = "Summary Statistics",
                desc = "A simple reference table of mean, SD, min, max, and observation count for the survey's most important variables — overall, and broken out per enumerator.")
)

module_label <- function(code) {
    code <- as.character(code)
    vapply(code, function(x) {
        m <- MODULE_META[[x]]
        if (is.null(m)) x else m$label
    }, character(1), USE.NAMES = FALSE)
}

# `modules`: the project's confirmed modules.yaml list — when supplied and a
# dynamic builder exists for this module code (module_desc.R), the
# description states this project's actual configured thresholds instead of
# the generic static text. Falls back to the static MODULE_META desc if
# `modules` is NULL, the module has no dynamic builder, or the builder errors
# on malformed config (never let a description-string failure break the
# whole report build).
module_desc <- function(code, modules = NULL) {
    code <- as.character(code)
    m <- MODULE_META[[code]]
    static_desc <- if (is.null(m)) "" else m$desc
    if (is.null(modules)) return(static_desc)
    builder <- DYNAMIC_MODULE_DESC[[code]]
    if (is.null(builder)) return(static_desc)
    dyn <- tryCatch(builder(modules), error = function(e) NA_character_)
    if (is.na(dyn) || !nzchar(dyn)) static_desc else dyn
}

# Human-readable labels for findings$category values — used both by the "By
# category" report table and the xlsx/csv "Issue Category" export
# (findings_to_issue_tracking()). The underlying `category` field itself
# stays the raw machine value throughout findings processing; only display
# surfaces apply this. M10 custom checks use arbitrary per-project category
# strings that can't be pre-mapped here; any unmapped value falls back to a
# Title-Case-from-snake_case transform, mirroring module_label()'s graceful
# fallback to the raw code.
CATEGORY_LABELS <- c(
    low_completion = "Low completion",
    duplicates = "Duplicate submission",
    form_version_mismatch = "Form version mismatch",
    long_duration = "Interview too long",
    short_duration = "Interview too short",
    irregular_time = "Irregular interview time",
    age_outlier = "Age outlier",
    numeric_outlier = "Numeric outlier",
    high_missingness = "High missingness",
    gps_distance = "GPS distance outlier",
    straightlining_enum = "Straightlining (by enumerator)",
    straightlining_survey = "Straightlining (within submission)",
    media_column_empty = "Media column empty (all rows)",
    assent = "Missing assent",
    consent = "Missing consent",
    audio = "Missing audio consent flag"
)

category_label <- function(category) {
    category <- as.character(category)
    vapply(category, function(x) {
        lbl <- CATEGORY_LABELS[[x]]
        if (!is.null(lbl)) return(lbl)
        # Fallback for unmapped (e.g. M10 custom) categories: snake_case -> Title Case.
        words <- strsplit(gsub("_", " ", x), " ")[[1]]
        words <- ifelse(nzchar(words), paste0(toupper(substr(words, 1, 1)), substr(words, 2, nchar(words))), words)
        paste(words, collapse = " ")
    }, character(1), USE.NAMES = FALSE)
}

# Which direction counts as "worse" for a category's sort_value (see
# mk_findings()'s sort_value_col) — "asc" means smaller = worse (e.g. a very
# short interview), "desc" means larger = worse (e.g. a large GPS distance).
# Categories absent from this map have no continuous badness measure (binary/
# categorical checks like duplicates, form version, consent) and fall back to
# the old enumerator/entity-ID order untouched.
FINDING_SORT_DIRECTION <- c(
    low_completion = "asc",
    long_duration = "desc", short_duration = "asc",
    irregular_time = "desc",
    age_outlier = "desc", numeric_outlier = "desc",
    high_missingness = "desc",
    gps_distance = "desc",
    straightlining_enum = "desc", straightlining_survey = "desc"
)

# Order findings by module (M1..M13, in MODULE_ORDER), then "worst first"
# within each module's block (direction from FINDING_SORT_DIRECTION, keyed by
# category, applied to mk_findings()'s sort_value), then enumerator, then
# submission_id (entity ID), then date (most recent first) as a final
# tiebreak. Categories with no sort_value (NA) keep the old enumerator/
# entity-ID/date order, matching pre-existing behavior exactly. Blank/NA
# values in enumerator/submission_id are grouped last (they mean "not
# applicable to this check") so individually traceable rows surface first
# instead of interleaving with N/A rows.
sort_findings_for_display <- function(df) {
    if (is.null(df) || nrow(df) == 0) return(df)
    module_rank <- match(df$check_module, MODULE_ORDER)
    module_rank[is.na(module_rank)] <- length(MODULE_ORDER) + 1L
    direction <- unname(FINDING_SORT_DIRECTION[as.character(df$category)])
    sv <- if ("sort_value" %in% names(df)) suppressWarnings(as.numeric(df$sort_value)) else rep(NA_real_, nrow(df))
    has_badness <- !is.na(direction) & !is.na(sv)
    badness <- ifelse(has_badness, ifelse(direction == "asc", -sv, sv), NA_real_)
    enum <- if ("enumerator" %in% names(df)) as.character(df$enumerator) else rep("", nrow(df))
    sid  <- if ("submission_id" %in% names(df)) as.character(df$submission_id) else rep("", nrow(df))
    enum[is.na(enum)] <- ""
    sid[is.na(sid)] <- ""
    raw_date <- if ("start_date" %in% names(df) || "end_date" %in% names(df)) {
        sd <- if ("start_date" %in% names(df)) as.character(df$start_date) else rep("", nrow(df))
        ed <- if ("end_date" %in% names(df)) as.character(df$end_date) else rep("", nrow(df))
        ifelse(!is.na(sd) & nzchar(sd), sd, ed)
    } else rep(NA_character_, nrow(df))
    date_key <- suppressWarnings(as.numeric(as.Date(raw_date)))
    date_key[is.na(date_key)] <- -Inf
    ord <- order(module_rank, !has_badness, -ifelse(has_badness, badness, 0),
                 enum == "", enum, sid == "", sid, -date_key)
    df[ord, , drop = FALSE]
}

# Searchable HTML table: all rows in DOM; first `show_n` visible until search.
# Tables with fewer than TRUNCATE_THRESHOLD rows always render in full (no
# toggle). Larger tables default to `show_n` rows + a "Show all" button that
# toggles to "Show top 15" (collapsing back to a 15-row view, not `show_n`).
TRUNCATE_THRESHOLD <- 15L

html_searchable_table <- function(df, cols, table_id, show_n = 10L, col_labels = NULL) {
    esc <- function(x) {
        x <- as.character(x)
        x[is.na(x)] <- ""
        x <- gsub("&", "&amp;", x, fixed = TRUE)
        x <- gsub("<", "&lt;", x, fixed = TRUE)
        x <- gsub(">", "&gt;", x, fixed = TRUE)
        x
    }
    if (is.null(df) || nrow(df) == 0) {
        return(paste0(
        "<div class='table-wrap' id='", table_id, "-wrap'>",
        "<p class='meta'>No rows</p></div>"
        ))
    }
    cols <- intersect(cols, names(df))
    if (!length(cols)) cols <- names(df)
    truncate <- nrow(df) >= TRUNCATE_THRESHOLD
    initial_shown <- if (truncate) min(show_n, nrow(df)) else nrow(df)
    labels <- if (!is.null(col_labels)) {
        vapply(cols, function(cn) col_labels[[cn]] %||% cn, character(1))
    } else cols
    head_cells <- paste0("<th>", esc(labels), "</th>", collapse = "")
    rows <- vapply(seq_len(nrow(df)), function(i) {
        cls_parts <- c(if (truncate && i > show_n) "row-hidden")
        cls <- if (length(cls_parts)) paste0(" class='", paste(cls_parts, collapse = " "), "'") else ""
        cells <- paste0(
        vapply(cols, function(cn) paste0("<td>", esc(df[[cn]][i]), "</td>"), character(1)),
        collapse = ""
        )
        paste0("<tr", cls, ">", cells, "</tr>")
    }, character(1))
    toggle_html <- if (truncate) {
        paste0(
        "<button type='button' class='table-toggle' data-table='", table_id,
        "' data-expanded='false'>Show all</button>"
        )
    } else ""
    paste0(
        "<div class='table-wrap' data-collapsed-n='", show_n, "' id='", table_id, "-wrap'>",
        "<div class='table-toolbar'>",
        "<input type='search' class='table-search' placeholder='Search all ", nrow(df),
        " rows…' aria-label='Search table' data-table='", table_id, "' />",
        toggle_html,
        "<span class='table-count' data-for='", table_id, "'>",
        initial_shown, " of ", nrow(df), " shown</span></div>",
        "<table class='searchable' id='", table_id, "'><thead><tr>", head_cells,
        "</tr></thead><tbody>", paste(rows, collapse = "\n"),
        "</tbody></table></div>"
    )
}

# Render a module's descriptive stats (a single data.frame, or a named list
# of data.frames e.g. M1's overall/by_group/by_enumerator/by_date) as one or
# more small labeled searchable tables. Used for M1/M3/M4/M7/M13, which
# report summary statistics rather than (only) row-level findings.
#' Any column named `pct_*` gets rendered as a whole-number percentage
#' string with a literal "%" suffix (87.3 -> "87%") — module-agnostic (scans
#' for the naming pattern rather than hardcoding specific modules), so it
#' automatically covers any future pct_* column. Display-only: operates on
#' a copy, never the underlying stats data other code might still use.
format_pct_cols <- function(df) {
    pct_cols <- grep("^pct_", names(df), value = TRUE)
    for (cn in pct_cols) {
        df[[cn]] <- paste0(round(suppressWarnings(as.numeric(df[[cn]]))), "%")
    }
    df
}

# Column header labels for render_stats_block()'s tables, keyed by module —
# not one flat map, since the same column name means different things in
# different modules (e.g. `n` is "Target" in M1's completion tables but a
# plain observation count in M4/M7). Only M1 has user-specified exact
# labels; the rest get sensible Title-Case-or-better labels for their real
# columns. M13 is already Title-Case — included for uniformity.
STATS_COL_LABELS <- list(
    M1 = c(n = "Target", n_complete = "Completed surveys", pct_complete = "Completion",
            group = "Group", group_var = "Group", value = "Value",
            enumerator = "Enumerator", date = "Date"),
    M3 = c(version = "Version", n = "N", date_min = "First seen", date_max = "Last seen",
            date_start = "Window start", date_end = "Window end"),
    M4 = c(level = "Section", n = "N", mean = "Mean", median = "Median", sd = "SD",
            min = "Min", max = "Max", enumerator = "Enumerator"),
    M7 = c(variable = "Variable", pct_missing = "% Missing", n_missing = "N Missing",
            n = "Obs", enumerator = "Enumerator"),
    M13 = c(Variable = "Variable", Mean = "Mean", SD = "SD", Min = "Min", Max = "Max", Missing = "NA", Obs = "Obs")
)

STATS_BLOCK_COLLAPSE_AFTER <- 4L

# Renders one table per named element of `mod_stats` (or a single "Summary"
# table when given a bare data.frame). When there are more than
# STATS_BLOCK_COLLAPSE_AFTER non-empty entries (e.g. M13's per-enumerator
# breakdown), every entry except the first ("Overall", when present) renders
# collapsed inside a <details> with a jump-index of links at the top — a flat
# wall of 19 open tables (1 overall + 18 enumerators) isn't navigable
# otherwise. Below the threshold, every table just renders open as before.
render_stats_block <- function(mod_stats, prefix, col_labels = NULL) {
    if (is.null(mod_stats)) return("")
    esc <- function(x) {
        x <- as.character(x)
        x[is.na(x)] <- ""
        x <- gsub("&", "&amp;", x, fixed = TRUE)
        x <- gsub("<", "&lt;", x, fixed = TRUE)
        x <- gsub(">", "&gt;", x, fixed = TRUE)
        x
    }
    if (is.data.frame(mod_stats)) mod_stats <- list(Summary = mod_stats)
    present <- names(mod_stats)[vapply(mod_stats, function(df) is.data.frame(df) && nrow(df) > 0, logical(1))]
    collapse <- length(present) > STATS_BLOCK_COLLAPSE_AFTER

    index_links <- character()
    blocks <- character()
    for (nm in present) {
        df <- format_pct_cols(mod_stats[[nm]])
        tid <- paste0("tbl-", prefix, "-", tolower(gsub("[^A-Za-z0-9]+", "-", nm)))
        label <- gsub("_", " ", nm)
        label <- paste0(toupper(substr(label, 1, 1)), substr(label, 2, nchar(label)))
        table_html <- html_searchable_table(df, names(df), tid, 10L, col_labels = col_labels)
        is_first <- identical(nm, present[[1]])
        if (collapse && !is_first) {
        # NOTE: html_searchable_table() already puts id="{tid}" on the
        # <table> itself (and "{tid}-wrap" on its wrapper div) — the details
        # anchor must use a third, distinct suffix to avoid a duplicate id.
        index_links <- c(index_links, sprintf("<a href='#%s-details'>%s</a>", tid, esc(label)))
        blocks <- c(blocks, sprintf(
            "<details class='stats-details' id='%s-details'><summary>%s</summary>%s</details>",
            tid, esc(label), table_html
        ))
        } else {
        blocks <- c(blocks, paste0("<h4>", esc(label), "</h4>", table_html))
        }
    }
    idx_html <- if (length(index_links)) {
        paste0("<nav class='stats-index'>", paste(index_links, collapse = " &middot; "), "</nav>")
    } else ""
    paste0(idx_html, paste(blocks, collapse = ""))
}

# Per-CATEGORY (not per-module) display columns for the HTML report's
# findings tables — a category's granularity (an aggregate unit like an
# enumerator/site, vs. one individual submission) determines what's
# meaningful to show, independent of which module produced it. This is what
# keeps a table from carrying columns the underlying check never actually
# established (e.g. no Entity/Group column on a by-enumerator missingness
# table — mk_aggregate_finding() never populated those fields in the first
# place, see utils.R). `entity_display`/`group_display`/`enumerator_display`
# are computed once below via resolve_display_vec() (utils.R) — entity_display
# is the raw ID by default (roles$entity_display, default "id" — we never
# have the respondent's real name), group/enumerator_display resolve to
# name-if-available by default (roles$group_display/enumerator_display,
# default "name").
FINDINGS_COLS_AGGREGATE_GROUP       <- c("group_display", "issue")
FINDINGS_COLS_AGGREGATE_ENUM        <- c("enumerator_display", "issue")
FINDINGS_COLS_AGGREGATE_ENUM_VALUE  <- c("enumerator_display", "issue", "value")
FINDINGS_COLS_AGGREGATE_SURVEY      <- c("issue")
FINDINGS_COLS_ROW_BASE         <- c("entity_display", "group_display", "enumerator_display", "issue")
FINDINGS_COLS_ROW_VALUE        <- c("entity_display", "group_display", "enumerator_display", "issue", "value")
FINDINGS_COLS_ROW_VALUE_VAR    <- c("entity_display", "group_display", "enumerator_display", "issue", "value", "variable")

CATEGORY_COLS <- list(
    low_completion         = FINDINGS_COLS_AGGREGATE_GROUP,
    duplicates             = FINDINGS_COLS_ROW_BASE,
    form_version_mismatch  = FINDINGS_COLS_ROW_VALUE,
    long_duration          = FINDINGS_COLS_ROW_VALUE,
    short_duration         = FINDINGS_COLS_ROW_VALUE,
    irregular_time         = FINDINGS_COLS_ROW_VALUE,
    age_outlier            = FINDINGS_COLS_ROW_VALUE_VAR,
    numeric_outlier        = FINDINGS_COLS_ROW_VALUE_VAR,
    high_missingness       = FINDINGS_COLS_AGGREGATE_ENUM_VALUE,
    gps_distance           = FINDINGS_COLS_ROW_BASE,
    straightlining_enum    = FINDINGS_COLS_AGGREGATE_ENUM_VALUE,
    straightlining_survey  = FINDINGS_COLS_ROW_VALUE,
    media_column_empty     = FINDINGS_COLS_AGGREGATE_SURVEY,
    assent                 = FINDINGS_COLS_ROW_BASE,
    consent                = FINDINGS_COLS_ROW_BASE,
    audio                  = FINDINGS_COLS_ROW_BASE
)
# Unmatched categories (e.g. an M10 custom check's own category string)
# default to the full row-level set — a custom check is arbitrary enough
# that erring toward showing more, not less, is the safer default.
DEFAULT_FINDINGS_COLS <- FINDINGS_COLS_ROW_VALUE

# Cross-module tables (Last Day, All issues) intentionally stay ONE table
# each rather than splitting per category like render_findings_tables() —
# their whole point is a single place to scan everything at once. The
# superset column set means an aggregate-level row (e.g. a by-enumerator
# missingness finding) shows blank Entity/Group cells there — genuinely
# blank because mk_aggregate_finding() never populated them, not clutter —
# while a row-level finding shows every column that applies to it.
ALL_FINDINGS_COLS <- c("entity_display", "group_display", "enumerator_display", "issue", "value", "variable")

#' Render one or more searchable tables for `sub`'s findings, splitting into
#' separate tables whenever the categories present require different display
#' columns (e.g. one module section mixing a by-enumerator aggregate check
#' with a row-level one — M9 straightlining is the current example). Sharing
#' a single table across mismatched granularities would force either blank
#' filler columns or hidden real data, exactly the "unnecessary columns"
#' problem this whole per-category scheme exists to avoid. Categories that
#' already share identical columns stay in one table together (the common
#' case), so most modules render exactly as before — just one table.
render_findings_tables <- function(sub, id_prefix, col_labels, show_n = 10L) {
    if (is.null(sub) || nrow(sub) == 0) {
        return(html_searchable_table(sub, DEFAULT_FINDINGS_COLS, id_prefix, show_n, col_labels = col_labels))
    }
    col_sig <- vapply(sub$category, function(cg) paste(CATEGORY_COLS[[cg]] %||% DEFAULT_FINDINGS_COLS, collapse = "|"), character(1))
    sigs <- unique(col_sig)
    if (length(sigs) <= 1) {
        cols <- CATEGORY_COLS[[sub$category[[1]]]] %||% DEFAULT_FINDINGS_COLS
        return(html_searchable_table(sub, cols, id_prefix, show_n, col_labels = col_labels))
    }
    esc <- function(x) {
        x <- as.character(x); x[is.na(x)] <- ""
        x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE); x <- gsub(">", "&gt;", x, fixed = TRUE)
        x
    }
    parts <- character()
    for (i in seq_along(sigs)) {
        grp_df <- sub[col_sig == sigs[i], , drop = FALSE]
        cols <- CATEGORY_COLS[[grp_df$category[[1]]]] %||% DEFAULT_FINDINGS_COLS
        lbl <- category_label(grp_df$category[[1]])
        sub_id <- paste0(id_prefix, "-", i)
        parts <- c(parts, paste0("<h4>", esc(lbl), "</h4>"),
                    html_searchable_table(grp_df, cols, sub_id, show_n, col_labels = col_labels))
    }
    paste(parts, collapse = "")
}

SUMMARY_PLACEHOLDER_TEXT <- "Summary not yet drafted — findings are listed below by module."

# hfc/config/summary_message.md — a short, agent-drafted narrative (Slack-
# register, focused on the pressing issues: completion, duplicates,
# irregular timing, custom checks) meant to be read at a glance each morning.
# Plain free text, hand-authored directly by the agent after reviewing
# findings — NOT reusing module_notes.yaml's overrides/custom schema, since
# this is a different kind of content (a narrative message, not a per-module
# description). Falls back to a placeholder when absent/empty (e.g. the very
# first build, before the agent has seen any findings yet).
read_summary_message <- function(code_output_dir) {
    path <- hfc_path(code_output_dir, "config", "summary_message.md")
    if (!file.exists(path)) return(NA_character_)
    txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
    if (!nzchar(trimws(txt))) return(NA_character_)
    txt
}

write_html_report <- function(findings, code_output_dir, project_id, open = FALSE,
                                    roles = NULL, ds = NULL, report_cfg = NULL,
                                    module_notes = NULL, stats = NULL, modules = NULL) {
        suppressPackageStartupMessages({ library(dplyr) })
        report_dir <- hfc_path(code_output_dir, "outputs")
        dir.create(report_dir, showWarnings = FALSE, recursive = TRUE)
        html_path <- file.path(report_dir, "report.html")

        esc <- function(x) {
            x <- as.character(x)
            x[is.na(x)] <- ""
            x <- gsub("&", "&amp;", x, fixed = TRUE)
            x <- gsub("<", "&lt;", x, fixed = TRUE)
            x <- gsub(">", "&gt;", x, fixed = TRUE)
            x
        }

        # Recomputed independently here (not inherited from run_check_modules(),
        # since R data frames are copy-on-modify) so the GPS map and any other
        # ds-derived rendering can show the composite ID consistently.
        if (!is.null(ds) && !is.null(roles)) {
            ds$.hfc_id_display <- composite_id_string(ds, roles$entity_id, roles$entity_id_sep %||% " / ")
        }

        stats <- stats %||% list()
        last_date <- roles$last_date %||% NA_character_
        if (!is.null(last_date) && (is.na(last_date) || !nzchar(last_date))) last_date <- NA_character_

        # Findings tables show only the columns a field team member needs to act
        # on a flagged row — Issue ID/category/check_module stay in the xlsx/csv
        # exports but are dropped from the HTML display. Entity ID's header is
        # survey-specific (e.g. "Student ID"); which of these columns actually
        # appear on a given table is per-CATEGORY, not fixed globally — see
        # CATEGORY_COLS/render_findings_tables() above. Entity is ID-only by
        # default (roles$entity_display, default "id" — we never have the
        # respondent's real name); Group/Enumerator are each a single
        # name-if-available-else-ID column by default (roles$group_display/
        # enumerator_display, default "name"). Any of the three is a silent
        # per-project role_map.yaml override, never guessed.
        entity_label <- roles$entity_label %||% "Entity ID"
        group_label <- roles$group_label %||% "Group"
        findings_col_labels <- list(
            entity_display = entity_label, group_display = group_label,
            enumerator_display = "Enumerator", issue = "Issue", value = "Value", variable = "Variable"
        )

        # Display order only — sorted by enumerator, then submission ID, then date
        # (most recent first) wherever available; the on-disk issues.csv /
        # tracking workbook keep natural order.
        findings <- sort_findings_for_display(findings)
        findings$entity_display <- resolve_display_vec(findings$submission_id, findings$entity_name, roles$entity_display %||% "id")
        findings$group_display <- resolve_display_vec(findings$group_id, findings$group_name, roles$group_display %||% "name")
        findings$enumerator_display <- resolve_display_vec(findings$enumerator, findings$enumerator_name, roles$enumerator_display %||% "name")

        by_mod <- if (nrow(findings) && "check_module" %in% names(findings)) {
            findings %>% count(check_module, sort = TRUE)
        } else tibble(check_module = character(), n = integer())

        summary_cards <- if (nrow(by_mod)) {
            paste0(
            "<div class='cards'>",
            paste0("<div class='stat'><div class='stat-n'>", by_mod$n,
                    "</div><div class='stat-l'>", esc(module_label(by_mod$check_module)), "</div></div>",
                    collapse = ""),
            "</div>"
            )
        } else ""

        summary_msg <- read_summary_message(code_output_dir)
        summary_msg_html <- if (!is.na(summary_msg)) {
            paste0("<div class='summary-narrative'>", gsub("\n", "<br/>", esc(summary_msg), fixed = TRUE), "</div>")
        } else {
            paste0("<div class='summary-narrative summary-placeholder'><em>", esc(SUMMARY_PLACEHOLDER_TEXT), "</em></div>")
        }

        # Per-module sections. A module appears if it produced row-level findings
        # OR non-empty descriptive stats (M13 Summary Statistics never produces
        # findings rows at all; M1/M3/M4/M7 can have stats with zero findings).
        present_from_findings <- if (nrow(findings) && "check_module" %in% names(findings)) {
            unique(findings$check_module)
        } else character()
        stats_nonempty <- function(s) {
            if (is.null(s)) return(FALSE)
            if (is.data.frame(s)) return(nrow(s) > 0)
            if (is.list(s)) return(any(vapply(s, function(x) is.data.frame(x) && nrow(x) > 0, logical(1))))
            FALSE
        }
        present_from_stats <- names(stats)[vapply(stats, stats_nonempty, logical(1))]
        modules_present <- intersect(MODULE_ORDER, union(present_from_findings, present_from_stats))
        # M13 Summary Statistics is a reference table, not an issue list — push it
        # last among module sections, immediately before "All issues", instead of
        # its numeric M1..M13 slot.
        modules_present <- c(setdiff(modules_present, "M13"), intersect(modules_present, "M13"))

        mod_sections <- character()
        nav_links <- c('<a href="#about">About</a>', '<a href="#summary">Summary</a>')
        if (!is.na(last_date)) nav_links <- c(nav_links, '<a href="#lastday">Last Day</a>')

        for (mod in modules_present) {
            sub <- findings %>% filter(check_module == mod)
            aid <- paste0("mod-", tolower(mod))
            nav_links <- c(nav_links, sprintf(
            '<a href="#%s">%s <sup class="mod-code">%s</sup></a>', aid, esc(module_label(mod)), esc(mod)
            ))
            desc_override <- module_notes$overrides[[mod]]
            desc_text <- if (!is.null(desc_override) && nzchar(desc_override)) desc_override else module_desc(mod, modules)
            desc_html <- if (nzchar(desc_text)) paste0("<p class='mod-desc'>", esc(desc_text), "</p>") else ""
            custom_html <- ""
            if (identical(mod, "M10") && length(module_notes$custom)) {
            items <- vapply(names(module_notes$custom), function(nm) {
                entry <- module_notes$custom[[nm]]
                lbl <- entry$label %||% nm
                d <- entry$description %||% ""
                paste0("<li><strong>", esc(lbl), "</strong> — ", esc(d), "</li>")
            }, character(1))
            custom_html <- paste0(
                "<div class='custom-checks'><h3>Custom checks for this survey</h3><ul>",
                paste(items, collapse = ""), "</ul></div>"
            )
            }
            stats_html <- render_stats_block(stats[[mod]], tolower(mod), col_labels = STATS_COL_LABELS[[mod]])
            # M13 Summary Statistics never has findings rows — skip the (always-empty,
            # otherwise-misleading) findings table and "N issues found" count for it.
            is_stats_only <- identical(mod, "M13")
            heading_suffix <- if (is_stats_only) "" else paste0(" · ", nrow(sub), " issues found")
            tbl <- if (is_stats_only) "" else render_findings_tables(
            sub, paste0("tbl-", aid), findings_col_labels
            )
            mod_sections <- c(mod_sections, paste0(
            "<section id='", aid, "' class='card'><h2>", esc(module_label(mod)),
            " <span class='mod-code'>", esc(mod), "</span>", heading_suffix,
            "</h2>", desc_html, custom_html, stats_html, tbl, "</section>"
            ))
        }

        # GPS map
        map_html <- ""
        map_focus <- tolower(as.character(report_cfg$map_focus %||% "country"))
        has_gps <- !is.null(roles) && isTRUE(roles$has_gps) && !is.null(ds) &&
            !is.na(roles$x) && !is.na(roles$y) &&
            roles$x %in% names(ds) && roles$y %in% names(ds)
        if (has_gps) {
            nav_links <- c(nav_links, '<a href="#map">Map</a>')
            xx <- safe_num(ds[[roles$x]])
            yy <- safe_num(ds[[roles$y]])
            ok <- is.finite(xx) & is.finite(yy)
            # Cap points for browser performance
            idx <- which(ok)
            if (length(idx) > 2000) idx <- sample(idx, 2000)
            ids <- if (".hfc_id_display" %in% names(ds)) {
            ds$.hfc_id_display[idx]
            } else rep("", length(idx))
            ids[is.na(ids)] <- ""
            flagged_ids <- unique(findings$submission_id[findings$check_module == "M8"])
            flagged <- ids %in% flagged_ids & nzchar(ids)
            pts_json <- as.character(jsonlite::toJSON(
            data.frame(lat = yy[idx], lon = xx[idx], id = ids, flagged = flagged, stringsAsFactors = FALSE),
            dataframe = "rows", auto_unbox = TRUE
            ))
            pts_json <- gsub("</script", "<\\/script", pts_json, fixed = TRUE)
            # Focus zoom defaults
            zoom <- switch(map_focus, world = 2, city = 11, country = 6, 6)
            center_lat <- if (length(idx)) median(yy[idx], na.rm = TRUE) else 0
            center_lon <- if (length(idx)) median(xx[idx], na.rm = TRUE) else 0
            map_html <- paste0(
            "<section id='map' class='card'><h2>GPS map</h2>",
            "<p class='meta'>Focus: ", esc(map_focus), " · ", length(idx),
            " points (sampled if &gt;2000). Coordinates from ", esc(roles$x), " / ",
            esc(roles$y), ". All points are shown; points flagged by GPS Location ",
            "(M8) are red. Click a point to see its unique ID.</p>",
            "<div id='gps-map' style='height:420px;border-radius:8px;'></div>",
            "<link rel='stylesheet' href='https://unpkg.com/leaflet@1.9.4/dist/leaflet.css'/>",
            "<script src='https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'></script>",
            "<script>(function(){",
            "var map=L.map('gps-map').setView([", center_lat, ",", center_lon, "],", zoom, ");",
            "L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{",
            "attribution:'&copy; OpenStreetMap'}).addTo(map);",
            "var pts=", pts_json, ";",
            "var latlngs=pts.map(function(p){return [p.lat,p.lon];});",
            "pts.forEach(function(p){",
            "L.circleMarker([p.lat,p.lon],{radius:3,color:p.flagged?'#c0392b':'#2a6f5e',fillOpacity:0.7})",
            ".bindPopup('ID: '+(p.id||'(none)')).addTo(map);",
            "});",
            "if(latlngs.length){map.fitBounds(latlngs,{padding:[20,20]});}",
            "})();</script></section>"
            )
    }

    # Last Day tab — every finding from the most recent day of data collection,
    # across all modules, for quick triage. M11 media findings folded into the
    # generic per-module loop above, same as every other module.
    lastday_html <- ""
    if (!is.na(last_date)) {
        last_day_f <- if (nrow(findings)) {
        findings %>% filter(start_date == last_date | end_date == last_date)
        } else findings
        lastday_html <- paste0(
        "<section id='lastday' class='card'><h2>Last Day — ", esc(last_date), "</h2>",
        "<p class='mod-desc'>Every issue from the most recent day of data collection, across all modules — ",
        "a quick way to see what's most urgent.</p>",
        html_searchable_table(
            last_day_f,
            ALL_FINDINGS_COLS,
            "tbl-lastday", 15L,
            col_labels = findings_col_labels
        ),
        "</section>"
        )
    }

    nav_links <- c(nav_links, '<a href="#all">All issues</a>')
    all_tbl <- html_searchable_table(
        findings,
        ALL_FINDINGS_COLS,
        "tbl-all", 10L,
        col_labels = findings_col_labels
    )

    # "About this dashboard" — orientation + glossary, always first. Only the
    # terms that can actually appear given which modules are on are shown
    # (e.g. no "Consent"/"Assent" entry when M12 is off) — a glossary entry for
    # a term the report never uses is exactly the kind of unnecessary
    # information this redesign is about cutting.
    glossary_all <- list(
        Finding = c("Finding", "One flagged row: a single thing that looks off in one submission (or one enumerator/site) and may be worth a closer look."),
        Category = c("Category", "A short label grouping similar findings together, e.g. \"irregular_time\" or \"gps_distance\"."),
        Consent = c("Consent", "The guardian or head-of-household's agreement for the interview to take place."),
        Assent = c("Assent", "The child's own agreement to participate — separate from, and in addition to, a guardian's consent."),
        Enumerator = c("Enumerator", "The field staff member who conducted the interview."),
        Duplicate = c("Duplicate ID / key", "Two or more submissions sharing the same unique ID (or ID combination) or survey key, usually meaning one interview was captured twice."),
        Outlier = c("Outlier", "A value far outside the typical range for that question — possibly a data-entry slip, possibly a genuinely unusual case."),
        Straightlining = c("Straightlining", "Giving the same answer choice repeatedly instead of varying answers — by one enumerator across surveys, or within one survey's set of similar questions."),
        LastDay = c("Last day", "The most recent date of data collection, confirmed at setup, collected in its own Last Day tab.")
    )
    glossary_keys <- c(
        "Finding", "Category",
        if ("M12" %in% modules_present) c("Consent", "Assent"),
        "Enumerator",
        if ("M2" %in% modules_present) "Duplicate",
        if ("M6" %in% modules_present) "Outlier",
        if ("M9" %in% modules_present) "Straightlining",
        if (!is.na(last_date)) "LastDay"
    )
    glossary_terms <- glossary_all[glossary_keys]
    glossary_html <- paste0(
        "<dl class='glossary'>",
        paste0(vapply(glossary_terms, function(t) paste0(
        "<dt>", esc(t[1]), "</dt><dd>", esc(t[2]), "</dd>"
        ), character(1)), collapse = ""),
        "</dl>"
    )
    about_html <- paste0(
        "<section id='about' class='card'><h2>About this dashboard</h2>",
        "<p>This report is a first read of the data, not a verdict. The tables below", 
        "are not necessarily proof that something is wrong, but results of an analysis", 
        "that can be reviewed BUT is first AI-assisted (to err is also AI). Use the search box (or ",
        "\"Show all\") in any table to look up a specific submission, enumerator, or value.</p>",
        "<p><strong>Terms you'll see:</strong></p>",
        glossary_html,
        "</section>"
    )

    html <- paste0(
        "<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'/>",
        "<meta name='viewport' content='width=device-width, initial-scale=1'/>",
        "<title>HFC FieldLoop — HFC Checks</title>",
        "<style>
:root{--bg:#f4efe6;--ink:#1c1914;--muted:#5c564c;--card:#fffdf8;--line:#ddd4c4;--accent:#2a6f5e;--nav:#1a222c}
*{box-sizing:border-box}
body{margin:0;font-family:'Source Serif 4',Georgia,serif;background:var(--bg);color:var(--ink);line-height:1.45}
header.nav{position:sticky;top:0;z-index:50;background:var(--nav);color:#e7eef5;
  display:flex;flex-wrap:wrap;gap:.75rem 1.1rem;align-items:center;
  padding:.7rem 1.25rem;border-bottom:1px solid #2d3a47}
header.nav .brand{font-weight:600;letter-spacing:.02em;margin-right:.5rem}
header.nav a{color:#c9d6e2;text-decoration:none;font-family:'IBM Plex Sans',system-ui,sans-serif;font-size:.88rem}
header.nav a:hover{color:#fff}
main{max-width:1100px;margin:0 auto;padding:1.5rem 1.25rem 3rem}
h1{font-size:clamp(1.6rem,3vw,2.1rem);margin:.2rem 0 .35rem}
.meta{color:var(--muted);font-size:.95rem}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:1rem 1.2rem;margin:1.1rem 0}
.cards{display:flex;flex-wrap:wrap;gap:.75rem;margin:1rem 0}
.stat{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:.7rem 1rem;min-width:5.5rem}
.stat-n{font-size:1.35rem;font-weight:700;color:var(--accent)}
.stat-l{font-size:.8rem;color:var(--muted);font-family:'IBM Plex Sans',system-ui,sans-serif}
.table-toolbar{display:flex;flex-wrap:wrap;gap:.6rem;align-items:center;margin:0 0 .6rem}
.table-search{flex:1;min-width:12rem;padding:.45rem .65rem;border:1px solid var(--line);border-radius:6px;
  font-family:'IBM Plex Sans',system-ui,sans-serif;font-size:.9rem}
.table-count{font-size:.82rem;color:var(--muted);font-family:'IBM Plex Sans',system-ui,sans-serif}
.table-toggle{padding:.4rem .75rem;border:1px solid var(--accent);border-radius:6px;background:#fff;
  color:var(--accent);font-family:'IBM Plex Sans',system-ui,sans-serif;font-size:.82rem;font-weight:600;cursor:pointer}
.table-toggle:hover{background:var(--accent);color:#fff}
table.searchable{border-collapse:collapse;width:100%;background:#fff;font-size:.9rem}
table.searchable th,table.searchable td{border:1px solid var(--line);padding:.4rem .55rem;text-align:left;vertical-align:top}
table.searchable th{background:#ebe3d4;font-family:'IBM Plex Sans',system-ui,sans-serif;font-weight:600}
tr.row-hidden{display:none}
tr.match-show{display:table-row}
.mod-code{font-size:.68rem;color:var(--muted);font-family:'IBM Plex Sans',system-ui,sans-serif;
  font-weight:400;margin-left:.35rem;vertical-align:middle}
h2 .mod-code{font-size:.62rem;border:1px solid var(--line);border-radius:4px;padding:.05rem .35rem}
.mod-desc{color:var(--muted);font-size:.95rem;margin:.15rem 0 .9rem}
.card h4{font-size:.85rem;font-family:'IBM Plex Sans',system-ui,sans-serif;font-weight:600;
  color:var(--muted);margin:1rem 0 .35rem;text-transform:uppercase;letter-spacing:.03em}
dl.glossary{display:grid;grid-template-columns:max-content 1fr;gap:.25rem 1rem;margin:.4rem 0 0}
dl.glossary dt{font-weight:600;font-family:'IBM Plex Sans',system-ui,sans-serif;font-size:.9rem}
dl.glossary dd{margin:0 0 .5rem;color:var(--muted);font-size:.9rem}
.custom-checks{margin:.4rem 0 1rem;padding:.6rem .8rem;background:#f7f1e4;border:1px solid var(--line);border-radius:8px}
.custom-checks h3{margin:0 0 .3rem;font-size:.95rem;font-family:'IBM Plex Sans',system-ui,sans-serif}
.custom-checks ul{margin:0;padding-left:1.1rem}
.custom-checks li{margin:.25rem 0;color:var(--muted);font-size:.9rem}
.summary-narrative{margin:.4rem 0 1rem;padding:.75rem 1rem;background:var(--card);border-left:4px solid var(--accent, #3d9a7a);border-radius:6px;line-height:1.5}
.summary-placeholder{color:var(--muted);border-left-color:var(--line)}
.stats-index{margin:.3rem 0 .8rem;font-size:.85rem;color:var(--muted)}
.stats-index a{color:var(--accent);text-decoration:none}
.stats-index a:hover{text-decoration:underline}
details.stats-details{margin:.5rem 0}
details.stats-details summary{cursor:pointer;font-weight:600;padding:.3rem 0;font-family:'IBM Plex Sans',system-ui,sans-serif}
footer.note{margin-top:1.5rem;color:var(--muted);font-size:.9rem}
</style>
<link href='https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;600&family=Source+Serif+4:opsz,wght@8..60,500;8..60,700&display=swap' rel='stylesheet'/>
</head><body>",
    "<header class='nav'><span class='brand'>FieldLoop</span>",
    paste(nav_links, collapse = " "),
    "</header><main>",
    "<h1>HFC Checks</h1>",
    "<p class='meta'>Generated ", Sys.Date(), " · ", nrow(findings), " issues found · ",
    dplyr::n_distinct(findings$category), " categories</p>",
    about_html,
    "<section id='summary' class='card'><h2>Summary</h2>", summary_msg_html,
    "<h3>By category</h3>", summary_cards, "</section>",
    lastday_html,
    paste(mod_sections, collapse = "\n"),
    map_html,
    "<section id='all' class='card'><h2>All issues</h2>", all_tbl, "</section>",
    "<p class='note footer'>Field edits go in the shared <code>issue_tracking.xlsx</code> in your ",
    "OneDrive-synced folder (see <code>hfc-fieldloop/config.json</code>). When ready, say ",
    "<strong>Process HFC feedback</strong>.</p>",
    "</main>",
    "<script>
(function(){
  function applySearch(input){
    var id=input.getAttribute('data-table');
    var table=document.getElementById(id);
    if(!table) return;
    var wrap=document.getElementById(id+'-wrap');
    var btn=document.querySelector('.table-toggle[data-table=\"'+id+'\"]');
    var expanded=btn && btn.getAttribute('data-expanded')==='true';
    var showN=wrap?parseInt(wrap.getAttribute('data-collapsed-n')||'10',10):10;
    var q=(input.value||'').toLowerCase().trim();
    var rows=[].slice.call(table.tBodies[0].rows);
    var shown=0;
    rows.forEach(function(tr,i){
      var text=tr.textContent.toLowerCase();
      var visible;
      if(q){
        visible=text.indexOf(q)!==-1;
        tr.classList.toggle('match-show', visible);
      } else {
        tr.classList.remove('match-show');
        visible=expanded || i<showN;
      }
      tr.classList.toggle('row-hidden', !visible);
      if(visible) shown++;
    });
    var count=document.querySelector('.table-count[data-for=\"'+id+'\"]');
    if(count) count.textContent=shown+' of '+rows.length+(q?' matching':' shown');
  }
  document.querySelectorAll('.table-search').forEach(function(inp){
    inp.addEventListener('input', function(){ applySearch(inp); });
  });
  document.querySelectorAll('.table-toggle').forEach(function(btn){
    btn.addEventListener('click', function(){
      var id=btn.getAttribute('data-table');
      var wrap=document.getElementById(id+'-wrap');
      var expanded=btn.getAttribute('data-expanded')==='true';
      if(expanded){
        btn.setAttribute('data-expanded','false');
        btn.textContent='Show all';
        if(wrap) wrap.setAttribute('data-collapsed-n','15');
      } else {
        btn.setAttribute('data-expanded','true');
        btn.textContent='Show top 15';
      }
      var input=document.querySelector('.table-search[data-table=\"'+id+'\"]');
      if(input){ input.value=''; applySearch(input); }
    });
  });
  function openDetailsTarget(){
    var h=location.hash;
    if(!h) return;
    var el=document.querySelector(h);
    if(el && el.tagName==='DETAILS'){ el.open=true; el.scrollIntoView(); }
  }
  window.addEventListener('hashchange', openDetailsTarget);
  window.addEventListener('DOMContentLoaded', openDetailsTarget);
  openDetailsTarget();
})();
</script>",
    "</body></html>"
  )
  writeLines(html, html_path)

  if (isTRUE(open) && !identical(Sys.getenv("CI"), "true") &&
      !identical(Sys.getenv("FIELDLOOP_NO_OPEN"), "1")) {
    try(utils::browseURL(html_path), silent = TRUE)
  }
  normalizePath(html_path)
}

ensure_project_dirs <- function(code_output_dir) {
    hfc <- hfc_root(code_output_dir)
    for (d in c("config", "instruments", "outputs", "code")) {
        dir.create(file.path(hfc, d), recursive = TRUE, showWarnings = FALSE)
    }
    dir.create(file.path(hfc, "code", "checks"), recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(hfc, "code", "resolutions"), recursive = TRUE, showWarnings = FALSE)
}

# Module code -> its check_templates/ filename (M10 excluded: fully
# agent-authored per project, nothing to copy).
CHECK_TEMPLATE_FILES <- c(
    M1 = "M1_completion.R", M2 = "M2_duplicates.R", M3 = "M3_form_version.R",
    M4 = "M4_duration.R", M5 = "M5_date_issues.R", M6 = "M6_outliers.R",
    M7 = "M7_missingness.R", M8 = "M8_gps.R", M9 = "M9_straightlining.R",
    M11 = "M11_media.R", M12 = "M12_consent.R", M13 = "M13_sumstats.R"
)

#' For every confirmed-on module, copy its real, runnable check_templates/
#' script into hfc/code/checks/<name>.R with the project path substituted —
#' same copy-and-substitute convention as write_main_r()/assets/main.R.
#' Running the copied file standalone reproduces that module's findings.
write_check_scripts <- function(code_output_dir, modules, skill_dir = NULL) {
    checks_dir <- hfc_path(code_output_dir, "code", "checks")
    dir.create(checks_dir, showWarnings = FALSE, recursive = TRUE)
    if (is.null(skill_dir) || is.na(skill_dir)) {
        stop("write_check_scripts() requires skill_dir — the caller must resolve it (see .resolve_skill() in each CLI script).")
    }
    tmpl_dir <- file.path(skill_dir, "assets", "check_templates")

    on_codes <- names(CHECK_TEMPLATE_FILES)[
        vapply(names(CHECK_TEMPLATE_FILES), function(m) isTRUE(modules[[m]]$on), logical(1))
    ]

    # Wipe stale generated scripts (identified by their auto-generated
    # "# HFC FieldLoop generated check: " first-line marker, not filename
    # alone, so a file the user renamed/repurposed into something custom is
    # never touched) for any module no longer confirmed on. Agent-authored
    # M10 custom-check files (no marker) are never touched either way.
    for (f in list.files(checks_dir, pattern = "\\.R$", full.names = TRUE)) {
        first_line <- tryCatch(readLines(f, n = 1, warn = FALSE), error = function(e) "")
        if (length(first_line) && startsWith(first_line, "# HFC FieldLoop generated check: ")) {
        mod_in_file <- sub("^# HFC FieldLoop generated check: ", "", first_line)
        if (!mod_in_file %in% on_codes) file.remove(f)
        }
    }

    for (m in on_codes) {
        fname <- CHECK_TEMPLATE_FILES[[m]]
        tmpl <- file.path(tmpl_dir, fname)
        if (!file.exists(tmpl)) next
        lines <- readLines(tmpl, warn = FALSE)
        lines <- sub('skill <- "your/path/to/hfc-fieldloop/"',
        sprintf('skill <- "%s"', normalizePath(skill_dir)), lines, fixed = TRUE)
        lines <- sub('code_output_dir <- "your/path/to/hfc/output/"',
        sprintf('code_output_dir <- "%s"', normalizePath(code_output_dir)), lines, fixed = TRUE)
        writeLines(lines, file.path(checks_dir, fname))
    }
}

write_main_r <- function(code_output_dir, skill_dir = NULL) {
    dir.create(hfc_path(code_output_dir, "code"), showWarnings = FALSE, recursive = TRUE)
    dest <- hfc_path(code_output_dir, "code", "main.R")
    if (is.null(skill_dir) || is.na(skill_dir)) {
        stop("write_main_r() requires skill_dir — the caller must resolve it (see .resolve_skill() in each CLI script).")
    }
    tmpl <- file.path(skill_dir, "assets", "main.R")
    if (file.exists(tmpl)) {
        lines <- readLines(tmpl, warn = FALSE)
        lines <- sub('skill <- "your/path/to/hfc-fieldloop/"',
        sprintf('skill <- "%s"', normalizePath(skill_dir)), lines, fixed = TRUE)
        lines <- sub('code_output_dir <- "your/path/to/hfc/output/"',
        sprintf('code_output_dir <- "%s"', normalizePath(code_output_dir)), lines, fixed = TRUE)
        writeLines(lines, dest)
    } else {
        # Defensive fallback only — assets/main.R should always exist; this
        # path is effectively unreachable in a normal install.
        writeLines(c(
        "# HFC FieldLoop — two path globals",
        sprintf('skill <- "%s"', normalizePath(skill_dir)),
        sprintf('code_output_dir <- "%s"', normalizePath(code_output_dir)),
        'hfc <- file.path(code_output_dir, "hfc")',
        "# Rscript file.path(skill, \"scripts\", \"run_setup_build.R\")",
        "# Rscript file.path(skill, \"scripts\", \"apply_feedback.R\") \"clone\""
        ), dest)
    }
}
