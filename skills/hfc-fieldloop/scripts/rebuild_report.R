# Refresh hfc/outputs/<MMDD>_HFCs.html after a "Process HFC feedback" pass —
# re-runs M1-M13 against the latest data (<sibling of input_data_dir>/intermediate/
# if any fixes were applied, else the original file in input_data_dir) using
# the project's already-confirmed hfc/config/role_map.yaml + modules.yaml
# (read as-is, never re-profiled or re-derived), then drops from the REPORT (not from issue_tracking.xlsx,
# which keeps full history unchanged) any finding whose live-tracking Status
# is now Resolved, or whose Issue ID no longer appears in the live tracking
# file at all.
#
# Deliberately NOT another call to run_setup_build.R: that script always
# diffs fresh findings against the live tracking file via
# merge_preserve_existing() and stops with MERGE_PENDING for a fresh
# AskUserQuestion confirm — wrong here, where the goal is only to *read* the
# already-committed live file and filter the report against it, never to
# merge into it again.
#
# Usage: Rscript rebuild_report.R [--open]

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
source(file.path(lib, "form_logic.R"))
source(file.path(lib, "run_checks.R"))
source(file.path(lib, "build_outputs.R"))
source(file.path(lib, "module_desc.R"))
source(file.path(lib, "pipeline_core.R"))
source(file.path(lib, "sync_fpaths.R"))
source(file.path(lib, "issue_store.R"))

args <- commandArgs(trailingOnly = TRUE)
do_open <- "--open" %in% args

suppressPackageStartupMessages({
    library(haven); library(dplyr); library(readr); library(openxlsx)
    library(yaml); library(jsonlite); library(lubridate); library(tibble)
})

cfg_ctx <- require_fieldloop_config_ready(skill)
cfg <- cfg_ctx$cfg

role_map_path <- hfc_path(cfg$code_output_dir, "config", "role_map.yaml")
modules_path <- hfc_path(cfg$code_output_dir, "config", "modules.yaml")
proj_yaml_path <- hfc_path(cfg$code_output_dir, "project.yaml")
if (!file.exists(role_map_path) || !file.exists(modules_path) || !file.exists(proj_yaml_path)) {
    stop(
    "No prior build found (missing role_map.yaml / modules.yaml / project.yaml under hfc/config or hfc/) — ",
    "run the setup build first: Rscript run_setup_build.R"
    )
}

roles <- yaml::read_yaml(role_map_path)
modules <- yaml::read_yaml(modules_path)
proj_yaml <- yaml::read_yaml(proj_yaml_path)
data_rel <- proj_yaml$data_file
project_id <- proj_yaml$project_id %||% derive_project_id(cfg$input_data_dir)
entity_label <- roles$entity_label %||% NA_character_
group_label <- roles$group_label %||% NA_character_

message("Loading latest data for: ", cfg$input_data_dir)
ds <- load_latest_dataset(cfg$input_data_dir, data_rel)

form_path <- hfc_path(cfg$code_output_dir, "instruments", "form.xlsx")
if (file.exists(form_path) && exists("parse_form_relevance", mode = "function")) {
    attr(ds, "hfc_form_map") <- parse_form_relevance(form_path)
}

module_notes_path <- hfc_path(cfg$code_output_dir, "config", "module_notes.yaml")
module_notes <- if (file.exists(module_notes_path)) yaml::read_yaml(module_notes_path) else NULL

# Reload the roster/target-sample list whenever one was found (read-only,
# never mutated, never copied) — not just when the confirmed completion
# signal is "roster": check_m1()'s replacement-sample analysis needs it
# independently of which signal is actually driving completion.
target_ds <- NULL
if (!is.null(roles$completion_roster_candidate) && !is.na(roles$completion_roster_candidate$path %||% NA_character_)) {
    target_ds <- tryCatch(load_microdata(roles$completion_roster_candidate$path), error = function(e) NULL)
}
res <- run_checks_and_write_issues(cfg$code_output_dir, ds, roles, modules, skill, target_ds = target_ds)

ctx <- fetch_issue_tracking(skill_dir = skill, entity_label = entity_label, group_label = group_label)
if (is.null(ctx$tbl)) {
    stop("No issue_tracking.xlsx found in the configured OneDrive output folder — nothing to filter the report against. Run the setup build first.")
}
filtered <- filter_findings_by_tracking_status(res$findings, ctx$tbl)
message("Findings after dropping Resolved/untracked: ", nrow(filtered), " of ", nrow(res$findings))

report_cfg <- list(map_focus = roles$map_focus %||% "country")
html_path <- write_html_report(
    filtered, cfg$code_output_dir, project_id, open = do_open,
    roles = roles, ds = ds, report_cfg = report_cfg, module_notes = module_notes,
    stats = res$stats, modules = modules
)

report_copy <- copy_report_to_sync_folder(project_id, skill_dir = skill, html_path)

message("Done. HTML: ", html_path)
message("Report copy: ", report_copy$status, " (", report_copy$reason %||% "", ") ", report_copy$dest_path %||% "(none)")
