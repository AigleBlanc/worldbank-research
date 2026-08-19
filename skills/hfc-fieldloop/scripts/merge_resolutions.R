# Merge today's resolutions/ clone (Status/Corrections edits from a "Process
# HFC feedback" pass) back into the live issue_tracking.xlsx. Non-blocking:
# writes merged_issue_resolutions.xlsx next to issue_tracking.xlsx and exits
# — it never overwrites the live file itself. The agent reviews the merged
# file and confirms via AskUserQuestion, then runs
# commit_merged_issue_tracking.R to actually replace issue_tracking.xlsx.
#
# Usage: Rscript merge_resolutions.R   (skills/hfc-fieldloop/config.json must already be configured)

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
source(file.path(lib, "sync_fpaths.R"))
source(file.path(lib, "issue_store.R"))
source(file.path(lib, "verify_merge.R"))

cfg_ctx <- require_fieldloop_config_ready(skill)
cfg <- cfg_ctx$cfg
entity_label <- load_entity_label(cfg$code_output_dir)
group_label <- load_group_label(cfg$code_output_dir)
ctx <- fetch_issue_tracking(skill_dir = skill, entity_label = entity_label, group_label = group_label)
current <- ctx$tbl
if (is.null(current)) stop("No issue_tracking.xlsx found — run the setup build first.")

clone <- read_resolution_clone(ctx, entity_label = entity_label, group_label = group_label)
if (is.null(clone)) {
  stop("No resolutions/ clone found for today — run `apply_feedback.R clone` first.")
}

# Only overwrite Status/Corrections/Correction Author for rows the agent
# actually touched today (record_touched_id(), issue_store.R) — protects a
# concurrent field/RA edit made directly to the live file on any other row
# from being silently clobbered by the clone's stale value for it.
touched_ids <- read_touched_ids(ctx)
merged <- merge_resolution_updates(current, clone, touched_ids = touched_ids)

v <- verify_resolution_merge(current, clone, merged)
message(format_merge_verification(v))
if (!isTRUE(v$ok)) {
  stop("merge_resolutions.R: verification failed — merged_issue_resolutions.xlsx NOT written. See the verification output above.")
}

write_named_tracking_file(ctx, merged, "merged_issue_resolutions.xlsx", entity_label = entity_label, group_label = group_label)

# Scoped to touched_ids, matching what merge_resolution_updates() actually
# applied — an untouched row's differing clone value is never merged in, so
# it shouldn't be counted as a "change from this pass" either.
n_changed <- sum(as.character(current$finding_id) %in% touched_ids &
                 current$finding_id %in% clone$finding_id &
                 (current$status != clone$status[match(current$finding_id, clone$finding_id)]))
message("Wrote merged_issue_resolutions.xlsx (", nrow(merged), " rows, ", n_changed, " Status changes from this pass).")
message("Review it, then run commit_merged_issue_tracking.R to replace issue_tracking.xlsx.")
