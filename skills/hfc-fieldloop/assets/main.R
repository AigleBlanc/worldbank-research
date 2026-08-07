### Main R script template — HFC FieldLoop project package
#
# Copy of this file is written to hfc/code/main.R on setup build (see
# write_main_r() in scripts/lib/build_outputs.R), with `skill` and
# `code_output_dir` below substituted for this machine's actual paths.
# input_data_dir/media_dir/onedrive_output_dir are NOT frozen here — they're
# read live from skills/hfc-fieldloop/config.json every time this file runs,
# so editing config.json later (e.g. pointing at a new data drop) is honored
# without regenerating this file.
#
# Normal use is entirely through chat ("Run HFC FieldLoop", "Process HFC
# feedback") — the agent runs every command below for you. This file is a
# reference/cheat-sheet for running any step by hand from a terminal.
# skills/hfc-fieldloop/config.json must already be fully configured — every
# script below requires it, there is no local-only mode.

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(as.character(a))))) return(b)
  a
}

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

# Set skill + code output paths (substituted automatically on setup build;
# only change these by hand if running main.R from an unusual location) ----
skill <- "your/path/to/hfc-fieldloop/"
code_output_dir <- "your/path/to/hfc/output/"

if (!dir.exists(skill)) {
  stop("Expected skill at: ", skill)
}

source(file.path(skill, "scripts", "lib", "sync_fpaths.R"))
cfg <- load_fieldloop_config(skill)
if (!isTRUE(cfg$found)) {
  stop("skills/hfc-fieldloop/config.json is not fully configured. Reason: ", cfg$reason %||% "unknown")
}

# ---------------------------------------------------------------------------
# Pipeline A — Setup build (after confirming modules in chat)
# Writes hfc/code/checks/, hfc/outputs/issues.csv, issue_tracking.xlsx
# (OneDrive), hfc/outputs/report.html.
# ---------------------------------------------------------------------------
# Rscript file.path(skill, "scripts", "run_setup_build.R") --open
# Optional: --sample N
#
# On a rebuild (issue_tracking.xlsx already exists), this does NOT overwrite
# it directly — it writes merged_issue_tracking.xlsx and prints MERGE_PENDING.
# Review it, then:
# Rscript file.path(skill, "scripts", "commit_merged_issue_tracking.R") "merged_issue_tracking.xlsx"

# ---------------------------------------------------------------------------
# Pipeline B — Post-feedback: interpret Open+Comment rows, write fixes
# ---------------------------------------------------------------------------
# Rscript file.path(skill, "scripts", "apply_feedback.R") "clone"
# Rscript file.path(skill, "scripts", "apply_feedback.R") "list-open"
# (agent writes hfc/code/resolutions/<Issue ID>.R defining fix(ds) -> ds, then:)
# Rscript file.path(skill, "scripts", "apply_feedback.R") "apply" --finding-id "<id>" --corrections "<text>"
# Rscript file.path(skill, "scripts", "apply_feedback.R") "needs-review" --finding-id "<id>"
# Rscript file.path(skill, "scripts", "merge_resolutions.R")
# (review merged_issue_resolutions.xlsx, then:)
# Rscript file.path(skill, "scripts", "commit_merged_issue_tracking.R") "merged_issue_resolutions.xlsx"

# ---------------------------------------------------------------------------
# Re-run a single check module standalone (reproduces exactly that module's
# findings for the current data) — generated fresh into hfc/code/checks/
# every setup build, one file per confirmed-on module:
# ---------------------------------------------------------------------------
# Rscript file.path(code_output_dir, "hfc", "code", "checks", "M1_completion.R")
# (M2_duplicates.R, M4_duration.R, M6_outliers.R, ... — whichever modules are on)

message("FieldLoop main.R ready. skill = ", skill, " | code_output_dir = ", code_output_dir)
message("Input data dir (live from config.json): ", cfg$input_data_dir)
message("Use chat prompts: 'Run HFC FieldLoop' then later 'Process HFC feedback'.")
message("Or call scripts under: ", file.path(skill, "scripts"))
