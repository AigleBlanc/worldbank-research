# Refresh hfc/outputs/report.html after a "Process HFC feedback" pass —
# re-runs M1-M13 against the latest data (data/intermediate/ if any fixes
# were applied, else data/raw/) using the project's already-confirmed
# hfc/config/role_map.yaml + modules.yaml (read as-is, never re-profiled or
# re-derived), then drops from the REPORT (not from issue_tracking.xlsx,
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
# Usage: Rscript rebuild_report.R <project_root> [--open]

`%||%` <- function(a, b) {
    if (is.null(a) || length(a) == 0) return(b)
    if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(as.character(a))))) return(b)
    a
}

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
source(file.path(lib, "sync_folder.R"))
source(file.path(lib, "issue_store.R"))

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("Usage: rebuild_report.R <project_root> [--open]")
project_root <- normalizePath(decode_file_arg(args[[1]]), mustWork = FALSE)
do_open <- "--open" %in% args

suppressPackageStartupMessages({
    library(haven); library(dplyr); library(readr); library(openxlsx)
    library(yaml); library(jsonlite); library(lubridate); library(tibble)
})

require_sync_folder_ready(project_root, skill)

role_map_path <- hfc_path(project_root, "config", "role_map.yaml")
modules_path <- hfc_path(project_root, "config", "modules.yaml")
proj_yaml_path <- hfc_path(project_root, "project.yaml")
if (!file.exists(role_map_path) || !file.exists(modules_path) || !file.exists(proj_yaml_path)) {
    stop(
    "No prior build found for this project (missing role_map.yaml / modules.yaml / project.yaml under hfc/config or hfc/) — ",
    "run the setup build first: Rscript run_setup_build.R \"", project_root, "\""
    )
}

roles <- yaml::read_yaml(role_map_path)
modules <- yaml::read_yaml(modules_path)
proj_yaml <- yaml::read_yaml(proj_yaml_path)
data_rel <- proj_yaml$data_file
project_id <- proj_yaml$project_id %||% basename(project_root)
entity_label <- roles$entity_label %||% NA_character_

message("Loading latest data for: ", project_root)
ds <- load_latest_dataset(project_root, data_rel)

form_path <- hfc_path(project_root, "instruments", "form.xlsx")
if (file.exists(form_path) && exists("parse_form_relevance", mode = "function")) {
    attr(ds, "hfc_form_map") <- parse_form_relevance(form_path)
}

module_notes_path <- hfc_path(project_root, "config", "module_notes.yaml")
module_notes <- if (file.exists(module_notes_path)) yaml::read_yaml(module_notes_path) else NULL

res <- run_checks_and_write_registry(project_root, ds, roles, modules, skill)

ctx <- fetch_issue_tracking(project_root, skill_dir = skill, entity_label = entity_label)
if (is.null(ctx$tbl)) {
    stop("No issue_tracking.xlsx found in the shared sync folder — nothing to filter the report against. Run the setup build first.")
}
filtered <- filter_findings_by_tracking_status(res$findings, ctx$tbl)
message("Findings after dropping Resolved/untracked: ", nrow(filtered), " of ", nrow(res$findings))

report_cfg <- list(map_focus = roles$map_focus %||% "country")
html_path <- write_html_report(
    filtered, project_root, project_id, open = do_open,
    roles = roles, ds = ds, report_cfg = report_cfg, module_notes = module_notes,
    stats = res$stats, modules = modules
)

report_copy <- copy_report_to_sync_folder(project_root, project_id, skill_dir = skill, html_path)

message("Done. HTML: ", html_path)
message("Report copy: ", report_copy$status, " (", report_copy$reason %||% "", ") ", report_copy$dest_path %||% "(none)")
