# Sync feedback: local twin ↔ OneDrive main (field) / audit (code)
# Rscript sync_feedback.R <project_root> [export|import|push-audit|push-main|push-both]
# Paths under hfc/ by default.

args <- commandArgs(trailingOnly = TRUE)
proj <- if (length(args) >= 1) normalizePath(args[[1]]) else getwd()
mode <- if (length(args) >= 2) args[[2]] else "export"

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

suppressPackageStartupMessages({
  library(readr); library(openxlsx); library(dplyr)
})

reg <- hfc_path(proj, "registry")
fb_csv <- file.path(reg, "feedback.csv")
fb_xlsx <- hfc_path(proj, "output", "feedback_sheet.xlsx")
findings_csv <- file.path(reg, "findings.csv")
# legacy fallback
if (!file.exists(fb_csv) && file.exists(file.path(proj, "registry", "feedback.csv"))) {
  reg <- file.path(proj, "registry")
  fb_csv <- file.path(reg, "feedback.csv")
  fb_xlsx <- file.path(proj, "output", "feedback_sheet.xlsx")
  findings_csv <- file.path(reg, "findings.csv")
}

if (mode == "export" || mode == "push-both") {
  if (!file.exists(fb_csv)) stop("No feedback.csv — run setup build first")
  fb <- ensure_resolved_column(read_csv(fb_csv, show_col_types = FALSE))
  findings <- if (file.exists(findings_csv)) read_csv(findings_csv, show_col_types = FALSE) else NULL
  write_feedback_twin(fb, findings, fb_xlsx, fb_csv)
  drv <- sync_drive_feedback_best_effort(proj, basename(proj), fb,
                                         skill_dir = skill, target = "both")
  message("Exported local twin + OneDrive (", drv$status, ": ", drv$reason %||% "", ")")
  message("  main:  ", drv$main_url %||% NA)
  message("  audit: ", drv$audit_url %||% NA)
} else if (mode == "push-audit") {
  if (!file.exists(fb_csv)) stop("No feedback.csv")
  fb <- ensure_resolved_column(read_csv(fb_csv, show_col_types = FALSE))
  drv <- push_feedback_midprocess(proj, fb, skill_dir = skill, target = "audit")
  message("Pushed audit sheet: ", drv$status, " (", drv$reason %||% "", ")")
} else if (mode == "push-main") {
  if (!file.exists(fb_csv)) stop("No feedback.csv")
  fb <- ensure_resolved_column(read_csv(fb_csv, show_col_types = FALSE))
  drv <- sync_drive_feedback_best_effort(proj, basename(proj), fb,
                                         skill_dir = skill, target = "main")
  message("Pushed main (field) sheet: ", drv$status, " (", drv$reason %||% "", ")")
} else if (mode == "import") {
  pulled <- pull_feedback_from_drive(proj, skill_dir = skill, prefer = c("main", "audit"))
  if (!isTRUE(pulled$ok)) {
    if (!file.exists(fb_xlsx)) stop("OneDrive import failed (", pulled$reason, ") and no local xlsx")
    fb <- ensure_resolved_column(as_tibble(read.xlsx(fb_xlsx, sheet = "Feedback")))
    message("OneDrive import failed (", pulled$reason, "); imported local xlsx")
  } else {
    fb <- ensure_resolved_column(as_tibble(pulled$data))
    message("Imported from OneDrive ", pulled$source, " file")
  }
  if (!"status" %in% names(fb) && "ra_status" %in% names(fb)) fb$status <- fb$ra_status
  if (!all(c("finding_id", "status", "resolved") %in% names(fb))) {
    stop("feedback missing required columns (finding_id, status, resolved)")
  }
  if (file.exists(fb_csv)) file.copy(fb_csv, paste0(fb_csv, ".bak"), overwrite = TRUE)
  write_csv(fb, fb_csv)
  findings <- if (file.exists(findings_csv)) read_csv(findings_csv, show_col_types = FALSE) else NULL
  write_feedback_twin(fb, findings, fb_xlsx, fb_csv)
  message("Wrote hfc/registry/feedback.csv (n=", nrow(fb), ")")
} else {
  stop("mode must be export | import | push-audit | push-main | push-both")
}
