# Report contract validation — checks a built HTML report's actual
# structure against report_sections.json, the authoritative spec for what
# every section should be. Wired into write_html_report()'s callers
# (run_setup_build.R/rebuild_report.R): a non-fatal message() summary in
# production (consistent with the rest of the codebase's posture — a
# report-quality issue shouldn't abort the build), but fatal (stopifnot) in
# tests/test_report_contract.R.
#
# Depends on compute_modules_present() (build_outputs.R) — the SAME
# function the real render loop calls, so this validator and the actual
# build can never structurally drift apart.

suppressPackageStartupMessages({
    if (!requireNamespace("xml2", quietly = TRUE)) {
        stop("scripts/lib/report_contract.R requires the 'xml2' package.")
    }
})

# Section label (report_sections.json's own section names) -> DOM id, built
# from the actual render code in build_outputs.R (write_html_report()):
# "About"/"Summary"/"Last Day" get fixed ids, every numbered module gets
# "mod-<lowercase code>", "Other" (M9's split-off section) gets "mod-other",
# "All Issues" gets "all". Last Day is conditional on data (only rendered
# when a last_date was found) — never asserted as required here, since the
# validator doesn't independently recompute that condition.
REPORT_CONTRACT_FIXED_IDS <- c(About = "about", Summary = "summary", `All Issues` = "all")

#' Read `report_sections.json`'s section list (just names, for now — the
#' per-column/table content beneath each section is used as a reference
#' when building a module, not re-validated field-by-field here).
read_report_sections_spec <- function(report_sections_path) {
    if (!file.exists(report_sections_path)) {
        return(list(ok = FALSE, error = paste("report_sections.json not found at", report_sections_path)))
    }
    spec <- tryCatch(jsonlite::fromJSON(report_sections_path, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(spec) || is.null(spec$sections)) {
        return(list(ok = FALSE, error = "report_sections.json did not parse into the expected {notes, sections} shape."))
    }
    list(ok = TRUE, sections = spec$sections)
}

#' validate_report_contract(html_path, report_sections_path, modules_present, modules)
#' -> list(ok, missing, unexpected, warnings)
#'
#' `missing`: an expected-and-currently-relevant section/id that isn't in
#' the HTML at all. `unexpected`: (reserved — not populated by structural
#' checks below, since an "extra" id is harmless; kept in the return shape
#' for forward compatibility with a stricter check later). `warnings`: a
#' targeted spot-check failed (wrong label text, missing sub-structure) —
#' real problems, but not "section is completely absent."
validate_report_contract <- function(html_path, report_sections_path, modules_present, modules = NULL) {
    missing <- character(); unexpected <- character(); warnings <- character()

    if (!file.exists(html_path)) {
        return(list(ok = FALSE, missing = "(html file not found)", unexpected = character(), warnings = character()))
    }
    spec <- read_report_sections_spec(report_sections_path)
    if (!isTRUE(spec$ok)) {
        return(list(ok = FALSE, missing = character(), unexpected = character(), warnings = spec$error))
    }

    doc <- tryCatch(xml2::read_html(html_path), error = function(e) NULL)
    if (is.null(doc)) {
        return(list(ok = FALSE, missing = "(HTML did not parse)", unexpected = character(), warnings = character()))
    }
    has_id <- function(id) length(xml2::xml_find_all(doc, sprintf("//*[@id='%s']", id))) > 0
    section_text <- function(id) {
        nodes <- xml2::xml_find_all(doc, sprintf("//*[@id='%s']", id))
        if (!length(nodes)) return(NA_character_)
        paste(xml2::xml_text(nodes), collapse = " ")
    }

    # Fixed, always-expected sections.
    for (nm in names(REPORT_CONTRACT_FIXED_IDS)) {
        if (!has_id(REPORT_CONTRACT_FIXED_IDS[[nm]])) missing <- c(missing, nm)
    }

    # Every currently-"on"/present module gets its own section.
    for (mod in modules_present) {
        aid <- paste0("mod-", tolower(mod))
        if (!has_id(aid)) missing <- c(missing, sprintf("%s (%s)", module_label(mod), mod))
    }
    # M9 Field Request always brings its adjacent "Other" section with it.
    if ("M9" %in% modules_present && !has_id("mod-other")) missing <- c(missing, "Other")

    # ---- targeted spot-checks (report_sections.json's documented rules) ----

    # Field Request's own table reads "Info," not "Issue," in its header row.
    # A precise th-element query, not a substring/word-boundary check on the
    # whole section's flattened text — xml_text() concatenates adjacent
    # elements with no separator (e.g. a heading "Field Request" directly
    # followed by a header cell "Info" reads as "Field RequestInfo," which a
    # \\bInfo\\b word-boundary check would miss entirely).
    if ("M9" %in% modules_present && has_id("mod-m9")) {
        node <- xml2::xml_find_first(doc, "//*[@id='mod-m9']")
        th_texts <- trimws(xml2::xml_text(xml2::xml_find_all(node, ".//th")))
        if (!"Info" %in% th_texts) {
        warnings <- c(warnings, "M9 Field Request: expected an 'Info' column header, not found.")
        }
    }

    # Balance Tables render via gt — its fingerprint class should be present.
    if ("M12" %in% modules_present && has_id("mod-m12")) {
        node <- xml2::xml_find_first(doc, "//*[@id='mod-m12']")
        html_frag <- as.character(xml2::xml_find_all(node, ".//table"))
        if (!any(grepl("gt_table", html_frag, fixed = TRUE))) {
        warnings <- c(warnings, "M12 Balance Tables: expected gt-rendered table(s) (class 'gt_table'), not found.")
        }
    }

    # GPS Map: a map div, or an explicit no-GPS note — either is fine, an
    # empty section is not.
    if ("M10" %in% modules_present && has_id("mod-m10")) {
        txt <- section_text("mod-m10")
        if (!has_id("gps-map") && (is.na(txt) || !grepl("No GPS coordinates", txt, fixed = TRUE))) {
        warnings <- c(warnings, "M10 GPS Map: expected either a map div or a 'No GPS coordinates' note, found neither.")
        }
    }

    # Duplicates (M2): report_sections.json's aggregate-per-group redesign —
    # one row per duplicate GROUP with a Value column (submission
    # timestamps), never a Date/Enumerator column (that would mean the
    # row-per-submission shape the redesign fixed came back).
    if ("M2" %in% modules_present && has_id("mod-m2")) {
        node <- xml2::xml_find_first(doc, "//*[@id='mod-m2']")
        th_texts <- trimws(xml2::xml_text(xml2::xml_find_all(node, ".//th")))
        if (!"Value" %in% th_texts) {
        warnings <- c(warnings, "M2 Duplicates: expected a 'Value' column (submission timestamps), not found.")
        }
        if ("Date" %in% th_texts || "Enumerator" %in% th_texts) {
        warnings <- c(warnings, "M2 Duplicates: found a Date/Enumerator column — should be a pure entity-level aggregate (one row per duplicate group).")
        }
    }

    # M1 never shows the removed "by enumerator, latest day" table (Phase 3d
    # regression guard — report_sections.json's Completion Notes).
    if ("M1" %in% modules_present && has_id("mod-m1")) {
        txt <- section_text("mod-m1")
        if (!is.na(txt) && grepl("Last Active Day", txt, fixed = TRUE)) {
        warnings <- c(warnings, "M1 Completion: found a 'Last Active Day' column — this table was supposed to be removed in v2.")
        }
    }

    # Per-module per-enumerator collapsing (Phase 3i): 'enum-issues' panels
    # are exclusively an All Issues feature — they must never appear inside
    # any per-module section.
    enum_issue_nodes <- xml2::xml_find_all(doc, "//*[contains(@class,'enum-issues')]")
    if (length(enum_issue_nodes)) {
        outside_all <- Filter(function(n) {
        anc <- xml2::xml_find_first(n, "ancestor::*[@id='all']")
        length(anc) == 0 || is.na(xml2::xml_attr(anc, "id"))
        }, enum_issue_nodes)
        if (length(outside_all)) {
        warnings <- c(warnings, "Found 'enum-issues' per-enumerator panel(s) outside the All Issues section — per-module collapsing should have been removed.")
        }
    }

    # M1's BY GROUP table reads "Progress," not "Completion," under roster
    # mode (Phase 3l) — precise th-element query, same reasoning as the
    # Field Request "Info" check above.
    if (!is.null(modules) && identical(modules$M1$completion_signal, "roster") && has_id("mod-m1")) {
        node <- xml2::xml_find_first(doc, "//*[@id='mod-m1']")
        th_texts <- trimws(xml2::xml_text(xml2::xml_find_all(node, ".//th")))
        if (!"Progress" %in% th_texts) {
        warnings <- c(warnings, "M1 Completion: roster completion_signal is on, expected a 'Progress' column header, not found.")
        }
    }

    list(
        ok = length(missing) == 0 && length(warnings) == 0,
        missing = missing, unexpected = unexpected, warnings = warnings
    )
}

#' Human-readable one-block summary, for the message()-level production use.
format_report_contract <- function(v) {
    if (isTRUE(v$ok)) return("Report contract: OK — every expected section present, spot-checks passed.")
    lines <- character()
    if (length(v$missing)) lines <- c(lines, paste0("Missing sections: ", paste(v$missing, collapse = ", ")))
    if (length(v$warnings)) lines <- c(lines, paste0("Warnings: ", paste(v$warnings, collapse = " | ")))
    paste0("Report contract: ISSUES FOUND\n  ", paste(lines, collapse = "\n  "))
}
