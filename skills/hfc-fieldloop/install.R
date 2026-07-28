# Install FieldLoop R dependencies (idempotent)
# Usage: Rscript .claude/skills/hfc-fieldloop/install.R
#    or: Rscript "${CLAUDE_SKILL_DIR}/install.R"

core <- c(
    "haven", "readr", "readxl", "dplyr", "tidyr", "tibble", "stringr",
    "lubridate", "openxlsx", "yaml", "jsonlite"
)
recommended <- c("Microsoft365R", "geosphere")
# Optional: audio duration for M12 (skipped cleanly if missing; ffprobe also works)
optional_media <- c("av")

pkgs <- c(core, recommended)

need <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (!length(need)) {
    message("All FieldLoop packages already installed (", length(pkgs), ").")
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
message("Recommended (OneDrive/GPS): ", paste(recommended, collapse = ", "))

opt_need <- optional_media[!vapply(optional_media, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(opt_need)) {
    message("Optional media (M12 duration): install with install.packages(\"", opt_need[[1]],
            "\") or use ffprobe — not required for install success.")
} else {
    message("Optional media (M12 duration): av available.")
}
