# Merge today's intermediate/ snapshot into the live issue_tracking.xlsx.
# Non-blocking: writes merged_issue_tracking.xlsx next to issue_tracking.xlsx
# and exits — it never overwrites the live file itself. The agent reviews the
# merged file and confirms via AskUserQuestion, then runs
# commit_merged_issue_tracking.R to actually replace issue_tracking.xlsx.
#
# Usage: Rscript merge_issues.R <project_root> [--no-onedrive]

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
if (!length(args)) stop("Usage: merge_issues.R <project_root> [--no-onedrive]")
project_root <- normalizePath(decode_file_arg(args[[1]]))
no_onedrive <- "--no-onedrive" %in% args

suppressPackageStartupMessages({ library(dplyr) })

ctx <- fetch_issue_tracking(project_root, skill_dir = skill, force_local = no_onedrive)
current <- ctx$tbl

if (is.null(current)) {
  message("No existing issue_tracking.xlsx — nothing to merge (first-ever build writes it directly).")
  quit(save = "no", status = 0)
}

snapshot <- read_tracking_snapshot(ctx)
if (is.null(snapshot)) {
  stop("No snapshot found for today under intermediate/ — run the setup build first.")
}

merged <- merge_preserve_existing(current, snapshot)
res <- write_named_tracking_file(ctx, merged, "merged_issue_tracking.xlsx")

message("Wrote merged_issue_tracking.xlsx (", nrow(merged), " rows: ", nrow(current), " existing + ",
        nrow(merged) - nrow(current), " new).")
message("Review it, then run commit_merged_issue_tracking.R to replace issue_tracking.xlsx.")
