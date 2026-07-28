# Post-feedback pipeline: propose/apply accepted fixes → *_resolved + resolved column
# Rscript apply_feedback.R <project_root> [--dry-run]
# Reads feedback from hfc/ (or OneDrive). status=accepted (legacy ra_status mapped).

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && (is.na(a) || (is.character(a) && !nzchar(as.character(a))))) return(b)
  a
}

.resolve_skill <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", ca, value = TRUE)
  sp <- if (length(fa)) gsub("~+~", " ", sub("^--file=", "", fa[[1]]), fixed = TRUE) else NA_character_
  if (!is.na(sp) && file.exists(sp)) return(normalizePath(file.path(dirname(sp), "..")))
  if (file.exists("hfc-fieldloop/scripts/lib/utils.R")) return(normalizePath("hfc-fieldloop"))
  if (file.exists("scripts/lib/utils.R")) return(normalizePath(".."))
  stop("Cannot locate hfc-fieldloop")
}
skill <- .resolve_skill()
lib <- file.path(skill, "scripts", "lib")
source(file.path(lib, "utils.R"))
source(file.path(lib, "build_outputs.R"))
source(file.path(lib, "onedrive_drive.R"))

args <- commandArgs(trailingOnly = TRUE)
project_root <- if (length(args) && !startsWith(args[[1]], "--")) {
  normalizePath(decode_file_arg(args[[1]]))
} else {
  project_root_from_skill(skill)
}
dry_run <- "--dry-run" %in% args

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(yaml); library(openxlsx); library(haven)
})

proj_yaml_path <- hfc_path(project_root, "project.yaml")
if (!file.exists(proj_yaml_path)) {
  # legacy fallback
  proj_yaml_path <- file.path(project_root, "project.yaml")
}
if (!file.exists(proj_yaml_path)) stop("Missing hfc/project.yaml — run setup build first")
cfg <- yaml::read_yaml(proj_yaml_path)

fb_csv <- hfc_path(project_root, "registry", "feedback.csv")
fb_xlsx <- hfc_path(project_root, "output", "feedback_sheet.xlsx")
if (!file.exists(fb_csv) && file.exists(file.path(project_root, "registry", "feedback.csv"))) {
  fb_csv <- file.path(project_root, "registry", "feedback.csv")
  fb_xlsx <- file.path(project_root, "output", "feedback_sheet.xlsx")
}

pulled <- pull_feedback_from_drive(project_root, skill_dir = skill, prefer = c("main", "audit"))
if (isTRUE(pulled$ok)) {
  fb <- pulled$data
  message("Loaded feedback from OneDrive ", pulled$source, " file")
} else if (file.exists(fb_xlsx) && file.exists(fb_csv)) {
  if (file.info(fb_xlsx)$mtime > file.info(fb_csv)$mtime) {
    fb <- read.xlsx(fb_xlsx, sheet = "Feedback")
  } else {
    fb <- read_csv(fb_csv, show_col_types = FALSE)
  }
  message("OneDrive pull skipped (", pulled$reason %||% "?", "); using local twin")
} else if (file.exists(fb_csv)) {
  fb <- read_csv(fb_csv, show_col_types = FALSE)
} else if (file.exists(fb_xlsx)) {
  fb <- read.xlsx(fb_xlsx, sheet = "Feedback")
} else {
  stop("No feedback file found (OneDrive: ", pulled$reason %||% "n/a", ")")
}
fb <- ensure_resolved_column(as_tibble(fb))

if (!"status" %in% names(fb) && "ra_status" %in% names(fb)) {
  fb$status <- fb$ra_status
}
req <- c("finding_id", "status", "resolved")
miss <- setdiff(req, names(fb))
if (length(miss)) stop("Feedback missing columns: ", paste(miss, collapse = ", "))

findings_path <- hfc_path(project_root, "registry", "findings.csv")
if (!file.exists(findings_path)) findings_path <- file.path(project_root, "registry", "findings.csv")
findings <- if (file.exists(findings_path)) read_csv(findings_path, show_col_types = FALSE) else NULL
if (!is.null(findings) && !"category" %in% names(fb) && "category" %in% names(findings)) {
  fb <- fb %>% left_join(findings %>% select(finding_id, category), by = "finding_id")
}

role_map_path <- hfc_path(project_root, "config", "role_map.yaml")
if (!file.exists(role_map_path)) role_map_path <- file.path(project_root, "config", "role_map.yaml")
roles <- if (file.exists(role_map_path)) yaml::read_yaml(role_map_path) else list(id = "id")

data_rel <- cfg$data_file %||% list.files(file.path(project_root, "data", "raw"),
                                          pattern = "\\.(dta|csv|xlsx)$", full.names = FALSE)[[1]]
data_path <- file.path(project_root, data_rel)
if (!file.exists(data_path)) stop("Data file missing: ", data_path)

accepted <- fb %>% filter(tolower(as.character(status)) == "accepted")
message("Accepted rows: ", nrow(accepted), " / ", nrow(fb))

proposals <- accepted %>%
  mutate(
    action = dplyr::case_when(
      grepl("dup", category %||% issue, ignore.case = TRUE) ~ "drop_dup_suffix",
      grepl("age", category %||% issue, ignore.case = TRUE) ~ "winsor_age_median",
      grepl("early", category %||% issue, ignore.case = TRUE) ~ "flag_early",
      TRUE ~ "flag_review"
    )
  )
readr::write_csv(proposals, hfc_path(project_root, "registry", "fix_proposals.csv"))
message("Wrote hfc/registry/fix_proposals.csv")

if (dry_run) {
  message("Dry run — not applying fixes")
  quit(save = "no", status = 0)
}

ds <- load_microdata(data_path)
fixed_ds <- ds
applied <- list()
fixes_dir <- hfc_path(project_root, "fixes")
dir.create(fixes_dir, showWarnings = FALSE, recursive = TRUE)

for (i in seq_len(nrow(accepted))) {
  row <- accepted[i, ]
  fid <- as.character(row$finding_id)
  catg <- as.character(row$category %||% "")
  sid <- as.character(row$submission_id %||% "")
  if (!nzchar(sid) && "id" %in% names(row)) sid <- as.character(row$id)

  fix_file <- file.path(fixes_dir, sprintf("FIX-%s.R", gsub("[^A-Za-z0-9_-]", "_", fid)))
  writeLines(c(
    sprintf("# Fix for %s (%s)", fid, catg),
    sprintf("# proposed_fix: %s", row$proposed_fix %||% ""),
    sprintf("# field_comment: %s", row$field_comment %||% "")
  ), fix_file)

  id_col <- roles$id
  if (is.null(id_col) || !id_col %in% names(fixed_ds)) {
    id_col <- names(fixed_ds)[1]
  }
  id_chr <- as.character(fixed_ds[[id_col]])

  if (grepl("dup", catg, ignore.case = TRUE) && nzchar(sid)) {
    idx <- which(id_chr == sid)
    if (length(idx) > 1) {
      id_chr[idx[-1]] <- paste0(id_chr[idx[-1]], "_DUPDROP")
      fixed_ds[[id_col]] <- id_chr
      applied <- c(applied, list(list(finding_id = fid, action = "suffix_dup_ids", n = length(idx) - 1)))
    }
  } else if (grepl("age", catg, ignore.case = TRUE) && nzchar(sid) &&
             !is.null(roles$age) && roles$age %in% names(fixed_ds)) {
    idx <- which(id_chr == sid)
    if (length(idx)) {
      fixed_ds[[roles$age]] <- safe_num(fixed_ds[[roles$age]])
      med <- median(fixed_ds[[roles$age]], na.rm = TRUE)
      fixed_ds[[roles$age]][idx] <- med
      applied <- c(applied, list(list(finding_id = fid, action = "winsor_age_to_median", n = length(idx))))
    }
  } else if (grepl("early", catg, ignore.case = TRUE) && nzchar(sid)) {
    if (!"hfc_early_flag" %in% names(fixed_ds)) fixed_ds$hfc_early_flag <- 0
    fixed_ds$hfc_early_flag[id_chr == sid] <- 1
    applied <- c(applied, list(list(finding_id = fid, action = "flag_early_start", n = sum(id_chr == sid))))
  } else if (nzchar(sid)) {
    if (!"hfc_review_flag" %in% names(fixed_ds)) fixed_ds$hfc_review_flag <- 0
    fixed_ds$hfc_review_flag[id_chr == sid] <- 1
    applied <- c(applied, list(list(finding_id = fid, action = "flag_review", n = sum(id_chr == sid))))
  }
}

resolved_path <- write_resolved(fixed_ds, data_path)
message("Wrote resolved data: ", resolved_path)

fb$resolved <- as.character(fb$resolved)
fb$resolved[fb$finding_id %in% accepted$finding_id] <- "yes"
for (fid in accepted$finding_id) {
  acted <- any(vapply(applied, function(a) identical(a$finding_id, fid), logical(1)))
  if (!acted) fb$resolved[fb$finding_id == fid] <- "partial"
}
fb$date_updated[fb$finding_id %in% accepted$finding_id] <- as.character(Sys.Date())

fb_out <- fb %>% select(-any_of("category"))
write_feedback_twin(fb_out, findings, fb_xlsx, fb_csv)

drive_push <- push_feedback_midprocess(project_root, fb_out, skill_dir = skill, target = "audit")
message("Audit OneDrive sync: ", drive_push$status, " (", drive_push$reason %||% "", ")")

yaml::write_yaml(list(
  applied = applied,
  n_accepted = nrow(accepted),
  resolved_file = resolved_path,
  audit_sync = drive_push,
  timestamp = as.character(Sys.time())
), hfc_path(project_root, "registry", "accepted_fixes.yaml"))

cfg$last_resolved_file <- resolved_path
cfg$last_feedback_apply <- as.character(Sys.time())
cfg$feedback_audit_url <- drive_push$audit_url %||% cfg$feedback_audit_url
cfg$feedback_main_url <- drive_push$main_url %||% cfg$feedback_main_url
yaml::write_yaml(cfg, hfc_path(project_root, "project.yaml"))

message("Updated resolved column on feedback. Please review: ", resolved_path)
