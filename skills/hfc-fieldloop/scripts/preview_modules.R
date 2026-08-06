# Build + open hfc/check_modules.html — a tree preview of every M1-M13
# module's proposed default (on/off, rationale, thresholds/variables), shown
# to the user BEFORE the accept-all/review pace question (SKILL.md A2.3).
# Read-only against hfc/config/: reflects modules.yaml/role_map.yaml if they
# already exist (a rebuild-preview), else fresh profiler defaults — never
# writes either file itself, that only happens once the user actually
# confirms in chat.
#
# Usage: Rscript preview_modules.R [--open]
# Reads skills/hfc-fieldloop/config.json for input_data_dir/media_dir/code_output_dir.

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
source(file.path(lib, "discover.R"))
source(file.path(lib, "profile_roles.R"))
source(file.path(lib, "build_outputs.R"))
source(file.path(lib, "module_desc.R"))
source(file.path(lib, "check_modules_preview.R"))
source(file.path(lib, "sync_folder.R"))
source(file.path(lib, "issue_store.R"))

args <- commandArgs(trailingOnly = TRUE)
do_open <- "--open" %in% args

suppressPackageStartupMessages({
    library(haven); library(dplyr); library(readr); library(openxlsx)
    library(yaml); library(jsonlite); library(lubridate); library(tibble)
})

ctx <- require_fieldloop_config_ready(skill)
cfg <- ctx$cfg

disc <- discover_project(cfg$input_data_dir)
if (!identical(disc$status, "found")) {
    stop("No microdata found in input_data_dir (", cfg$input_data_dir, "). Drop a .dta/.csv/.xlsx there and re-run.")
}
data_path <- disc$data$path

message("Loading: ", data_path)
ds <- load_microdata(data_path)

media_folder <- cfg$media_dir %||% NA_character_

roles <- profile_roles(ds, media_folder = media_folder, roster_candidate = disc$roster_candidate)

modules_path <- hfc_path(cfg$code_output_dir, "config", "modules.yaml")
modules <- if (file.exists(modules_path)) yaml::read_yaml(modules_path) else default_modules(roles)

# Overlay any already-confirmed required-fields-gate answers (A1 runs before
# A2, so role_map.yaml may already hold a partial config) — read-only, never
# written back here.
role_map_path <- hfc_path(cfg$code_output_dir, "config", "role_map.yaml")
if (file.exists(role_map_path)) {
    saved <- yaml::read_yaml(role_map_path)
    if (!is.null(saved$entity_label) && nzchar(as.character(saved$entity_label))) {
        roles$entity_label <- as.character(saved$entity_label)
    }
    if (!is.null(saved$important_vars) && length(saved$important_vars)) {
        roles$important_vars <- unlist(saved$important_vars)
    }
    if (!is.null(saved$completion_primary_signal) && nzchar(as.character(saved$completion_primary_signal))) {
        roles$completion_primary_signal <- as.character(saved$completion_primary_signal)
    }
    if (!is.null(saved$treatment_control_col) && nzchar(as.character(saved$treatment_control_col))) {
        roles$treatment_control_col <- as.character(saved$treatment_control_col)
    }
    if (!is.null(saved$geo_group_col) && nzchar(as.character(saved$geo_group_col))) {
        roles$geo_group_col <- as.character(saved$geo_group_col)
    }
}

out <- write_check_modules_preview_html(cfg, roles, modules, open = do_open)
message("Wrote ", out)
