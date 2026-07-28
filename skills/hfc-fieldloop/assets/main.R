### Main R script template — HFC FieldLoop project package
#
# Change ONLY the path line below for a new machine / project location.
# Copy of this file is written to code/main.R on setup build.

# Load libraries ----
# Prefer: Rscript hfc-fieldloop/install.R  (once per machine)

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(readr)
  library(openxlsx)
  library(yaml)
  library(jsonlite)
  library(lubridate)
  library(tibble)
})

# Set package path (ONLY place to change for a new machine) ----
path <- "your/path/to/survey_project/"

# Examples:
# path <- "C:/Users/you/Documents/my_survey/"
# path <- "/Users/you/Documents/my_survey/"

skill <- file.path(path, "hfc-fieldloop")
if (!dir.exists(skill)) {
  stop("Expected skill at: ", skill, "\nDrop or symlink hfc-fieldloop/ into the project root.")
}

# ---------------------------------------------------------------------------
# Pipeline A — Setup build (after confirming modules in chat)
# Writes checks, findings, tracking, feedback twin, HTML report.
# ---------------------------------------------------------------------------
# Rscript file.path(skill, "scripts", "run_setup_build.R") path --open
# Optional: --sample N   --no-onedrive

# ---------------------------------------------------------------------------
# Feedback sync (local Excel twin <-> OneDrive when configured)
# ---------------------------------------------------------------------------
# Rscript file.path(skill, "scripts", "sync_feedback.R") path export
# Rscript file.path(skill, "scripts", "sync_feedback.R") path import
# Rscript file.path(skill, "scripts", "sync_feedback.R") path push-audit

# ---------------------------------------------------------------------------
# Pipeline B — Apply accepted field feedback → *_resolved beside raw
# ---------------------------------------------------------------------------
# Rscript file.path(skill, "scripts", "apply_feedback.R") path

# Re-run check modules from project config (optional local refresh) ----
# Uncomment after a successful setup build:
# source(file.path(skill, "scripts", "lib", "utils.R"))
# source(file.path(skill, "scripts", "lib", "run_checks.R"))
# roles <- yaml::read_yaml(file.path(path, "config", "role_map.yaml"))
# modules <- yaml::read_yaml(file.path(path, "config", "modules.yaml"))
# ds <- load_microdata(file.path(path, yaml::read_yaml(file.path(path, "project.yaml"))$data_file))
# findings <- run_check_modules(ds, roles, modules)
# readr::write_csv(findings, file.path(path, "registry", "findings.csv"))

message("FieldLoop main.R ready. path = ", path)
message("Use chat prompts: 'Run HFC FieldLoop' then later 'Process HFC feedback'.")
message("Or call scripts under: ", file.path(skill, "scripts"))
