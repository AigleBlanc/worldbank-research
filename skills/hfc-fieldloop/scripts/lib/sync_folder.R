# Local shared-folder access — the folder itself is expected to be kept in
# sync with the cloud by something running outside this skill (in practice,
# the OneDrive desktop app), but nothing here verifies that. This file only
# ever does plain filesystem I/O against whatever path assets/lib/sync_folder.json
# names — it would behave identically pointed at any local folder, synced or
# not. Naming it "sync_folder" rather than "onedrive" reflects that honestly:
# the code has no OneDrive-specific logic or verification anywhere.
#
# One file matters: main_file (issue_tracking.xlsx) — shared with the field
# team, edited collaboratively by the agent, RA, and field team. This shared
# folder is required and is the sole store (see scripts/lib/issue_store.R,
# which builds the actual fetch/commit logic on top of the primitives here,
# plus require_sync_folder_ready() which every user-facing script calls
# first).
#
# Access model: assets/lib/sync_folder.json's "local_path" points at a folder
# already being synced to the cloud by the OneDrive desktop app installed on
# this machine — every read/write here is plain filesystem I/O; OneDrive's
# own sync client (not this code) is what actually gets changes to/from the
# cloud, typically within seconds, with no auth step or API dependency in
# this skill at all.
#
# Target: whoever runs the pipeline points local_path at their OWN OneDrive
# sync folder — no SharePoint site or Team needs to be created. That person
# then manually shares the resulting folder with collaborators (edit access)
# via OneDrive's normal "Specific people" sharing UI — this code never mints
# its own share links, it just reads/writes whatever folder access has
# already been configured by hand.

# Resolve skill root for config lookup — checks the real drop-in convention
# (<project_root>/.claude/skills/hfc-fieldloop/) first, then a couple of
# looser fallbacks for odd working directories.
skill_dir_guess <- function(project_root = NULL) {
    cands <- c(
        if (!is.null(project_root)) file.path(project_root, ".claude", "skills", "hfc-fieldloop"),
        if (!is.null(project_root)) file.path(project_root, "hfc-fieldloop"),
        "hfc-fieldloop",
        if (!is.null(project_root)) file.path(dirname(project_root), "hfc-fieldloop")
    )
    for (c in cands) {
        if (!is.null(c) && dir.exists(c) && file.exists(file.path(c, "scripts", "lib", "sync_folder.R"))) {
        return(normalizePath(c))
        }
    }
    NA_character_
}

# Load local_path/file names from sync_folder.json
# One rule: the only file that matters is assets/lib/sync_folder.json, inside
# the skill itself. Every user edits that one file with their own local
# path/file names — there is no per-project override. local_path must be an
# absolute path to a folder already synced by the OneDrive desktop app; the
# only signal for "is this actually set up" is the explicit `enabled` flag
# (the skill ships `enabled: false`) plus a non-empty `local_path`.
load_sync_folder_config <- function(project_root, skill_dir = NULL) {
    if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess(project_root)
    empty <- function(path = NA_character_, reason = NULL) {
        list(
            found = FALSE, path = path,
            local_path = NA_character_,
            main_file = NA_character_,
            reason = reason
        )
    }
    if (is.null(skill_dir) || is.na(skill_dir)) return(empty(reason = "missing_sync_folder_json"))
    cfg_path <- file.path(skill_dir, "assets", "lib", "sync_folder.json")
    if (!file.exists(cfg_path)) return(empty(reason = "missing_sync_folder_json"))

    raw <- tryCatch(jsonlite::fromJSON(cfg_path), error = function(e) NULL)
    if (is.null(raw)) return(empty(path = normalizePath(cfg_path), reason = "invalid_sync_folder_json"))
    if (!isTRUE(raw$enabled)) return(empty(path = normalizePath(cfg_path), reason = "not_enabled_in_sync_folder_json"))
    if (is.null(raw$local_path) || !nzchar(as.character(raw$local_path))) {
        return(empty(path = normalizePath(cfg_path), reason = "missing_local_path"))
    }

    list(
        found = TRUE,
        path = normalizePath(cfg_path),
        local_path = as.character(raw$local_path),
        main_file = if (!is.null(raw$main_file) && nzchar(as.character(raw$main_file))) {
        as.character(raw$main_file)
        } else "issue_tracking.xlsx"
    )
}

# Create `path` (and any missing parents) if it doesn't exist yet; returns
# `path` unchanged so it can be used inline. Idempotent — safe to call every
# time, whether or not OneDrive's sync client has already materialized it.
ensure_local_folder <- function(path) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
    path
}

# Copy the built HTML report into the configured shared sync folder, so it
# syncs to the cloud alongside issue_tracking.xlsx. No shareable link is
# minted here — the folder's access (e.g. specific external collaborators)
# is set up once by hand in the OneDrive web UI, and anyone already granted
# access to it can find this file there once it syncs.
copy_report_to_sync_folder <- function(project_root, project_id, skill_dir = NULL, html_path) {
    out <- list(status = "skipped", reason = "no_config", dest_path = NA_character_)
    if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess(project_root)
    cfg <- load_sync_folder_config(project_root, skill_dir)
    if (!isTRUE(cfg$found)) {
        out$reason <- cfg$reason %||% "missing_sync_folder_json"
        return(out)
    }
    if (!file.exists(html_path)) {
        out$reason <- "html_report_missing"
        return(out)
    }
    tryCatch({
        ensure_local_folder(cfg$local_path)
        dest_name <- paste0(gsub("[^A-Za-z0-9_-]+", "_", project_id), "_report.html")
        dest_path <- file.path(cfg$local_path, dest_name)
        ok <- file.copy(html_path, dest_path, overwrite = TRUE)
        if (isTRUE(ok)) {
            out$status <- "ok"
            out$reason <- "copied"
            out$dest_path <- dest_path
        } else {
            out$reason <- "copy_failed"
        }
    }, error = function(e) {
        out$status <<- "skipped"
        out$reason <<- conditionMessage(e)
    })
    out
}
