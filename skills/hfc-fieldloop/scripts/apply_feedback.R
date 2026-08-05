# Post-feedback pipeline — thin CLI over scripts/lib/apply_feedback_helpers.R.
# The fix logic itself is agent-authored per finding (hfc/code/resolutions/<id>.R,
# defining fix(ds) -> ds) — there is no built-in fix-classification engine.
# Trigger: any row with Status=Open and a non-empty RIL Comment is eligible
# (no separate Accepted gate). The agent reads each such row, decides the
# fix, writes hfc/code/resolutions/<id>.R, then calls `apply` with the Corrections text
# — all against today's resolutions/ clone, never issue_tracking.xlsx
# directly (see scripts/merge_resolutions.R for how the clone gets folded
# back into the live file, after AskUserQuestion confirmation).
#
# Usage (a shared sync folder must already be configured — no local mode):
#   Rscript apply_feedback.R clone <project_root>
#   Rscript apply_feedback.R list-open <project_root>
#   Rscript apply_feedback.R apply <project_root> --finding-id <id> --corrections "<text>"
#   Rscript apply_feedback.R needs-review <project_root> --finding-id <id>

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(as.character(a))))) return(b)
  a
}

# Step 1: find the skill's own root dir, same as run_setup_build.R.
.resolve_skill <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", ca, value = TRUE)
  sp <- if (length(fa)) gsub("~+~", " ", sub("^--file=", "", fa[[1]]), fixed = TRUE) else NA_character_
  if (!is.na(sp) && file.exists(sp)) return(normalizePath(file.path(dirname(sp), "..")))
  if (file.exists(".claude/skills/hfc-fieldloop/scripts/lib/utils.R")) return(normalizePath(".claude/skills/hfc-fieldloop"))
  if (file.exists("hfc-fieldloop/scripts/lib/utils.R")) return(normalizePath("hfc-fieldloop"))
  if (file.exists("scripts/lib/utils.R")) return(normalizePath(".."))
  stop("Cannot locate hfc-fieldloop")
}
skill <- .resolve_skill()
lib <- file.path(skill, "scripts", "lib")
source(file.path(lib, "utils.R"))
source(file.path(lib, "build_outputs.R"))
source(file.path(lib, "sync_folder.R"))
source(file.path(lib, "issue_store.R"))
source(file.path(lib, "apply_feedback_helpers.R"))

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(yaml)
})

# Step 2: parse CLI args — subcommand, project root, --finding-id, --corrections.
args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) {
  stop("Usage: apply_feedback.R <clone|list-open|apply|needs-review> <project_root> [--finding-id <id>] [--corrections <text>]")
}
mode <- args[[1]]
rest <- args[-1]
project_root <- if (length(rest) && !startsWith(rest[[1]], "--")) {
  normalizePath(decode_file_arg(rest[[1]]))
} else {
  project_root_from_skill(skill)
}
opt_val <- function(flag) {
  i <- match(flag, rest)
  if (!is.na(i) && i < length(rest)) rest[[i + 1]] else NA_character_
}
finding_id <- opt_val("--finding-id")
corrections_text <- opt_val("--corrections")

# Step 2b: a configured shared sync folder is required — no local fallback.
require_sync_folder_ready(project_root, skill)

# Step 3: dispatch.
if (mode == "clone") {
  res <- clone_for_resolution_pass(project_root, skill_dir = skill)
  message("Resolutions clone ", res$status, " (", res$n, " rows).")
} else if (mode == "list-open") {
  open_rows <- list_open_commented_rows(project_root, skill_dir = skill)
  out_path <- hfc_path(project_root, "registry", "fix_candidates.csv")
  write_csv(open_rows, out_path)
  message("Open + commented rows: ", nrow(open_rows))
  message("Wrote ", out_path)
} else if (mode == "apply") {
  if (is.na(finding_id)) stop("apply requires --finding-id <id>")
  if (is.na(corrections_text)) stop("apply requires --corrections \"<text>\"")
  res <- apply_one_fix(project_root, finding_id, corrections_text, skill_dir = skill)
  message("Fixed ", finding_id, " -> ", res$intermediate_path)
  message("Status set to Resolved in today's resolutions clone.")
} else if (mode == "needs-review") {
  if (is.na(finding_id)) stop("needs-review requires --finding-id <id>")
  mark_needs_review(project_root, finding_id, skill_dir = skill)
  message("Status set to Needs Review for ", finding_id, " in today's resolutions clone.")
} else {
  stop("Unknown mode: ", mode, " (expected clone | list-open | apply | needs-review)")
}
