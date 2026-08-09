# Writes hfc/config/modules.yaml — a commented, human-readable draft of
# every M1-M13 module's proposed default (on/off, description, thresholds/
# variables) — shown to the user BEFORE the accept-all/review confirmation
# (SKILL.md A2), so the agent can give them a real, already-existing path to
# open and review/edit directly, in addition to the chat tabs. Reflects
# modules.yaml/role_map.yaml if they already exist (a rebuild-preview,
# re-serialized with fresh comments but the same values), else fresh
# profiler defaults. role_map.yaml itself is read-only here, never written.
#
# Usage: Rscript preview_modules.R
# Reads skills/hfc-fieldloop/config.json for input_data_dir/media_dir/code_output_dir.

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
source(file.path(lib, "sync_fpaths.R"))
source(file.path(lib, "issue_store.R"))

suppressPackageStartupMessages({
    library(haven); library(dplyr); library(readr); library(openxlsx)
    library(yaml); library(jsonlite); library(lubridate); library(tibble)
})

ctx <- require_fieldloop_config_ready(skill)
cfg <- ctx$cfg
modules_path <- hfc_path(cfg$code_output_dir, "config", "modules.yaml")

# --blank: write an empty, pre-fillable draft immediately after discovery,
# before any role profiling -- SKILL.md A1's Setup window mentions this
# file's path so the user can hand-edit whatever they already know (module
# on/off, thresholds, variables) instead of waiting to be asked. No data
# dependency at all -- skips discovery/loading/profiling entirely.
args <- commandArgs(trailingOnly = TRUE)
if ("--blank" %in% args) {
    out <- write_commented_modules_yaml(list(), modules_path)
    message("Wrote blank draft: ", out)
    quit(save = "no", status = 0)
}

disc <- discover_project(cfg$input_data_dir)
if (!identical(disc$status, "found")) {
    stop("No microdata found in input_data_dir (", cfg$input_data_dir, "). Drop a .dta/.csv/.xlsx there and re-run.")
}
data_path <- disc$data$path

message("Loading: ", data_path)
ds <- load_microdata(data_path)

media_folder <- cfg$media_dir %||% NA_character_

roles <- profile_roles(ds, media_folder = media_folder, roster_candidate = disc$roster_candidate)

# Overlay any already-confirmed required-fields-gate answers (A1 runs before
# A2, so role_map.yaml may already hold a partial config) — read-only, never
# written back here. Applied BEFORE default_modules(roles) below, so these
# adjustments actually reach the fresh guess (important_vars etc. feed
# M6/M9/M13's guessed variable lists).
role_map_path <- hfc_path(cfg$code_output_dir, "config", "role_map.yaml")
if (file.exists(role_map_path)) {
    saved <- yaml::read_yaml(role_map_path)
    if (!is.null(saved$entity_label) && nzchar(as.character(saved$entity_label))) {
        roles$entity_label <- as.character(saved$entity_label)
    }
    if (!is.null(saved$group_label) && nzchar(as.character(saved$group_label))) {
        roles$group_label <- as.character(saved$group_label)
    }
    if (!is.null(saved$important_vars) && length(saved$important_vars)) {
        roles$important_vars <- unlist(saved$important_vars)
    }
    if (!is.null(saved$missingness_extra_vars) && length(saved$missingness_extra_vars)) {
        roles$missingness_extra_vars <- unlist(saved$missingness_extra_vars)
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

# Merge fresh guesses with whatever's already on disk -- the blank draft
# from the earlier --blank pass, possibly hand-edited by the user in the
# Setup window (SKILL.md A1). Never used wholesale: any field the user left
# untouched still needs a real guess, not a blank.
guessed <- default_modules(roles)
prefilled <- if (file.exists(modules_path)) yaml::read_yaml(modules_path) else list()
modules <- merge_prefilled_modules(guessed, prefilled)

out <- write_commented_modules_yaml(modules, modules_path)
message("Wrote ", out)
