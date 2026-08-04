# One-time interactive OneDrive for Business sign-in.
#
# Run this yourself, once, from a normal interactive R or RStudio session —
# NOT through Claude Code. It opens a browser (or prints a device code 
# if no browser is available) so you can sign in with your own
# Microsoft 365 account. This connects to YOUR OWN OneDrive, not a shared
# site; no SharePoint site or Team needs to exist. 

# Microsoft365R/AzureAuth then caches the resulting token locally; 
#v every later run of run_setup_build.R (including the ones Claude Code triggers 
# non-interactively) reuses that cached token and refreshes it silently, 
# with no further prompts. Share the resulting folder with collaborators afterward 

# Usage: Rscript setup_onedrive_auth.R
# Reads assets/lib/onedrive.json — the one file that configures OneDrive for
# every script in this skill. Edit that file (folder_path/main_file, and
# set "enabled": true) before running this.


# Null-coalescing helper: falls through to `b` on NULL, zero-length, NA, or "".
`%||%` <- function(a, b) {
    if (is.null(a) || length(a) == 0) return(b)
    if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(as.character(a))))) return(b)
    a
}

# Locate the skill root two ways: from Rscript's own --file= arg (normal case),
# or by checking known relative paths (in case this is sourced/copied around).
# NOTE: unlike every script under scripts/ (one level deeper, so they go
# dirname(sp)/".." to reach the skill root), this file sits directly AT the
# skill root — dirname(sp) alone is already the skill root, no ".." needed.
.resolve_skill <- function() {
    sp <- {
        ca <- commandArgs(trailingOnly = FALSE)
        fa <- grep("^--file=", ca, value = TRUE)
        if (length(fa)) gsub("~+~", " ", sub("^--file=", "", fa[[1]]), fixed = TRUE) else NA_character_
    }
    if (!is.na(sp) && file.exists(sp)) {
        return(normalizePath(dirname(sp)))
    }
    if (file.exists(".claude/skills/hfc-fieldloop/scripts/lib/utils.R")) {
        return(normalizePath(".claude/skills/hfc-fieldloop"))
    }
    if (file.exists("hfc-fieldloop/scripts/lib/utils.R")) {
        return(normalizePath("hfc-fieldloop"))
    }
    if (file.exists("scripts/lib/utils.R")) return(normalizePath("."))
    stop("Cannot locate hfc-fieldloop")
}

skill <- .resolve_skill()
lib <- file.path(skill, "scripts", "lib")
source(file.path(lib, "utils.R"))
source(file.path(lib, "onedrive_drive.R"))

# Same config resolution the real pipeline uses, so this dry-run reflects
# exactly what run_setup_build.R will see later.
cfg <- load_onedrive_config(project_root = NULL, skill_dir = skill)
if (!isTRUE(cfg$found)) {
    stop(
        "No usable onedrive.json found (", cfg$reason, "). Edit ",
        ".claude/hfc-fieldloop/assets/lib/onedrive.json and", 
        "set \"enabled\": true (plus folder_path/main_file", 
        "for your own OneDrive) before running this."
    )
}

# AzureAuth only auto-creates its token-cache directory when interactive()
# is TRUE — which Rscript batch sessions (this one included) never are, even
# with a real terminal/browser available. Without this, sign-in still
# succeeds but nothing gets cached, so every future run would need to sign in
# again, defeating the point of this script. Create it explicitly instead.
if (requireNamespace("AzureAuth", quietly = TRUE)) {
    AzureAuth::create_AzureR_dir()
}

message("Signing in to your OneDrive for Business account...")
message("(A browser window should open — sign in with your Microsoft 365 account.)")

# This is the one call that actually triggers the interactive OAuth flow the
# first time it runs; AzureAuth caches the resulting token afterward.
drive <- get_onedrive_drive(cfg)
folder_item <- ensure_onedrive_folder(drive, cfg$folder_path)

# Round-trip a real API call so a failure here (no folder access, etc.)
# surfaces now rather than during a real pipeline run.
items <- tryCatch(folder_item$list_items(info = "name"), error = function(e) character())

message("Signed in and cached. Folder '", cfg$folder_path, "' contains ", length(items), " item(s).")
message("Remember to share that folder with collaborators (edit access) via OneDrive's own sharing UI.")
message("You can now proceed!")
