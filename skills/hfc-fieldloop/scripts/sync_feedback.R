# Sync the single issue_tracking.xlsx with whichever backend is live
# (OneDrive if configured, else local hfc/output/) — thin wrapper over
# scripts/lib/issue_store.R's fetch_issue_tracking()/commit_issue_tracking().
# Rscript sync_feedback.R <project_root> [pull|push] [--no-onedrive]

# Step 1: parse CLI args — project root + mode.
args <- commandArgs(trailingOnly = TRUE)
proj <- if (length(args) >= 1) normalizePath(args[[1]]) else getwd()
mode <- if (length(args) >= 2 && !startsWith(args[[2]], "--")) args[[2]] else "pull"
no_onedrive <- "--no-onedrive" %in% args

# Step 2: find the skill's own root dir (a few more fallback strategies than
# the other two scripts, since this one may be run from odd working dirs).
ca <- commandArgs(trailingOnly = FALSE)
fa <- grep("^--file=", ca, value = TRUE)
sp <- if (length(fa)) gsub("~+~", " ", sub("^--file=", "", fa[[1]]), fixed = TRUE) else NA_character_
skill <- if (!is.na(sp) && file.exists(sp)) {
    normalizePath(file.path(dirname(sp), ".."))
} else if (dir.exists(file.path(proj, "hfc-fieldloop"))) {
    normalizePath(file.path(proj, "hfc-fieldloop"))
} else if (file.exists("hfc-fieldloop/scripts/lib/utils.R")) {
    normalizePath("hfc-fieldloop")
} else stop("Cannot locate skill")
source(file.path(skill, "scripts", "lib", "utils.R"))
source(file.path(skill, "scripts", "lib", "build_outputs.R"))
source(file.path(skill, "scripts", "lib", "onedrive_drive.R"))
source(file.path(skill, "scripts", "lib", "issue_store.R"))

suppressPackageStartupMessages({
    library(readr); library(dplyr)
})

if (mode == "push") {
    tracking_csv <- hfc_path(proj, "registry", "issue_tracking.csv")
    if (!file.exists(tracking_csv)) stop("No issue_tracking.csv — run setup build first")
    fb <- as_tibble(read_issue_tracking(tracking_csv))
    res <- commit_issue_tracking(proj, fb, skill_dir = skill, force_local = no_onedrive)
    message("Pushed issue_tracking: ", res$status, " (", res$backend, ") ", res$url %||% NA)
} else if (mode == "pull") {
    ctx <- fetch_issue_tracking(proj, skill_dir = skill, force_local = no_onedrive)
    if (is.null(ctx$tbl)) {
        message("No issue_tracking.xlsx found on ", ctx$backend, " (", ctx$reason %||% "", ")")
    } else {
        commit_issue_tracking(proj, ctx$tbl, skill_dir = skill, fetch_ctx = ctx)
        message("Synced local registry copy from ", ctx$backend, " (n=", nrow(ctx$tbl), ")")
    }
} else {
    stop("mode must be pull | push")
}
