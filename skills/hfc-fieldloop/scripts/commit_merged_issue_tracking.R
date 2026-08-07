# Overwrite the live issue_tracking.xlsx with an already-reviewed merged
# file (merged_issue_tracking.xlsx or merged_issue_resolutions.xlsx), then
# delete the merged file. This is the ONLY script that ever overwrites the
# live file — only ever run after the agent has shown the user the merged
# file and gotten explicit AskUserQuestion confirmation, with a warning that
# this replaces the shared live file.
#
# Usage: Rscript commit_merged_issue_tracking.R <merged_filename>
#   (skills/hfc-fieldloop/config.json must already be configured)
#   e.g. Rscript commit_merged_issue_tracking.R merged_issue_tracking.xlsx
#        Rscript commit_merged_issue_tracking.R merged_issue_resolutions.xlsx

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

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: commit_merged_issue_tracking.R <merged_filename>")
merged_filename <- args[[1]]

cfg_ctx <- require_fieldloop_config_ready(skill)
cfg <- cfg_ctx$cfg
entity_label <- load_entity_label(cfg$code_output_dir)
group_label <- load_group_label(cfg$code_output_dir)
ctx <- fetch_issue_tracking(skill_dir = skill, entity_label = entity_label, group_label = group_label)
merged <- read_named_tracking_file(ctx, merged_filename, entity_label = entity_label, group_label = group_label)
if (is.null(merged)) stop("No such merged file found: ", merged_filename)

commit_issue_tracking(merged, skill_dir = skill, fetch_ctx = ctx, entity_label = entity_label, group_label = group_label)
delete_named_tracking_file(ctx, merged_filename)

message("Committed ", merged_filename, " -> issue_tracking.xlsx (", nrow(merged), " rows). ", merged_filename, " deleted.")
