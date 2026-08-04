### Main R script template — HFC FieldLoop project package
#
# Change ONLY the path line below for a new machine / project location.
# Copy of this file is written to hfc/code/main.R on setup build (see
# write_main_r() in scripts/lib/build_outputs.R).
#
# Normal use is entirely through chat ("Run HFC FieldLoop", "Process HFC
# feedback") — the agent runs every command below for you. This file is a
# reference/cheat-sheet for running any step by hand from a terminal.
# OneDrive must already be configured and signed in (assets/lib/onedrive.json
# "enabled": true + setup_onedrive_auth.R) — every script below requires it,
# there is no local-only mode.

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

# Set project path (ONLY place to change for a new machine) ----
path <- "your/path/to/survey_project/"

# Examples:
# path <- "C:/Users/you/Documents/my_survey/"
# path <- "/Users/you/Documents/my_survey/"

skill <- file.path(path, ".claude", "skills", "hfc-fieldloop")
if (!dir.exists(skill)) {
  stop("Expected skill at: ", skill, "\nThis skill is deployed as .claude/ in the survey project root (see the skill's own README.md) — not a bare hfc-fieldloop/ folder.")
}

# ---------------------------------------------------------------------------
# Pipeline A — Setup build (after confirming modules in chat)
# Writes hfc/code/checks/, hfc/registry/findings.csv, issue_tracking.xlsx
# (OneDrive), hfc/outputs/report.html.
# ---------------------------------------------------------------------------
# Rscript file.path(skill, "scripts", "run_setup_build.R") path --open
# Optional: --sample N
#
# On a rebuild (issue_tracking.xlsx already exists), this does NOT overwrite
# it directly — it writes merged_issue_tracking.xlsx and prints MERGE_PENDING.
# Review it, then:
# Rscript file.path(skill, "scripts", "commit_merged_issue_tracking.R") path "merged_issue_tracking.xlsx"

# ---------------------------------------------------------------------------
# Pipeline B — Post-feedback: interpret Open+RIL-Comment rows, write fixes
# ---------------------------------------------------------------------------
# Rscript file.path(skill, "scripts", "apply_feedback.R") "clone"  path
# Rscript file.path(skill, "scripts", "apply_feedback.R") "list-open" path
# (agent writes hfc/code/resolutions/<Issue ID>.R defining fix(ds) -> ds, then:)
# Rscript file.path(skill, "scripts", "apply_feedback.R") "apply" path --finding-id "<id>" --corrections "<text>"
# Rscript file.path(skill, "scripts", "apply_feedback.R") "needs-review" path --finding-id "<id>"
# Rscript file.path(skill, "scripts", "merge_resolutions.R") path
# (review merged_issue_resolutions.xlsx, then:)
# Rscript file.path(skill, "scripts", "commit_merged_issue_tracking.R") path "merged_issue_resolutions.xlsx"

# ---------------------------------------------------------------------------
# Re-run a single check module standalone (reproduces exactly that module's
# findings for the current data) — generated fresh into hfc/code/checks/
# every setup build, one file per confirmed-on module:
# ---------------------------------------------------------------------------
# Rscript file.path(path, "hfc", "code", "checks", "M1_completion.R")
# (M2_duplicates.R, M4_duration.R, M6_outliers.R, ... — whichever modules are on)

message("FieldLoop main.R ready. path = ", path)
message("Use chat prompts: 'Run HFC FieldLoop' then later 'Process HFC feedback'.")
message("Or call scripts under: ", file.path(skill, "scripts"))
