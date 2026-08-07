# Install R dependencies for this skill
# Usage: Rscript .claude/skills/hfc-fieldloop/install.R
#    or: Rscript "${THIS_CLAUDE_SKILL_DIR}/install.R"

core <- c(
    "haven", "readr", "readxl", "dplyr", "tibble",
    "lubridate", "openxlsx", "yaml", "jsonlite"
)
recommended <- c("geosphere")


pkgs <- c(core, recommended)
need <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]

if (!length(need)) {
    message("All necessary packages already installed (", length(pkgs), ").")
} else {
    message("Installing: ", paste(need, collapse = ", "))
    install.packages(need, repos = "https://cloud.r-project.org")
}

missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing)) {
    stop("Still missing after install: ", paste(missing, collapse = ", "))
}
message("FieldLoop dependencies OK.")
message("Core: ", paste(core, collapse = ", "))
message("Recommended (GPS distance): ", paste(recommended, collapse = ", "))

# Optional: audio duration (skipped cleanly if missing; ffprobe also works)
# Manual installation if necessary so the script doesn't fail on non-required installations
optional_media <- c("av")
opt_need <- optional_media[!vapply(optional_media, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(opt_need)) {
    message("Optional media: install with install.packages(\"", opt_need[[1]],
            "\") or use ffprobe — not required for install success.")
} else {
    message("Optional media (M11 duration): av available.")
}
