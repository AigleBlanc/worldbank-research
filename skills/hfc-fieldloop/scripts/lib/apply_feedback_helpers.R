# Post-feedback helpers. Fix logic itself is agent-authored per finding —
# there is no built-in heuristic engine here (mirrors how M11 custom checks
# are AI-authored per project rather than a fixed catalog). All work happens
# against today's resolutions/<date>_issues_resolution.xlsx clone, never the
# live issue_tracking.xlsx directly — merge_resolutions.R + explicit
# AskUserQuestion confirmation is the only path that ever updates the live
# file (see scripts/merge_resolutions.R, scripts/commit_merged_issue_tracking.R).
#
# Trigger: any row with Status == "Open" and a non-empty RIL Comment is
# eligible — there is no separate Accepted gate. The agent interprets the
# RIL Comment and applies a fix in a single pass (propose Corrections +
# apply the data fix + set Status = "Resolved", all at once).
#
# Every function here takes `cfg` — the loaded config.json (see
# scripts/lib/sync_folder.R) — as its first argument, since fix application
# needs both input_data_dir (to load/write microdata) and code_output_dir
# (to read hfc/project.yaml and hfc/code/resolutions/) distinctly.

sanitize_finding_id <- function(finding_id) gsub("[^A-Za-z0-9_.-]", "_", finding_id)

#' Create today's resolutions/<date> clone from the current issue_tracking.xlsx,
#' unless today's clone already exists (a same-day second pass reuses it
#' rather than discarding in-progress Status/Corrections edits).
clone_for_resolution_pass <- function(cfg, skill_dir = NULL, date = Sys.Date()) {
  entity_label <- load_entity_label(cfg$code_output_dir)
  ctx <- fetch_issue_tracking(skill_dir = skill_dir, entity_label = entity_label)
  existing <- read_resolution_clone(ctx, date = date, entity_label = entity_label)
  if (!is.null(existing)) {
    return(list(status = "reused", n = nrow(existing)))
  }
  if (is.null(ctx$tbl)) stop("No issue_tracking.xlsx found — run the setup build first.")
  write_resolution_clone(ctx, ctx$tbl, date = date, entity_label = entity_label)
  list(status = "created", n = nrow(ctx$tbl))
}

#' Status=Open + non-empty RIL Comment rows from today's resolutions clone,
#' with full row context for the agent to read directly — Issue, RIL
#' Comment, Entity ID, Variable, Value, Issue Category, etc.
list_open_commented_rows <- function(cfg, skill_dir = NULL, date = Sys.Date()) {
  suppressPackageStartupMessages({ library(dplyr) })
  entity_label <- load_entity_label(cfg$code_output_dir)
  ctx <- fetch_issue_tracking(skill_dir = skill_dir, entity_label = entity_label)
  clone <- read_resolution_clone(ctx, date = date, entity_label = entity_label)
  if (is.null(clone)) stop("No resolutions/ clone for today — run clone_for_resolution_pass() first.")
  clone %>% filter(toupper(as.character(status)) == "OPEN", nzchar(as.character(ril_comment)))
}

#' Update one row's Status/Corrections in today's resolutions clone only.
.update_clone_row <- function(cfg, skill_dir, date, finding_id, new_status, corrections_text = NULL) {
  entity_label <- load_entity_label(cfg$code_output_dir)
  ctx <- fetch_issue_tracking(skill_dir = skill_dir, entity_label = entity_label)
  clone <- read_resolution_clone(ctx, date = date, entity_label = entity_label)
  if (is.null(clone)) stop("No resolutions/ clone for today — run clone_for_resolution_pass() first.")
  if (!finding_id %in% clone$finding_id) stop("Issue ID not found in today's resolutions clone: ", finding_id)
  clone$status[clone$finding_id == finding_id] <- new_status
  if (!is.null(corrections_text)) {
    clone$corrections[clone$finding_id == finding_id] <- corrections_text
  }
  write_resolution_clone(ctx, clone, date = date, entity_label = entity_label)
  invisible(clone)
}

#' Single pass: agent has already written hfc/code/resolutions/<id>.R (fix(ds) -> ds)
#' after interpreting the row's RIL Comment. This loads the latest dataset,
#' applies the fix, writes <sibling of input_data_dir>/intermediate/<stem>.<ext>,
#' and records the Corrections text + Status = "Resolved" in today's
#' resolutions clone.
apply_one_fix <- function(cfg, finding_id, corrections_text, skill_dir = NULL, date = Sys.Date()) {
  fixes_dir <- hfc_path(cfg$code_output_dir, "code", "resolutions")
  fix_file <- file.path(fixes_dir, paste0(sanitize_finding_id(finding_id), ".R"))
  if (!file.exists(fix_file)) {
    stop("No fix file found: ", fix_file, " — write it first, defining fix(ds) -> ds.")
  }

  env <- new.env(parent = globalenv())
  sys.source(fix_file, envir = env)
  if (!exists("fix", envir = env, mode = "function")) {
    stop("Fix file must define fix(ds): ", fix_file)
  }

  proj_yaml_path <- hfc_path(cfg$code_output_dir, "project.yaml")
  proj <- yaml::read_yaml(proj_yaml_path)
  data_rel <- proj$data_file
  stem <- tools::file_path_sans_ext(basename(data_rel))
  ext <- tolower(tools::file_ext(data_rel))

  ds <- load_latest_dataset(cfg$input_data_dir, data_rel)
  fixed_ds <- env$fix(ds)
  out_path <- write_intermediate(fixed_ds, cfg$input_data_dir, stem, ext)

  .update_clone_row(cfg, skill_dir, date, finding_id, "Resolved", corrections_text)

  list(status = "ok", intermediate_path = out_path, fix_file = fix_file)
}

#' The agent couldn't confidently resolve this row — mark it for human
#' follow-up instead of leaving it stuck on Open.
mark_needs_review <- function(cfg, finding_id, skill_dir = NULL, date = Sys.Date()) {
  .update_clone_row(cfg, skill_dir, date, finding_id, "Needs Review")
  list(status = "ok")
}
