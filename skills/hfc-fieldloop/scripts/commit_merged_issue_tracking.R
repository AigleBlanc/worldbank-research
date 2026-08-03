# Overwrite the live issue_tracking.xlsx with an already-reviewed merged
# file (merged_issue_tracking.xlsx or merged_issue_resolutions.xlsx), then
# delete the merged file. This is the ONLY script that ever overwrites the
# live file — only ever run after the agent has shown the user the merged
# file and gotten explicit AskUserQuestion confirmation, with a warning that
# this replaces the shared live file.
#
# Usage: Rscript commit_merged_issue_tracking.R <project_root> <merged_filename> [--no-onedrive]
#   e.g. Rscript commit_merged_issue_tracking.R . merged_issue_tracking.xlsx
#        Rscript commit_merged_issue_tracking.R . merged_issue_resolutions.xlsx

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(as.character(a))))) return(b)
  a
}

.resolve_skill <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", ca, value = TRUE)
  sp <- if (length(fa)) gsub("~+~", " ", sub("^--file=", "", fa[[1]]), fixed = TRUE) else NA_character_
  if (!is.na(sp) && file.exists(sp)) return(normalizePath(file.path(dirname(sp), "..")))
  if (file.exists("hfc-fieldloop/scripts/lib/utils.R")) return(normalizePath("hfc-fieldloop"))
  if (file.exists("scripts/lib/utils.R")) return(normalizePath(".."))
  stop("Cannot locate hfc-fieldloop")
}
skill <- .resolve_skill()
lib <- file.path(skill, "scripts", "lib")
source(file.path(lib, "utils.R"))
source(file.path(lib, "build_outputs.R"))
source(file.path(lib, "onedrive_drive.R"))
source(file.path(lib, "issue_store.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: commit_merged_issue_tracking.R <project_root> <merged_filename> [--no-onedrive]")
project_root <- normalizePath(decode_file_arg(args[[1]]))
merged_filename <- args[[2]]
no_onedrive <- "--no-onedrive" %in% args

ctx <- fetch_issue_tracking(project_root, skill_dir = skill, force_local = no_onedrive)
merged <- read_named_tracking_file(ctx, merged_filename)
if (is.null(merged)) stop("No such merged file found: ", merged_filename)

commit_issue_tracking(project_root, merged, skill_dir = skill, fetch_ctx = ctx)
delete_named_tracking_file(ctx, merged_filename)

message("Committed ", merged_filename, " -> issue_tracking.xlsx (", nrow(merged), " rows). ", merged_filename, " deleted.")
