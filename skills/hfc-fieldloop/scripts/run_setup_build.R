# Setup build, driven entirely by skills/hfc-fieldloop/config.json.
# Rscript run_setup_build.R [--open] [--sample N]
# config.json must already be configured (input_data_dir, onedrive_output_dir,
# code_output_dir required; media_dir optional) — there is no local-only mode.
#
# Reads optional hfc/config/modules.yaml; otherwise uses profile defaults.
# All product artifacts land under <code_output_dir>/hfc/. Raw microdata is
# read in place from input_data_dir and never copied anywhere.

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
    if (file.exists(".claude/skills/hfc-fieldloop/scripts/lib/utils.R")) {
    return(normalizePath(".claude/skills/hfc-fieldloop"))
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
source(file.path(lib, "module_desc.R"))
source(file.path(lib, "check_modules_preview.R"))
source(file.path(lib, "pipeline_core.R"))
source(file.path(lib, "product_structure.R"))
source(file.path(lib, "sync_fpaths.R"))
source(file.path(lib, "issue_store.R"))

# Step 2: parse CLI flags — no positional args anymore, everything comes from config.json.
args <- commandArgs(trailingOnly = TRUE)
do_open <- "--open" %in% args
sample_n <- NA_integer_
if ("--sample" %in% args) {
    i <- match("--sample", args)
    if (!is.na(i) && i < length(args)) sample_n <- as.integer(args[[i + 1]])
}

suppressPackageStartupMessages({
    library(haven); library(dplyr); library(readr); library(openxlsx)
    library(yaml); library(jsonlite); library(lubridate); library(tibble)
})

# Step 2b: config.json must be fully configured and its OneDrive output
# folder reachable — no local fallback. Fail fast, before any other work,
# with setup instructions rather than silently proceeding.
cfg_ctx <- require_fieldloop_config_ready(skill)
cfg <- cfg_ctx$cfg

# Step 3: scaffold hfc/ under code_output_dir and drop the skill-tree browser page.
message("Input data dir: ", cfg$input_data_dir)
message("Code output dir: ", cfg$code_output_dir)
ensure_project_dirs(cfg$code_output_dir)
write_product_structure_html(cfg, open = FALSE)

# Step 4: find the microdata (+ optional form) inside the configured input_data_dir only.
disc <- discover_project(cfg$input_data_dir)
if (identical(disc$status, "missing_dir")) {
    stop("input_data_dir does not exist: ", cfg$input_data_dir)
}
if (identical(disc$status, "missing_data")) {
    stop("No microdata found in input_data_dir (", cfg$input_data_dir, "). Drop a .dta/.csv/.xlsx there and re-run.")
}

data_path <- disc$data$path
form_path <- if (!is.null(disc$form)) disc$form$path else NA_character_

# Step 5: copy the form (survey instrument, not respondent data) into
# hfc/instruments/form.xlsx. Raw microdata is never copied — it's read in
# place from input_data_dir below.
if (!is.na(form_path) && file.exists(form_path)) {
    form_dest <- hfc_path(cfg$code_output_dir, "instruments", "form.xlsx")
    if (!identical(normalizePath(form_path, mustWork = FALSE),
                    normalizePath(form_dest, mustWork = FALSE))) {
    file.copy(form_path, form_dest, overwrite = TRUE)
    }
}

# Step 6: load the microdata into memory (optionally subsampled).
message("Loading: ", data_path)
ds <- load_microdata(data_path, sample_n = sample_n)

# Step 7: media folder for M11 on-disk audio/image checks — configured
# directly via config.json's media_dir, optional.
media_folder <- cfg$media_dir %||% NA_character_
if (!is.na(media_folder) && nzchar(media_folder)) {
    message("Media folder: ", media_folder)
} else {
    message("Media folder: (not configured — M11 on-disk checks will be skipped if media cols exist)")
}

# Step 8: heuristically detect column roles (id, group, gps, enum, …).
roles <- profile_roles(ds, media_folder = media_folder, roster_candidate = disc$roster_candidate)
if (length(roles$entity_id_rationale)) {
    message("Entity ID shortlist:\n  ", paste(roles$entity_id_rationale, collapse = "\n  "))
}

# Step 9: reload previously confirmed roles (required-fields gate answers,
# the important-variables shortlist, and M7's missingness_extra_vars) from
# role_map.yaml, BEFORE modules are loaded/defaulted next — default_modules()
# reads roles$important_vars/roles$missingness_extra_vars, so this must
# happen first or a true first-ever build (no modules.yaml yet) would
# silently ignore an already-confirmed shortlist.
role_map_path <- hfc_path(cfg$code_output_dir, "config", "role_map.yaml")
role_map_existed <- file.exists(role_map_path)
if (role_map_existed) {
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
    if (!is.null(saved$group_label) && nzchar(as.character(saved$group_label))) {
        roles$group_label <- as.character(saved$group_label)
    }
    # De-identification display overrides (default "id"/"name"/"name" set by
    # profile_roles() every run) — reload a saved override so it survives a
    # rebuild instead of reverting to the default.
    if (!is.null(saved$entity_display) && nzchar(as.character(saved$entity_display))) {
        roles$entity_display <- as.character(saved$entity_display)
    }
    if (!is.null(saved$enumerator_display) && nzchar(as.character(saved$enumerator_display))) {
        roles$enumerator_display <- as.character(saved$enumerator_display)
    }
    if (!is.null(saved$group_display) && nzchar(as.character(saved$group_display))) {
        roles$group_display <- as.character(saved$group_display)
    }
    if (!is.null(saved$map_focus) && nzchar(as.character(saved$map_focus))) {
        roles$map_focus <- as.character(saved$map_focus)
    }
    if (!is.null(saved$important_vars) && length(saved$important_vars)) {
        roles$important_vars <- unlist(saved$important_vars)
    }
    if (!is.null(saved$missingness_extra_vars) && length(saved$missingness_extra_vars)) {
        roles$missingness_extra_vars <- unlist(saved$missingness_extra_vars)
    }
    # Completion signal + grouping confirmations (SKILL.md A1's required-gate
    # window / module-bundle tabs) persist here too; reload rather than
    # re-deriving so a confirmed answer survives rebuilds.
    if (!is.null(saved$completion_primary_signal) && nzchar(as.character(saved$completion_primary_signal))) {
        roles$completion_primary_signal <- as.character(saved$completion_primary_signal)
    }
    if (!is.null(saved$completion_status_col) && nzchar(as.character(saved$completion_status_col))) {
        roles$completion_status_col <- as.character(saved$completion_status_col)
    }
    if (!is.null(saved$completion_status_complete_values) && length(saved$completion_status_complete_values)) {
        roles$completion_status_complete_values <- unlist(saved$completion_status_complete_values)
    }
    if (!is.null(saved$completion_roster_key_col) && nzchar(as.character(saved$completion_roster_key_col))) {
        roles$completion_roster_key_col <- as.character(saved$completion_roster_key_col)
    }
    if (!is.null(saved$completion_primary_secondary_col) && nzchar(as.character(saved$completion_primary_secondary_col))) {
        roles$completion_primary_secondary_col <- as.character(saved$completion_primary_secondary_col)
    }
    if (!is.null(saved$completion_primary_value) && nzchar(as.character(saved$completion_primary_value))) {
        roles$completion_primary_value <- as.character(saved$completion_primary_value)
    }
    if (!is.null(saved$treatment_control_col) && nzchar(as.character(saved$treatment_control_col))) {
        roles$treatment_control_col <- as.character(saved$treatment_control_col)
    }
    if (!is.null(saved$geo_group_col) && nzchar(as.character(saved$geo_group_col))) {
        roles$geo_group_col <- as.character(saved$geo_group_col)
    }
    if (!is.null(saved$geo_group_opted_in)) {
        roles$geo_group_opted_in <- isTRUE(saved$geo_group_opted_in)
    }
    if (!is.null(saved$qualitative_text_cols) && length(saved$qualitative_text_cols)) {
        roles$qualitative_text_cols <- unlist(saved$qualitative_text_cols)
    }
}

# Step 10: load confirmed module config if it exists (from a prior run /
# AskUserQuestion confirm), else fall back to profiled defaults (now using
# the possibly-reloaded roles above) and write it.
modules_path <- hfc_path(cfg$code_output_dir, "config", "modules.yaml")
if (file.exists(modules_path)) {
    modules <- yaml::read_yaml(modules_path)
} else {
    modules <- default_modules(roles)
    write_commented_modules_yaml(modules, modules_path)
}
if (role_map_existed && !is.null(modules$M2)) {
    modules$M2$id <- roles$entity_id
    modules$M2$extra_keys <- roles$dup_key_extra %||% character()
}
# Step 11: persist the (possibly reloaded) roles.
yaml::write_yaml(roles, role_map_path)

# Step 12: form relevance for nested skip-logic
form_map <- parse_form_relevance(if (!is.na(form_path) && file.exists(form_path)) form_path else
    hfc_path(cfg$code_output_dir, "instruments", "form.xlsx"))
attr(ds, "hfc_form_map") <- form_map

# Step 13: report config (map focus etc.) — folded into role_map.yaml
# (roles$map_focus, reloaded above), no separate report.yaml.
report_cfg <- list(map_focus = roles$map_focus %||% "country")

# Step 14: human-readable notes for custom/M10 checks (and optional per-module
# description overrides), authored during the Additional-checks confirm step.
# Optional file.
module_notes_path <- hfc_path(cfg$code_output_dir, "config", "module_notes.yaml")
module_notes <- if (file.exists(module_notes_path)) yaml::read_yaml(module_notes_path) else NULL

# Steps 15-16: the actual work — run every confirmed M1–M13 + custom check,
# then write hfc/outputs/ artifacts (shared with scripts/rebuild_report.R).
# Load the roster/target-sample list (read-only, never mutated, never
# copied anywhere) whenever one was found — not just when the confirmed
# completion signal is "roster": check_m1()'s replacement-sample analysis
# (primary/replacement/rank columns) is independent of which signal is
# actually driving completion, so it needs target_ds too.
target_ds <- NULL
if (!is.null(roles$completion_roster_candidate) && !is.na(roles$completion_roster_candidate$path %||% NA_character_)) {
    target_ds <- tryCatch(load_microdata(roles$completion_roster_candidate$path), error = function(e) NULL)
    if (is.null(target_ds)) message("Could not load roster/target file: ", roles$completion_roster_candidate$path)
}
res <- run_checks_and_write_issues(cfg$code_output_dir, ds, roles, modules, skill, target_ds = target_ds)
findings <- res$findings
stats <- res$stats

# Step 17: fetch the live issue_tracking.xlsx from the configured OneDrive
# output folder (see scripts/lib/issue_store.R), write this run's fresh
# findings as today's intermediate/ snapshot, then either commit directly
# (first-ever run — nothing to merge against) or merge and stop for the agent
# to confirm (a prior file exists: merging must never silently overwrite
# field/RA/agent work on the live shared file).
entity_label <- roles$entity_label %||% NA_character_
group_label <- roles$group_label %||% NA_character_
ctx <- fetch_issue_tracking(skill_dir = skill, entity_label = entity_label, group_label = group_label)
fb_new <- findings_to_issue_tracking(findings, roles = roles)
write_tracking_snapshot(ctx, fb_new, entity_label = entity_label, group_label = group_label)

merge_pending <- FALSE
if (is.null(ctx$tbl)) {
    commit_issue_tracking(fb_new, skill_dir = skill, fetch_ctx = ctx, entity_label = entity_label, group_label = group_label)
    issue_tracking_status <- "created"
} else {
    merged <- merge_preserve_existing(ctx$tbl, fb_new)
    write_named_tracking_file(ctx, merged, "merged_issue_tracking.xlsx", entity_label = entity_label, group_label = group_label)
    merge_pending <- TRUE
    issue_tracking_status <- "merge_pending"
}

# Step 18: mirror config.json into hfc/ for the record (this copy is
# informational only — the live config always stays at
# skills/hfc-fieldloop/config.json).
cfg_dest <- hfc_path(cfg$code_output_dir, "config", "config.json")
dir.create(dirname(cfg_dest), showWarnings = FALSE, recursive = TRUE)
if (!identical(normalizePath(cfg$path, mustWork = FALSE),
                normalizePath(cfg_dest, mustWork = FALSE))) {
    file.copy(cfg$path, cfg_dest, overwrite = TRUE)
}

# Step 19: assemble the project's own metadata file (data path, config
# pointers) — written after the report copy is done below.
project_id <- derive_project_id(cfg$input_data_dir)
proj_yaml <- list(
    project_id = project_id,
    data_file = basename(data_path),
    instrument = if (!is.na(form_path)) "hfc/instruments/form.xlsx" else NULL,
    report_type = "html",
    map_focus = report_cfg$map_focus %||% "country",
    shiny_later = TRUE,
    issue_tracking_merge_pending = merge_pending,
    config_file = "config.json",
    created = as.character(Sys.time()),
    n_findings = nrow(findings)
)

# Step 20: build the navigable HTML report (optionally auto-opened).
html_path <- write_html_report(
    findings, cfg$code_output_dir, project_id, open = do_open,
    roles = roles, ds = ds, report_cfg = report_cfg, module_notes = module_notes,
    stats = stats, modules = modules
)

# Step 21: copy the report into the OneDrive-synced folder (passive sharing
# — OneDrive's own sync client propagates it to the cloud from there), then
# finish + persist project.yaml.
report_copy <- copy_report_to_sync_folder(project_id, skill_dir = skill, html_path)
yaml::write_yaml(proj_yaml, hfc_path(cfg$code_output_dir, "project.yaml"))

message("Done. HTML: ", html_path)
message("Product root: ", hfc_root(cfg$code_output_dir))
message("Issue tracking folder: ", ctx$local_dir %||% "(unavailable)", " (", ctx$reason %||% "", ")")
if (merge_pending) {
    message("MERGE_PENDING: review merged_issue_tracking.xlsx before overwriting issue_tracking.xlsx.")
    message("  Rscript .claude/skills/hfc-fieldloop/scripts/commit_merged_issue_tracking.R merged_issue_tracking.xlsx")
} else {
    message("issue_tracking.xlsx created fresh (first build).")
}
message("Report copy: ", report_copy$status, " (", report_copy$reason %||% "", ") ", report_copy$dest_path %||% "(none)")
message("When field edits issue_tracking, run: Process HFC feedback")
