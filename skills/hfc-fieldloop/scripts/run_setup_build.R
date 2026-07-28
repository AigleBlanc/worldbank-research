# Setup build for a drop-in project root.
# Rscript run_setup_build.R <project_root> [--open] [--sample N] [--no-onedrive]
#
# Reads optional hfc/config/modules.yaml; otherwise uses profile defaults.
# All product artifacts land under <project_root>/hfc/.

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
source(file.path(lib, "geo_timezone.R"))
source(file.path(lib, "media.R"))
source(file.path(lib, "discover.R"))
source(file.path(lib, "profile_roles.R"))
source(file.path(lib, "form_logic.R"))
source(file.path(lib, "run_checks.R"))
source(file.path(lib, "build_outputs.R"))
source(file.path(lib, "product_structure.R"))
source(file.path(lib, "onedrive_drive.R"))

args <- commandArgs(trailingOnly = TRUE)
project_root <- if (length(args) && !startsWith(args[[1]], "--")) {
  normalizePath(decode_file_arg(args[[1]]), mustWork = FALSE)
} else {
  project_root_from_skill(skill)
}
do_open <- "--open" %in% args || "--open" %in% commandArgs(trailingOnly = TRUE)
no_onedrive <- "--no-onedrive" %in% args || identical(Sys.getenv("FIELDLOOP_NO_ONEDRIVE"), "1")
sample_n <- NA_integer_
if ("--sample" %in% args) {
  i <- match("--sample", args)
  if (!is.na(i) && i < length(args)) sample_n <- as.integer(args[[i + 1]])
}

suppressPackageStartupMessages({
  library(haven); library(dplyr); library(readr); library(openxlsx)
  library(yaml); library(jsonlite); library(lubridate); library(tibble)
})

message("Project root: ", project_root)
ensure_project_dirs(project_root)
write_product_structure_html(project_root, open = FALSE)

disc <- discover_project(project_root, create_raw_if_missing = TRUE)
if (identical(disc$status, "missing_data")) {
  stop("No microdata found under data/raw/. Drop a .dta/.csv/.xlsx and re-run.")
}

data_path <- disc$data$path
form_path <- if (!is.null(disc$form)) disc$form$path else NA_character_

raw_dest <- file.path(project_root, "data", "raw", basename(data_path))
if (!file.exists(raw_dest) || !identical(normalizePath(data_path), normalizePath(raw_dest, mustWork = FALSE))) {
  if (!file.exists(raw_dest)) {
    ok <- FALSE
    try(ok <- file.symlink(normalizePath(data_path), raw_dest), silent = TRUE)
    if (!isTRUE(ok) && !file.exists(raw_dest)) file.copy(data_path, raw_dest)
  }
  data_path <- raw_dest
}
if (!is.na(form_path) && file.exists(form_path)) {
  form_dest <- hfc_path(project_root, "instrument", "form.xlsx")
  if (!identical(normalizePath(form_path, mustWork = FALSE),
                 normalizePath(form_dest, mustWork = FALSE))) {
    file.copy(form_path, form_dest, overwrite = TRUE)
  }
}

message("Loading: ", data_path)
ds <- load_microdata(data_path, sample_n = sample_n)

media_folder <- disc$media_folder %||% NA_character_
if (is.null(media_folder) || (length(media_folder) == 1 && is.na(media_folder))) {
  mf <- discover_media_folder(project_root, data_path)
  media_folder <- mf$path
}
if (isTRUE(disc$media_folder_found) || (!is.na(media_folder) && nzchar(media_folder))) {
  message("Media folder: ", media_folder)
} else {
  message("Media folder: (not found — M12 on-disk checks will be skipped if media cols exist)")
}

roles <- profile_roles(ds, media_folder = media_folder)
if (length(roles$id_rationale)) {
  message("ID shortlist:\n  ", paste(roles$id_rationale, collapse = "\n  "))
}

modules_path <- hfc_path(project_root, "config", "modules.yaml")
if (file.exists(modules_path)) {
  modules <- yaml::read_yaml(modules_path)
  if (!is.null(modules$M12) &&
      (is.null(modules$M12$media_folder) || is.na(modules$M12$media_folder) ||
       !nzchar(as.character(modules$M12$media_folder[[1]])))) {
    modules$M12$media_folder <- media_folder
  }
} else {
  modules <- default_modules(roles)
  yaml::write_yaml(modules, modules_path)
}

role_map_path <- hfc_path(project_root, "config", "role_map.yaml")
if (file.exists(role_map_path)) {
  saved <- yaml::read_yaml(role_map_path)
  # Required-fields gate answers (unique ID(s), country/timezone, last date)
  # persist here; reload them each rebuild rather than re-deriving.
  if (!is.null(saved$id) && length(saved$id)) roles$id <- unlist(saved$id)
  if (!is.null(saved$id_sep) && nzchar(as.character(saved$id_sep))) {
    roles$id_sep <- as.character(saved$id_sep)
  }
  if (!is.null(saved$country_mode) && nzchar(as.character(saved$country_mode))) {
    roles$country_mode <- as.character(saved$country_mode)
  }
  if (!is.null(saved$country) && nzchar(as.character(saved$country))) {
    roles$country <- as.character(saved$country)
  }
  if (!is.null(saved$country_col) && nzchar(as.character(saved$country_col))) {
    roles$country_col <- as.character(saved$country_col)
  }
  if (!is.null(saved$country_timezone_map) && length(saved$country_timezone_map)) {
    roles$country_timezone_map <- saved$country_timezone_map
  }
  if (!is.null(saved$timezone) && nzchar(as.character(saved$timezone))) {
    roles$timezone <- as.character(saved$timezone)
  }
  if (!is.null(saved$last_date) && nzchar(as.character(saved$last_date))) {
    roles$last_date <- as.character(saved$last_date)
  }
  if (!is.null(modules$M2)) modules$M2$id <- roles$id
}
yaml::write_yaml(roles, role_map_path)
writeLines(format_module_cards(roles), hfc_path(project_root, "config", "module_cards.txt"))

# Form relevance for nested skip-logic
form_map <- parse_form_relevance(if (!is.na(form_path) && file.exists(form_path)) form_path else
  hfc_path(project_root, "instrument", "form.xlsx"))
attr(ds, "hfc_form_map") <- form_map

# Report config (map focus etc.)
report_cfg_path <- hfc_path(project_root, "config", "report.yaml")
report_cfg <- if (file.exists(report_cfg_path)) yaml::read_yaml(report_cfg_path) else list(map_focus = "country")

# Human-readable notes for custom/M8 checks (and optional per-module description
# overrides), authored during the Additional-checks confirm step. Optional file.
module_notes_path <- hfc_path(project_root, "config", "module_notes.yaml")
module_notes <- if (file.exists(module_notes_path)) yaml::read_yaml(module_notes_path) else NULL

message("Running checks...")
check_res <- run_check_modules(ds, roles, modules, project_root = project_root)
findings <- check_res$findings
stats <- check_res$stats
message("Findings: ", nrow(findings))

readr::write_csv(findings, hfc_path(project_root, "registry", "findings.csv"))
write_check_stubs(project_root, findings, skill_dir = skill)
write_main_r(project_root, skill_dir = skill)
write_tracking_xlsx(findings, hfc_path(project_root, "output", "tracking.xlsx"))

fb <- findings_to_feedback(findings)
write_feedback_twin(
  fb,
  findings,
  hfc_path(project_root, "output", "feedback_sheet.xlsx"),
  hfc_path(project_root, "registry", "feedback.csv")
)

project_id <- basename(project_root)
drive <- if (no_onedrive) {
  list(status = "skipped", reason = "no-onedrive flag",
       main_url = NA, audit_url = NA, main_id = NA, audit_id = NA,
       url = NA, id = NA)
} else {
  sync_drive_feedback_best_effort(project_root, project_id, fb,
                                  skill_dir = skill, target = "both")
}

drv_cfg <- load_onedrive_config(project_root, skill)
if (isTRUE(drv_cfg$found)) {
  cfg_dest <- hfc_path(project_root, "config", "onedrive.json")
  dir.create(dirname(cfg_dest), showWarnings = FALSE, recursive = TRUE)
  if (!identical(normalizePath(drv_cfg$path, mustWork = FALSE),
                 normalizePath(cfg_dest, mustWork = FALSE))) {
    file.copy(drv_cfg$path, cfg_dest, overwrite = TRUE)
  }
}

proj_yaml <- list(
  project_id = project_id,
  data_file = file.path("data", "raw", basename(data_path)),
  instrument = if (!is.na(form_path)) "hfc/instrument/form.xlsx" else NULL,
  report_type = "html",
  map_focus = report_cfg$map_focus %||% "country",
  shiny_later = TRUE,
  feedback_main_url = drive$main_url,
  feedback_main_id = drive$main_id,
  feedback_audit_url = drive$audit_url,
  feedback_audit_id = drive$audit_id,
  feedback_sheet_url = drive$main_url,
  feedback_sheet_id = drive$main_id,
  feedback_local = "hfc/output/feedback_sheet.xlsx",
  onedrive_config = "hfc/config/onedrive.json",
  created = as.character(Sys.time()),
  n_findings = nrow(findings)
)

html_path <- write_html_report(
  findings, project_root, project_id, open = do_open,
  roles = roles, ds = ds, report_cfg = report_cfg, module_notes = module_notes,
  stats = stats
)

report_link <- if (no_onedrive) {
  list(status = "skipped", reason = "no-onedrive flag", url = NA)
} else {
  upload_report_and_get_link(project_root, project_id, skill_dir = skill, html_path)
}
proj_yaml$report_onedrive_url <- report_link$url %||% NA
yaml::write_yaml(proj_yaml, hfc_path(project_root, "project.yaml"))

runs <- hfc_path(project_root, "runs", "setup")
dir.create(file.path(runs, "turns"), recursive = TRUE, showWarnings = FALSE)
yaml::write_yaml(list(status = "built", n_findings = nrow(findings), html = html_path),
                 file.path(runs, "meta.yaml"))
jsonlite::write_json(list(
  n_findings = nrow(findings),
  categories = as.list(table(findings$category)),
  drive = drive,
  report_link = report_link,
  html = html_path,
  id = roles$id,
  id_options = roles$id_options
), file.path(runs, "meta.json"), auto_unbox = TRUE, pretty = TRUE)

message("Done. HTML: ", html_path)
message("Product root: ", hfc_root(project_root))
message("OneDrive sync: ", drive$status, " (", drive$reason %||% "", ")")
message("  main (field):  ", drive$main_url %||% "(none)")
message("  audit (code):  ", drive$audit_url %||% "(none)")
message("Report link: ", report_link$status, " (", report_link$reason %||% "", ") ", report_link$url %||% "(none)")
message("When field edits the main file, run: Process HFC feedback")
