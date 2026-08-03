# Setup build for a drop-in project root.
# Rscript run_setup_build.R <project_root> [--open] [--sample N] [--no-onedrive]
#
# Reads optional hfc/config/modules.yaml; otherwise uses profile defaults.
# All product artifacts land under <project_root>/hfc/.

`%||%` <- function(a, b) {
    if (is.null(a) || length(a) == 0) return(b)
    if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(as.character(a))))) return(b)
    a
}

# Step 1: find the skill's own root dir (so scripts/lib/*.R can be sourced
# regardless of where/how this script was invoked from).
.resolve_skill <- function() {
    sp <- {
    ca <- commandArgs(trailingOnly = FALSE)
    fa <- grep("^--file=", ca, value = TRUE)
    if (length(fa)) gsub("~+~", " ", sub("^--file=", "", fa[[1]]), fixed = TRUE) else NA_character_
    }
    if (!is.na(sp) && file.exists(sp)) {
    return(normalizePath(file.path(dirname(sp), "..")))
    }
    if (file.exists("hfc-fieldloop/scripts/lib/utils.R")) {
    return(normalizePath("hfc-fieldloop"))
    }
    if (file.exists("scripts/lib/utils.R")) return(normalizePath(".."))
    stop("Cannot locate hfc-fieldloop")
}
skill <- .resolve_skill()
lib <- file.path(skill, "scripts", "lib")
source(file.path(lib, "utils.R"))
source(file.path(lib, "geo_timezone.R"))
source(file.path(lib, "media.R"))
source(file.path(lib, "discover.R"))
source(file.path(lib, "profile_roles.R"))
source(file.path(lib, "form_logic.R"))
source(file.path(lib, "run_checks.R"))
source(file.path(lib, "build_outputs.R"))
source(file.path(lib, "product_structure.R"))
source(file.path(lib, "onedrive_drive.R"))
source(file.path(lib, "issue_store.R"))

# Step 2: parse CLI args — project root + flags.
args <- commandArgs(trailingOnly = TRUE)
project_root <- if (length(args) && !startsWith(args[[1]], "--")) {
    normalizePath(decode_file_arg(args[[1]]), mustWork = FALSE)
} else {
    project_root_from_skill(skill)
}

do_open <- "--open" %in% args || "--open" %in% commandArgs(trailingOnly = TRUE)
no_onedrive <- "--no-onedrive" %in% args || identical(Sys.getenv("FIELDLOOP_NO_ONEDRIVE"), "1")
sample_n <- NA_integer_
if ("--sample" %in% args) {
    i <- match("--sample", args)
    if (!is.na(i) && i < length(args)) sample_n <- as.integer(args[[i + 1]])
}

suppressPackageStartupMessages({
    library(haven); library(dplyr); library(readr); library(openxlsx)
    library(yaml); library(jsonlite); library(lubridate); library(tibble)
})

# Step 3: scaffold hfc/ and drop the skill-tree browser page.
message("Project root: ", project_root)
ensure_project_dirs(project_root)
write_product_structure_html(project_root, open = FALSE)

# Step 4: find the microdata (+ optional form) under data/raw/.
disc <- discover_project(project_root, create_raw_if_missing = TRUE)
if (identical(disc$status, "missing_data")) {
    stop("No microdata found under data/raw/. Drop a .dta/.csv/.xlsx and re-run.")
}

data_path <- disc$data$path
form_path <- if (!is.null(disc$form)) disc$form$path else NA_character_

# Step 5: symlink/copy the data (+ form) into data/raw/ and hfc/instrument/
# if they weren't already there (e.g. discovered elsewhere in the project).
raw_dest <- file.path(project_root, "data", "raw", basename(data_path))
if (!file.exists(raw_dest) || !identical(normalizePath(data_path), normalizePath(raw_dest, mustWork = FALSE))) {
    if (!file.exists(raw_dest)) {
    ok <- FALSE
    try(ok <- file.symlink(normalizePath(data_path), raw_dest), silent = TRUE)
    if (!isTRUE(ok) && !file.exists(raw_dest)) file.copy(data_path, raw_dest)
    }
    data_path <- raw_dest
}
if (!is.na(form_path) && file.exists(form_path)) {
    form_dest <- hfc_path(project_root, "instrument", "form.xlsx")
    if (!identical(normalizePath(form_path, mustWork = FALSE),
                    normalizePath(form_dest, mustWork = FALSE))) {
    file.copy(form_path, form_dest, overwrite = TRUE)
    }
}

# Step 6: load the microdata into memory (optionally subsampled).
message("Loading: ", data_path)
ds <- load_microdata(data_path, sample_n = sample_n)

# Step 7: locate the media folder for M12 on-disk audio/image checks.
media_folder <- disc$media_folder %||% NA_character_
if (is.null(media_folder) || (length(media_folder) == 1 && is.na(media_folder))) {
    mf <- discover_media_folder(project_root, data_path)
    media_folder <- mf$path
}
if (isTRUE(disc$media_folder_found) || (!is.na(media_folder) && nzchar(media_folder))) {
    message("Media folder: ", media_folder)
} else {
    message("Media folder: (not found — M12 on-disk checks will be skipped if media cols exist)")
}

# Step 8: heuristically detect column roles (id, group, gps, enum, …).
roles <- profile_roles(ds, media_folder = media_folder)
if (length(roles$entity_id_rationale)) {
    message("Entity ID shortlist:\n  ", paste(roles$entity_id_rationale, collapse = "\n  "))
}

# Step 9: load confirmed module config if it exists (from a prior run /
# AskUserQuestion confirm), else fall back to profiled defaults and write it.
modules_path <- hfc_path(project_root, "config", "modules.yaml")
if (file.exists(modules_path)) {
    modules <- yaml::read_yaml(modules_path)
    if (!is.null(modules$M12) &&
        (is.null(modules$M12$media_folder) || is.na(modules$M12$media_folder) ||
        !nzchar(as.character(modules$M12$media_folder[[1]])))) {
    modules$M12$media_folder <- media_folder
    }
} else {
    modules <- default_modules(roles)
    yaml::write_yaml(modules, modules_path)
}

# Step 10: same for role_map.yaml — reload previously confirmed roles
# (required-fields gate answers) so rebuilds don't re-derive/re-ask them.
role_map_path <- hfc_path(project_root, "config", "role_map.yaml")
if (file.exists(role_map_path)) {
    saved <- yaml::read_yaml(role_map_path)
    # Required-fields gate answers (Entity ID, duplicate-check key,
    # country/timezone, last date) persist here; reload them each rebuild
    # rather than re-deriving.
    if (!is.null(saved$entity_id) && length(saved$entity_id)) roles$entity_id <- unlist(saved$entity_id)
    if (!is.null(saved$entity_id_sep) && nzchar(as.character(saved$entity_id_sep))) {
        roles$entity_id_sep <- as.character(saved$entity_id_sep)
    }
    if (!is.null(saved$dup_key_extra) && length(saved$dup_key_extra)) {
        roles$dup_key_extra <- unlist(saved$dup_key_extra)
    }
    if (!is.null(saved$country_mode) && nzchar(as.character(saved$country_mode))) {
        roles$country_mode <- as.character(saved$country_mode)
    }
    if (!is.null(saved$country) && nzchar(as.character(saved$country))) {
        roles$country <- as.character(saved$country)
    }
    if (!is.null(saved$country_col) && nzchar(as.character(saved$country_col))) {
        roles$country_col <- as.character(saved$country_col)
    }
    if (!is.null(saved$country_timezone_map) && length(saved$country_timezone_map)) {
        roles$country_timezone_map <- saved$country_timezone_map
    }
    if (!is.null(saved$timezone) && nzchar(as.character(saved$timezone))) {
        roles$timezone <- as.character(saved$timezone)
    }
    if (!is.null(saved$last_date) && nzchar(as.character(saved$last_date))) {
        roles$last_date <- as.character(saved$last_date)
    }
    if (!is.null(saved$entity_label) && nzchar(as.character(saved$entity_label))) {
        roles$entity_label <- as.character(saved$entity_label)
    }
    if (!is.null(modules$M2)) {
        modules$M2$id <- roles$entity_id
        modules$M2$extra_keys <- roles$dup_key_extra %||% character()
    }
}
# Step 11: persist the (possibly reloaded) roles + a human-readable option-
# card dump for reference.
yaml::write_yaml(roles, role_map_path)
writeLines(format_module_cards(roles), hfc_path(project_root, "config", "module_cards.txt"))

# Step 12: form relevance for nested skip-logic
form_map <- parse_form_relevance(if (!is.na(form_path) && file.exists(form_path)) form_path else
    hfc_path(project_root, "instrument", "form.xlsx"))
attr(ds, "hfc_form_map") <- form_map

# Step 13: report config (map focus etc.)
report_cfg_path <- hfc_path(project_root, "config", "report.yaml")
report_cfg <- if (file.exists(report_cfg_path)) yaml::read_yaml(report_cfg_path) else list(map_focus = "country")

# Step 14: human-readable notes for custom/M11 checks (and optional per-module
# description overrides), authored during the Additional-checks confirm step.
# Optional file.
module_notes_path <- hfc_path(project_root, "config", "module_notes.yaml")
module_notes <- if (file.exists(module_notes_path)) yaml::read_yaml(module_notes_path) else NULL

# Step 15: the actual work — run every confirmed M1–M13 + custom check.
message("Running checks...")
check_res <- run_check_modules(ds, roles, modules, project_root = project_root)
findings <- check_res$findings
stats <- check_res$stats
message("Findings: ", nrow(findings))

# Step 16: write registry outputs from the findings.
readr::write_csv(findings, hfc_path(project_root, "registry", "findings.csv"))
write_check_stubs(project_root, findings, skill_dir = skill)
write_main_r(project_root, skill_dir = skill)

# Step 17: fetch the live issue_tracking.xlsx (OneDrive main_file if
# configured, else local hfc/output/ — see scripts/lib/issue_store.R), write
# this run's fresh findings as today's intermediate/ snapshot, then either
# commit directly (first-ever run — nothing to merge against) or merge and
# stop for the agent to confirm (a prior file exists: merging must never
# silently overwrite field/RA/agent work on the live shared file).
ctx <- fetch_issue_tracking(project_root, skill_dir = skill, force_local = no_onedrive)
fb_new <- findings_to_issue_tracking(findings)
write_tracking_snapshot(ctx, fb_new)

merge_pending <- FALSE
if (is.null(ctx$tbl)) {
    commit_issue_tracking(project_root, fb_new, skill_dir = skill, fetch_ctx = ctx)
    issue_tracking_status <- "created"
} else {
    merged <- merge_preserve_existing(ctx$tbl, fb_new)
    write_named_tracking_file(ctx, merged, "merged_issue_tracking.xlsx")
    merge_pending <- TRUE
    issue_tracking_status <- "merge_pending"
}

drive <- list(status = ctx$backend, reason = ctx$reason %||% "", url = NA_character_)

# Step 18: mirror the skill's OneDrive config into hfc/ for the record (this
# copy is informational only — the live config always stays in the skill's
# own assets/lib/onedrive.json).
drv_cfg <- load_onedrive_config(project_root, skill)
if (isTRUE(drv_cfg$found)) {
    cfg_dest <- hfc_path(project_root, "config", "onedrive.json")
    dir.create(dirname(cfg_dest), showWarnings = FALSE, recursive = TRUE)
    if (!identical(normalizePath(drv_cfg$path, mustWork = FALSE),
                    normalizePath(cfg_dest, mustWork = FALSE))) {
        file.copy(drv_cfg$path, cfg_dest, overwrite = TRUE)
    }
}

# Step 19: assemble the project's own metadata file (data path, OneDrive
# links, config pointers) — written after the report link is known below.
project_id <- basename(project_root)
proj_yaml <- list(
    project_id = project_id,
    data_file = file.path("data", "raw", basename(data_path)),
    instrument = if (!is.na(form_path)) "hfc/instrument/form.xlsx" else NULL,
    report_type = "html",
    map_focus = report_cfg$map_focus %||% "country",
    shiny_later = TRUE,
    issue_tracking_backend = ctx$backend,
    issue_tracking_merge_pending = merge_pending,
    onedrive_config = "hfc-fieldloop/assets/lib/onedrive.json",
    created = as.character(Sys.time()),
    n_findings = nrow(findings)
)

# Step 20: build the navigable HTML report (optionally auto-opened).
html_path <- write_html_report(
    findings, project_root, project_id, open = do_open,
    roles = roles, ds = ds, report_cfg = report_cfg, module_notes = module_notes,
    stats = stats
)

# Step 21: upload the report to OneDrive and get its shareable URL, then
# finish + persist project.yaml now that the link is known.
report_link <- if (no_onedrive) {
    list(status = "skipped", reason = "no-onedrive flag", url = NA)
} else {
    upload_report_and_get_link(project_root, project_id, skill_dir = skill, html_path)
}
proj_yaml$report_onedrive_url <- report_link$url %||% NA
yaml::write_yaml(proj_yaml, hfc_path(project_root, "project.yaml"))

# Step 22: log this run for debugging/traceability.
runs <- hfc_path(project_root, "runs", "setup")
dir.create(file.path(runs, "turns"), recursive = TRUE, showWarnings = FALSE)
yaml::write_yaml(list(status = "built", n_findings = nrow(findings), html = html_path),
                 file.path(runs, "meta.yaml"))
jsonlite::write_json(list(
    n_findings = nrow(findings),
    categories = as.list(table(findings$category)),
    issue_tracking_status = issue_tracking_status,
    issue_tracking_backend = ctx$backend,
    report_link = report_link,
    html = html_path,
    entity_id = roles$entity_id,
    entity_id_options = roles$entity_id_options,
    dup_key_extra = roles$dup_key_extra
), file.path(runs, "meta.json"), auto_unbox = TRUE, pretty = TRUE)

message("Done. HTML: ", html_path)
message("Product root: ", hfc_root(project_root))
message("Issue tracking backend: ", ctx$backend, " (", drive$reason %||% "", ")")
if (merge_pending) {
    message("MERGE_PENDING: review merged_issue_tracking.xlsx before overwriting issue_tracking.xlsx.")
    message("  Rscript .claude/skills/hfc-fieldloop/scripts/commit_merged_issue_tracking.R \"<project_root>\" merged_issue_tracking.xlsx")
} else {
    message("issue_tracking.xlsx created fresh (first build).")
}
message("Report link: ", report_link$status, " (", report_link$reason %||% "", ") ", report_link$url %||% "(none)")
message("When field edits issue_tracking, run: Process HFC feedback")
