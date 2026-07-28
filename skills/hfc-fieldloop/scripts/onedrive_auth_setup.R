# One-time interactive OneDrive/SharePoint sign-in.
#
# Run this yourself, once, from a normal interactive R or RStudio session —
# NOT through Claude Code / the Bash tool. It opens a browser (or prints a
# device code if no browser is available) so you can sign in with your
# Microsoft 365 account. Microsoft365R/AzureAuth then caches the resulting
# token locally; every later run of run_setup_build.R (including ones Claude
# Code triggers non-interactively) reuses that cached token and refreshes it
# silently, with no further prompts.
#
# Usage: Rscript scripts/onedrive_auth_setup.R [project_root]
# If project_root is omitted, the current working directory is used — this
# only matters if you're relying on a project-level hfc/config/onedrive.json
# override rather than the skill's assets/lib/onedrive.json default.

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(as.character(a))))) return(b)
  a
}

.resolve_skill <- function() {
  sp <- {
    ca <- commandArgs(trailingOnly = FALSE)
    fa <- grep("^--file=", ca, value = TRUE)
    if (length(fa)) gsub("~+~", " ", sub("^--file=", "", fa[[1]]), fixed = TRUE) else NA_character_
  }
  if (!is.na(sp) && file.exists(sp)) {
    return(normalizePath(file.path(dirname(sp), "..")))
  }
  if (file.exists("hfc-fieldloop/scripts/lib/utils.R")) {
    return(normalizePath("hfc-fieldloop"))
  }
  if (file.exists("scripts/lib/utils.R")) return(normalizePath(".."))
  stop("Cannot locate hfc-fieldloop")
}
skill <- .resolve_skill()
lib <- file.path(skill, "scripts", "lib")
source(file.path(lib, "utils.R"))
source(file.path(lib, "onedrive_drive.R"))

args <- commandArgs(trailingOnly = TRUE)
project_root <- if (length(args) >= 1) normalizePath(args[[1]], mustWork = FALSE) else getwd()

cfg <- load_onedrive_config(project_root, skill)
if (!isTRUE(cfg$found)) {
  stop(
    "No usable onedrive.json found (", cfg$reason, "). Copy ",
    "assets/lib/onedrive.example.json to assets/lib/onedrive.json (or ",
    "hfc/config/onedrive.json for a single project) and fill in the real ",
    "site_url before running this."
  )
}

message("Signing in to: ", cfg$site_url)
message("(A browser window should open — sign in with your Microsoft 365 account.)")
drive <- get_onedrive_drive(cfg)
folder_item <- ensure_onedrive_folder(drive, cfg$folder_path)
items <- tryCatch(folder_item$list_items(info = "name"), error = function(e) character())

message("Signed in and cached. Folder '", cfg$folder_path, "' contains ", length(items), " item(s).")
message("You can now run run_setup_build.R (via Claude Code or directly) without further prompts.")
