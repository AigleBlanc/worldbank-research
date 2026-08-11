# Config loading + shared-folder access. The skill is now driven entirely by
# skills/hfc-fieldloop/config.json, naming four directories the user sets
# once: input_data_dir (where survey microdata lives), media_dir (optional
# — SurveyCTO audio/image attachments), onedrive_output_dir (a folder kept
# in sync with the cloud by something outside this skill — in practice, the
# OneDrive desktop app; nothing here verifies that, it's plain filesystem
# I/O), and code_output_dir (a git working copy the user manages themselves
# — this skill only ever writes plain files there, it never runs git).
#
# One file matters in onedrive_output_dir: main_file (issue_tracking.xlsx) —
# shared with the field team, edited collaboratively by the agent, RA, and
# field team (see scripts/lib/issue_store.R, which builds the actual
# fetch/commit logic on top of the primitives here, plus
# require_fieldloop_config_ready() which every user-facing script calls
# first).
#
# Target: whoever runs the pipeline points onedrive_output_dir at their OWN
# OneDrive sync folder — no SharePoint site or Team needs to be created.
# That person then manually shares the resulting folder with collaborators
# (edit access) via OneDrive's normal "Specific people" sharing UI — this
# code never mints its own share links.

# Resolve skill root — defensive fallback only; every real call site already
# resolves and passes skill_dir explicitly via its own .resolve_skill().
skill_dir_guess <- function() {
    cands <- c(".claude/skills/hfc-fieldloop", "hfc-fieldloop", ".")
    for (c in cands) {
        if (dir.exists(c) && file.exists(file.path(c, "scripts", "lib", "sync_fpaths.R"))) {
        return(normalizePath(c))
        }
    }
    NA_character_
}

CONFIG_PLACEHOLDER_RE <- "^<.*>$"

.is_unset <- function(x) {
    is.null(x) || !nzchar(as.character(x)) || grepl(CONFIG_PLACEHOLDER_RE, as.character(x))
}

# Load + validate skills/hfc-fieldloop/config.json — the only config file
# that matters, edited directly, no per-project override. JSON keys are
# Title Case (RA-facing — this file is something a non-programmer edits by
# hand): "Input Data Directory", "Media Folder Directory",
# "HFC Output Directory", "Code Output Directory",
# "Main Tracking Filename". The R-side return list below keeps snake_case
# element names (cfg$input_data_dir etc.) — only the JSON string keys are
# Title Case; every downstream cfg$... reference in this codebase is
# unaffected by this file's key names. Required fields: Input Data
# Directory, HFC Output Directory, Code Output Directory. Media Folder
# Directory is optional (surveys with no audio/photo questions can leave it
# blank) — scripts/lib/media.R already tolerates a missing/unset media
# folder.
CONFIG_JSON_KEYS <- c(
    input_data_dir = "Input Data Directory",
    media_dir = "Media Folder Directory",
    onedrive_output_dir = "HFC Output Directory",
    code_output_dir = "Code Output Directory",
    main_file = "Main Tracking Filename"
)

load_fieldloop_config <- function(skill_dir = NULL) {
    if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess()
    empty <- function(path = NA_character_, reason = NULL) {
        list(
            found = FALSE, path = path,
            input_data_dir = NA_character_, media_dir = NA_character_,
            onedrive_output_dir = NA_character_, code_output_dir = NA_character_,
            main_file = NA_character_, reason = reason
        )
    }
    if (is.null(skill_dir) || is.na(skill_dir)) return(empty(reason = "missing_config_json"))
    cfg_path <- file.path(skill_dir, "config.json")
    if (!file.exists(cfg_path)) return(empty(reason = "missing_config_json"))

    raw <- tryCatch(jsonlite::fromJSON(cfg_path), error = function(e) NULL)
    if (is.null(raw)) return(empty(path = normalizePath(cfg_path), reason = "invalid_config_json"))

    required <- c("input_data_dir", "onedrive_output_dir", "code_output_dir")
    for (field in required) {
        if (.is_unset(raw[[CONFIG_JSON_KEYS[[field]]]])) {
        return(empty(path = normalizePath(cfg_path), reason = paste0("missing_", field)))
        }
    }

    list(
        found = TRUE,
        path = normalizePath(cfg_path),
        input_data_dir = as.character(raw[[CONFIG_JSON_KEYS[["input_data_dir"]]]]),
        media_dir = if (!.is_unset(raw[[CONFIG_JSON_KEYS[["media_dir"]]]])) as.character(raw[[CONFIG_JSON_KEYS[["media_dir"]]]]) else NA_character_,
        onedrive_output_dir = as.character(raw[[CONFIG_JSON_KEYS[["onedrive_output_dir"]]]]),
        code_output_dir = as.character(raw[[CONFIG_JSON_KEYS[["code_output_dir"]]]]),
        main_file = if (!.is_unset(raw[[CONFIG_JSON_KEYS[["main_file"]]]])) as.character(raw[[CONFIG_JSON_KEYS[["main_file"]]]]) else "issue_tracking.xlsx"
    )
}

# Create `path` (and any missing parents) if it doesn't exist yet; returns
# `path` unchanged so it can be used inline. Idempotent — safe to call every
# time, whether or not OneDrive's sync client has already materialized it.
ensure_local_folder <- function(path) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
    path
}

# Copy the built HTML report into the configured OneDrive output folder, so
# it syncs to the cloud alongside issue_tracking.xlsx. No shareable link is
# minted here — the folder's access (e.g. specific external collaborators)
# is set up once by hand in the OneDrive web UI, and anyone already granted
# access to it can find this file there once it syncs.
copy_report_to_sync_folder <- function(project_id, skill_dir = NULL, html_path) {
    out <- list(status = "skipped", reason = "no_config", dest_path = NA_character_)
    if (is.null(skill_dir) || is.na(skill_dir)) skill_dir <- skill_dir_guess()
    cfg <- load_fieldloop_config(skill_dir)
    if (!isTRUE(cfg$found)) {
        out$reason <- cfg$reason %||% "missing_config_json"
        return(out)
    }
    if (!file.exists(html_path)) {
        out$reason <- "html_report_missing"
        return(out)
    }
    tryCatch({
        ensure_local_folder(cfg$onedrive_output_dir)
        # Mirror the source file's own (dated) name exactly, rather than
        # reconstructing a fixed suffix — the report is now written as
        # <MMDD>_HFCs.html and rebuilds accumulate as separate snapshots.
        dest_name <- basename(html_path)
        dest_path <- file.path(cfg$onedrive_output_dir, dest_name)
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
