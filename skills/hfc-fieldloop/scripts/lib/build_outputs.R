# Build tracking workbook, HTML report, feedback twin, project scaffold under hfc/.

feedback_required_cols <- function() {
  c("finding_id", "submission_id", "issue",
    "field_comment", "proposed_fix", "status", "resolved",
    "initials", "date_updated", "school_id", "enumerator", "key", "value", "notes")
}

findings_to_feedback <- function(findings) {
  suppressPackageStartupMessages({ library(dplyr); library(tibble) })
  if (nrow(findings) == 0) {
    return(as_tibble(setNames(rep(list(character()), length(feedback_required_cols())),
                              feedback_required_cols())))
  }
  findings %>%
    transmute(
      finding_id,
      submission_id = submission_id,
      issue,
      field_comment = "",
      proposed_fix = "",
      status = "Open",
      resolved = "No",
      initials = "",
      date_updated = "",
      school_id = school_id %||% "",
      enumerator = enumerator %||% "",
      key = key %||% "",
      value = value %||% "",
      notes = ""
    )
}

#' Normalize legacy ra_status → status; ensure Open/No defaults.
normalize_feedback_status <- function(fb) {
  fb <- as.data.frame(fb, stringsAsFactors = FALSE)
  if ("ra_status" %in% names(fb) && !"status" %in% names(fb)) {
    fb$status <- fb$ra_status
    fb$ra_status <- NULL
  }
  if (!"status" %in% names(fb)) fb$status <- "Open"
  fb$status[is.na(fb$status) | !nzchar(as.character(fb$status))] <- "Open"
  # Title-case Open if lowercase open
  fb$status[tolower(as.character(fb$status)) == "open"] <- "Open"
  if (!"resolved" %in% names(fb)) fb$resolved <- "No"
  fb$resolved[is.na(fb$resolved) | !nzchar(as.character(fb$resolved))] <- "No"
  fb$resolved[tolower(as.character(fb$resolved)) == "no"] <- "No"
  # Drop check_module from feedback twin if present
  fb$check_module <- NULL
  fb
}

write_tracking_xlsx <- function(findings, path) {
  suppressPackageStartupMessages({ library(openxlsx); library(dplyr) })
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  wb <- createWorkbook()
  addWorksheet(wb, "Tracking Sheet")
  track <- findings %>%
    transmute(
      `Today's Date` = as.character(Sys.Date()),
      `Submission ID` = submission_id,
      `School ID` = school_id,
      enumerator = enumerator,
      startdate = start_date,
      enddate = end_date,
      Issue = issue,
      finding_id, check_id, check_module, category, key, value
    )
  writeData(wb, "Tracking Sheet", track)

  tab_map <- list(
    "Schools_LowCompletion" = "low_completion",
    "Child assent audit" = "assent",
    "Parental consent audit" = "consent",
    "Student enrolment" = "enrolment",
    "GPS distance" = "gps_distance",
    "Cognitive outliers" = "cognitive_outlier",
    "Irregular timing" = "irregular_time",
    "Straightlining (enumerator)" = "straightlining_enum",
    "Straightlining (survey)" = "straightlining_survey",
    "High missingness" = "high_missingness",
    "Form version mismatch" = "form_version_mismatch"
  )
  for (nm in names(tab_map)) {
    addWorksheet(wb, nm)
    writeData(wb, nm, findings %>% filter(category == tab_map[[nm]]))
  }
  saveWorkbook(wb, path, overwrite = TRUE)
}

write_feedback_twin <- function(feedback, findings, xlsx_path, csv_path) {
  suppressPackageStartupMessages({ library(openxlsx); library(readr) })
  feedback <- normalize_feedback_status(feedback)
  # Ensure column order
  cols <- feedback_required_cols()
  for (c in cols) if (!c %in% names(feedback)) feedback[[c]] <- ""
  feedback <- feedback[, intersect(cols, names(feedback)), drop = FALSE]

  dir.create(dirname(csv_path), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(xlsx_path), recursive = TRUE, showWarnings = FALSE)
  write_csv(feedback, csv_path)
  wb <- createWorkbook()
  addWorksheet(wb, "Feedback")
  writeData(wb, "Feedback", feedback)
  if (!is.null(findings) && nrow(findings) > 0) {
    addWorksheet(wb, "Findings")
    writeData(wb, "Findings", findings)
  }
  addWorksheet(wb, "Instructions")
  writeData(wb, "Instructions", data.frame(
    step = 1:5,
    action = c(
      "Field: fill field_comment and proposed_fix",
      "RA: set status to accepted | revise | Open",
      "RA: set initials and date_updated",
      "Leave resolved=No until post-feedback pipeline runs",
      "When ready in chat: Process HFC feedback"
    )
  ))
  saveWorkbook(wb, xlsx_path, overwrite = TRUE)
}

#' Module code -> plain-English label + <=3-sentence description.
#' Keep in sync with references/check_modules.md ("Report display labels & descriptions").
MODULE_ORDER <- paste0("M", 1:13)

MODULE_META <- list(
  M1 = list(label = "Completion",
            desc = "Reports how many submissions are complete overall, and by group, enumerator, and date, so gaps in fieldwork show up early. Can also flag sites whose completion falls far below the survey median."),
  M2 = list(label = "Duplicates",
            desc = "Flags submissions that share the same unique ID or survey key, which usually means the same interview was uploaded or entered more than once."),
  M3 = list(label = "Form Version",
            desc = "Tracks which version of the survey instrument was in use on each date, and flags any submission whose recorded version doesn't match the expected window for its date."),
  M4 = list(label = "Survey Duration",
            desc = "Reports how long interviews took overall and by enumerator, and flags individual interviews that were unusually long or short."),
  M5 = list(label = "Irregular Timing",
            desc = "Flags interviews conducted at unusual times — weekends or outside normal working hours — using each submission's local time zone."),
  M6 = list(label = "Numeric Outliers",
            desc = "Flags unusually high or low values on key numeric questions (e.g. ages, scores) that fall outside the normal range for this survey."),
  M7 = list(label = "Missingness",
            desc = "Flags variables and enumerators with unusually high rates of missing or sentinel-coded (e.g. 99, -9999) responses on key survey questions."),
  M8 = list(label = "GPS Location",
            desc = "Flags submissions recorded far from where that school/site's other submissions were recorded, which can mean the interview happened somewhere unexpected."),
  M9 = list(label = "Straightlining",
            desc = "Flags enumerators who gave the same answer on a question in most of their interviews, and submissions where most ordinal/Likert-style questions share one identical value."),
  M10 = list(label = "Summary Statistics",
            desc = "A simple reference table of mean, SD, min, max, and observation count for the survey's most important numeric variables."),
  M11 = list(label = "Survey-Specific",
            desc = "Flags logic issues specific to this survey's content (for example, a mismatch between a record saying something happened and the respondent's own answer), including any custom checks requested for this project."),
  M12 = list(label = "Media Files",
            desc = "Flags problems with recorded audio/photo files: missing files, empty filename cells, unexpectedly small files, wrong file types, or duplicates."),
  M13 = list(label = "Consent & Assent",
            desc = "Flags cases missing a required consent (guardian agreement) or assent (the child's own agreement) flag, which the survey should always capture before proceeding.")
)

module_label <- function(code) {
  code <- as.character(code)
  vapply(code, function(x) {
    m <- MODULE_META[[x]]
    if (is.null(m)) x else m$label
  }, character(1), USE.NAMES = FALSE)
}

module_desc <- function(code) {
  m <- MODULE_META[[as.character(code)]]
  if (is.null(m)) "" else m$desc
}

#' Order findings by enumerator, then submission_id, then date (most recent
#' first), for display. Blank/NA values in enumerator/submission_id are
#' grouped last (they mean "not applicable to this check") so individually
#' traceable rows surface first instead of interleaving with N/A rows.
sort_findings_for_display <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
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
  ord <- order(enum == "", enum, sid == "", sid, -date_key)
  df[ord, , drop = FALSE]
}

#' Searchable HTML table: all rows in DOM; first `show_n` visible until search.
#' Tables with fewer than TRUNCATE_THRESHOLD rows always render in full (no
#' toggle). Larger tables default to `show_n` rows + a "Show all" button that
#' toggles to "Show top 15" (collapsing back to a 15-row view, not `show_n`).
TRUNCATE_THRESHOLD <- 15L

html_searchable_table <- function(df, cols, table_id, show_n = 10L, bold_date = NA_character_) {
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
  head_cells <- paste0("<th>", esc(cols), "</th>", collapse = "")
  has_bold_date <- !is.na(bold_date) && nzchar(bold_date) &&
    any(c("start_date", "end_date") %in% names(df))
  sd_col <- if ("start_date" %in% names(df)) as.character(df$start_date) else rep(NA_character_, nrow(df))
  ed_col <- if ("end_date" %in% names(df)) as.character(df$end_date) else rep(NA_character_, nrow(df))
  rows <- vapply(seq_len(nrow(df)), function(i) {
    is_bold <- has_bold_date && (identical(sd_col[i], bold_date) || identical(ed_col[i], bold_date))
    cls_parts <- c(if (truncate && i > show_n) "row-hidden", if (is_bold) "row-bold")
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

#' Render a module's descriptive stats (a single data.frame, or a named list
#' of data.frames e.g. M1's overall/by_group/by_enumerator/by_date) as one or
#' more small labeled searchable tables. Used for M1/M3/M4/M7/M10, which
#' report summary statistics rather than (only) row-level findings.
render_stats_block <- function(mod_stats, prefix) {
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
  blocks <- character()
  for (nm in names(mod_stats)) {
    df <- mod_stats[[nm]]
    if (is.null(df) || !is.data.frame(df) || !nrow(df)) next
    tid <- paste0("tbl-", prefix, "-", tolower(gsub("[^A-Za-z0-9]+", "-", nm)))
    label <- gsub("_", " ", nm)
    label <- paste0(toupper(substr(label, 1, 1)), substr(label, 2, nchar(label)))
    blocks <- c(blocks, paste0(
      "<h4>", esc(label), "</h4>",
      html_searchable_table(df, names(df), tid, 10L)
    ))
  }
  paste(blocks, collapse = "")
}

write_html_report <- function(findings, project_root, project_id, open = FALSE,
                              roles = NULL, ds = NULL, report_cfg = NULL,
                              module_notes = NULL, stats = NULL) {
  suppressPackageStartupMessages({ library(dplyr) })
  report_dir <- hfc_path(project_root, "report")
  dir.create(report_dir, showWarnings = FALSE, recursive = TRUE)
  html_path <- file.path(report_dir, "index.html")

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
    ds$.hfc_id_display <- composite_id_string(ds, roles$id, roles$id_sep %||% " / ")
  }

  stats <- stats %||% list()
  last_date <- roles$last_date %||% NA_character_
  if (!is.null(last_date) && (is.na(last_date) || !nzchar(last_date))) last_date <- NA_character_

  # Display order only — sorted by enumerator, then submission ID, then date
  # (most recent first) wherever available; the on-disk findings.csv /
  # tracking workbook keep natural order.
  findings <- sort_findings_for_display(findings)

  by_cat <- if (nrow(findings)) findings %>% count(category, sort = TRUE) else
    tibble(category = character(), n = integer())
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

  cat_table <- html_searchable_table(by_cat, c("category", "n"), "tbl-cats", 10L)

  # Per-module sections. A module appears if it produced row-level findings
  # OR non-empty descriptive stats (M10 Summary Statistics never produces
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
    desc_text <- if (!is.null(desc_override) && nzchar(desc_override)) desc_override else module_desc(mod)
    desc_html <- if (nzchar(desc_text)) paste0("<p class='mod-desc'>", esc(desc_text), "</p>") else ""
    custom_html <- ""
    if (identical(mod, "M11") && length(module_notes$custom)) {
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
    stats_html <- render_stats_block(stats[[mod]], tolower(mod))
    # M10 Summary Statistics never has findings rows — skip the (always-empty,
    # otherwise-misleading) findings table and "N findings" count for it.
    is_stats_only <- identical(mod, "M10")
    heading_suffix <- if (is_stats_only) "" else paste0(" · ", nrow(sub), " findings")
    tbl <- if (is_stats_only) "" else html_searchable_table(
      sub,
      c("finding_id", "category", "issue", "submission_id", "enumerator", "school_id", "value"),
      paste0("tbl-", aid),
      10L,
      bold_date = last_date
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
  # across all modules, for quick triage. M12 media findings folded into the
  # generic per-module loop above, same as every other module.
  lastday_html <- ""
  if (!is.na(last_date)) {
    last_day_f <- if (nrow(findings)) {
      findings %>% filter(start_date == last_date | end_date == last_date)
    } else findings
    lastday_html <- paste0(
      "<section id='lastday' class='card'><h2>Last Day — ", esc(last_date), "</h2>",
      "<p class='mod-desc'>Every finding from the most recent day of data collection, across all modules — ",
      "a quick way to see what's most urgent. These same rows are also bolded within their own module's table.</p>",
      html_searchable_table(
        last_day_f,
        c("finding_id", "check_module", "category", "issue", "submission_id", "enumerator", "school_id", "value"),
        "tbl-lastday", 15L
      ),
      "</section>"
    )
  }

  nav_links <- c(nav_links, '<a href="#all">All findings</a>')
  all_tbl <- html_searchable_table(
    findings,
    c("finding_id", "check_module", "category", "issue", "submission_id", "enumerator", "school_id", "value"),
    "tbl-all", 10L,
    bold_date = last_date
  )

  # "About this dashboard" — orientation + glossary, always first
  about_items <- c(
    if (!is.na(last_date)) sprintf(
      "<li><strong>Last Day</strong> — every finding from %s (the most recent day of data collection) in one place.</li>",
      esc(last_date)
    ),
    vapply(modules_present, function(m) paste0(
      "<li><strong>", esc(module_label(m)), "</strong> <span class='mod-code'>", esc(m),
      "</span> — ", esc(module_desc(m)), "</li>"
    ), character(1)),
    if (has_gps) "<li><strong>Map</strong> — an interactive map of all submission locations; points flagged by GPS Location are shown in red. Click a point to see its unique ID.</li>",
    "<li><strong>All findings</strong> — every flagged row from every check module in one searchable table.</li>"
  )
  glossary_terms <- list(
    c("Finding", "One flagged row: a single thing that looks off in one submission (or one enumerator/site) and may be worth a closer look."),
    c("Category", "A short label grouping similar findings together, e.g. \"irregular_time\" or \"gps_distance\"."),
    c("Consent", "The guardian or head-of-household's agreement for the interview to take place."),
    c("Assent", "The child's own agreement to participate — separate from, and in addition to, a guardian's consent."),
    c("Enumerator", "The field staff member who conducted the interview."),
    c("Duplicate ID / key", "Two or more submissions sharing the same unique ID (or ID combination) or survey key, usually meaning one interview was captured twice."),
    c("Outlier", "A value far outside the typical range for that question — possibly a data-entry slip, possibly a genuinely unusual case."),
    c("Straightlining", "Giving the same answer choice repeatedly instead of varying answers — by one enumerator across surveys, or within one survey's set of similar questions."),
    c("Last day", "The most recent date of data collection, confirmed at setup. Findings from that date are bolded throughout the report and collected in the Last Day tab.")
  )
  glossary_html <- paste0(
    "<dl class='glossary'>",
    paste0(vapply(glossary_terms, function(t) paste0(
      "<dt>", esc(t[1]), "</dt><dd>", esc(t[2]), "</dd>"
    ), character(1)), collapse = ""),
    "</dl>"
  )
  about_html <- paste0(
    "<section id='about' class='card'><h2>About this dashboard</h2>",
    "<p>This report is a first read of the data, not a verdict — every table below is a shortlist ",
    "for field staff or RAs to review, not proof that something is wrong. Use the search box (or ",
    "\"Show all\") in any table to look up a specific submission, enumerator, or site. Tables are ",
    "sorted by enumerator, then unique ID, then date (most recent first).</p>",
    "<p><strong>What's in this report:</strong></p>",
    "<ul class='about-list'>", paste(about_items, collapse = ""), "</ul>",
    "<p><strong>Terms you'll see:</strong></p>",
    glossary_html,
    "</section>"
  )

  html <- paste0(
    "<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'/>",
    "<meta name='viewport' content='width=device-width, initial-scale=1'/>",
    "<title>HFC FieldLoop — ", esc(project_id), "</title>",
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
tr.row-bold td{font-weight:700}
.mod-code{font-size:.68rem;color:var(--muted);font-family:'IBM Plex Sans',system-ui,sans-serif;
  font-weight:400;margin-left:.35rem;vertical-align:middle}
h2 .mod-code{font-size:.62rem;border:1px solid var(--line);border-radius:4px;padding:.05rem .35rem}
.mod-desc{color:var(--muted);font-size:.95rem;margin:.15rem 0 .9rem;max-width:62ch}
.card h4{font-size:.85rem;font-family:'IBM Plex Sans',system-ui,sans-serif;font-weight:600;
  color:var(--muted);margin:1rem 0 .35rem;text-transform:uppercase;letter-spacing:.03em}
.about-list{margin:.4rem 0 1rem;padding-left:1.1rem}
.about-list li{margin:.3rem 0}
dl.glossary{display:grid;grid-template-columns:max-content 1fr;gap:.25rem 1rem;margin:.4rem 0 0}
dl.glossary dt{font-weight:600;font-family:'IBM Plex Sans',system-ui,sans-serif;font-size:.9rem}
dl.glossary dd{margin:0 0 .5rem;color:var(--muted);font-size:.9rem}
.custom-checks{margin:.4rem 0 1rem;padding:.6rem .8rem;background:#f7f1e4;border:1px solid var(--line);border-radius:8px}
.custom-checks h3{margin:0 0 .3rem;font-size:.95rem;font-family:'IBM Plex Sans',system-ui,sans-serif}
.custom-checks ul{margin:0;padding-left:1.1rem}
.custom-checks li{margin:.25rem 0;color:var(--muted);font-size:.9rem}
footer.note{margin-top:1.5rem;color:var(--muted);font-size:.9rem}
</style>
<link href='https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;600&family=Source+Serif+4:opsz,wght@8..60,500;8..60,700&display=swap' rel='stylesheet'/>
</head><body>",
    "<header class='nav'><span class='brand'>FieldLoop</span>",
    paste(nav_links, collapse = " "),
    "</header><main>",
    "<h1>", esc(project_id), "</h1>",
    "<p class='meta'>Generated ", Sys.Date(), " · ", nrow(findings), " findings · ",
    dplyr::n_distinct(findings$category), " categories</p>",
    about_html,
    "<section id='summary' class='card'><h2>Summary</h2>", summary_cards,
    "<h3>By category</h3>", cat_table, "</section>",
    lastday_html,
    paste(mod_sections, collapse = "\n"),
    map_html,
    "<section id='all' class='card'><h2>All findings</h2>", all_tbl, "</section>",
    "<p class='note footer'>Field edits go in the <strong>main</strong> feedback file in the ",
    "shared OneDrive folder (see <code>hfc/config/onedrive.json</code>). Local twin: ",
    "<code>hfc/output/feedback_sheet.xlsx</code>. When ready, say ",
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

ensure_project_dirs <- function(project_root) {
  # Raw data at project root; everything else under hfc/
  dir.create(file.path(project_root, "data", "raw"), recursive = TRUE, showWarnings = FALSE)
  hfc <- hfc_root(project_root)
  for (d in c("checks", "code", "fixes", "registry", "output", "report", "config", "instrument")) {
    dir.create(file.path(hfc, d), recursive = TRUE, showWarnings = FALSE)
  }
}

write_check_stubs <- function(project_root, findings, skill_dir = NULL) {
  checks_dir <- hfc_path(project_root, "checks")
  dir.create(checks_dir, showWarnings = FALSE, recursive = TRUE)
  # Do not wipe custom user checks (non-template names)
  if (!is.null(skill_dir) && !is.na(skill_dir)) {
    tmpl_dir <- file.path(skill_dir, "assets", "check_templates")
    if (dir.exists(tmpl_dir)) {
      for (f in list.files(tmpl_dir, pattern = "\\.R$", full.names = TRUE)) {
        bn <- basename(f)
        if (grepl("^custom_|example", bn, ignore.case = TRUE)) next
        file.copy(f, file.path(checks_dir, bn), overwrite = TRUE)
      }
    }
  }
  check_ids <- unique(findings$check_id)
  if (!length(check_ids)) check_ids <- "duplicates_id"
  for (cid in check_ids) {
    dest <- file.path(checks_dir, paste0(cid, ".R"))
    if (file.exists(dest)) next
    writeLines(c(
      sprintf("# Check: %s", cid),
      "# Re-run: Rscript hfc-fieldloop/scripts/run_setup_build.R <project_root>",
      "# Full logic: hfc-fieldloop/scripts/lib/run_checks.R"
    ), dest)
  }
}

write_main_r <- function(project_root, skill_dir = NULL) {
  dir.create(hfc_path(project_root, "code"), showWarnings = FALSE, recursive = TRUE)
  dest <- hfc_path(project_root, "code", "main.R")
  if (is.null(skill_dir) || is.na(skill_dir)) {
    skill_dir <- file.path(project_root, "hfc-fieldloop")
  }
  tmpl <- file.path(skill_dir, "assets", "main.R")
  if (file.exists(tmpl)) {
    lines <- readLines(tmpl, warn = FALSE)
    lines <- sub(
      'path <- "your/path/to/survey_project/"',
      sprintf('path <- "%s"', normalizePath(project_root)),
      lines,
      fixed = TRUE
    )
    writeLines(lines, dest)
  } else {
    writeLines(c(
      "# HFC FieldLoop — one path global",
      sprintf('path <- "%s"', normalizePath(project_root)),
      'skill <- file.path(path, "hfc-fieldloop")',
      'hfc <- file.path(path, "hfc")',
      "# Rscript file.path(skill, \"scripts\", \"run_setup_build.R\") path --open",
      "# Rscript file.path(skill, \"scripts\", \"apply_feedback.R\") path"
    ), dest)
  }
}
