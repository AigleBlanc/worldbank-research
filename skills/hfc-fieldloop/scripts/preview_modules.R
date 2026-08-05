# Build + open hfc/check_modules.html — a tree preview of every M1-M13
# module's proposed default (on/off, rationale, thresholds/variables), shown
# to the user BEFORE the accept-all/review pace question (SKILL.md A2.3).
# Read-only against hfc/config/: reflects modules.yaml/role_map.yaml if they
# already exist (a rebuild-preview), else fresh profiler defaults — never
# writes either file itself, that only happens once the user actually
# confirms in chat.
#
# Usage: Rscript preview_modules.R <project_root> [--open]

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
project_root <- if (length(args) && !startsWith(args[[1]], "--")) {
    normalizePath(decode_file_arg(args[[1]]), mustWork = FALSE)
} else {
    project_root_from_skill(skill)
}
do_open <- "--open" %in% args

suppressPackageStartupMessages({
    library(haven); library(dplyr); library(readr); library(openxlsx)
    library(yaml); library(jsonlite); library(lubridate); library(tibble)
})

require_sync_folder_ready(project_root, skill)

disc <- discover_project(project_root, create_raw_if_missing = TRUE)
if (identical(disc$status, "missing_data")) {
    stop("No microdata found under data/raw/. Drop a .dta/.csv/.xlsx and re-run.")
}
data_path <- disc$data$path

message("Loading: ", data_path)
ds <- load_microdata(data_path)

media_folder <- disc$media_folder %||% NA_character_
if (is.null(media_folder) || (length(media_folder) == 1 && is.na(media_folder))) {
    mf <- discover_media_folder(project_root, data_path)
    media_folder <- mf$path
}

roles <- profile_roles(ds, media_folder = media_folder)

modules_path <- hfc_path(project_root, "config", "modules.yaml")
modules <- if (file.exists(modules_path)) yaml::read_yaml(modules_path) else default_modules(roles)

# Overlay any already-confirmed required-fields-gate answers (A1 runs before
# A2, so role_map.yaml may already hold a partial config) — read-only, never
# written back here.
role_map_path <- hfc_path(project_root, "config", "role_map.yaml")
if (file.exists(role_map_path)) {
    saved <- yaml::read_yaml(role_map_path)
    if (!is.null(saved$entity_label) && nzchar(as.character(saved$entity_label))) {
        roles$entity_label <- as.character(saved$entity_label)
    }
    if (!is.null(saved$important_vars) && length(saved$important_vars)) {
        roles$important_vars <- unlist(saved$important_vars)
    }
}

out <- write_check_modules_preview_html(project_root, roles, modules, open = do_open)
message("Wrote ", out)
