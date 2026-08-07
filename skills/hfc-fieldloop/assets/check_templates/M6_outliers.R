# HFC FieldLoop generated check: M6
# Standalone, runnable script: reproduces this project's M6 (Numeric Outliers)
# findings using the same shared logic the build itself calls. Copied into
# hfc/code/checks/M6_outliers.R at build time with the skill/code_output_dir lines below
# substituted for this machine's real paths — this file, as shipped in the
# skill's assets/check_templates/, is the copy-source template.
#
# Usage: Rscript hfc/code/checks/M6_outliers.R

# Set skill + code output paths (substituted automatically on setup build) ----
skill <- "your/path/to/hfc-fieldloop/"
code_output_dir <- "your/path/to/hfc/output/"

lib <- file.path(skill, "scripts", "lib")
for (f in c("utils.R", "geo_timezone.R", "media.R", "form_logic.R", "profile_roles.R", "run_checks.R", "sync_fpaths.R")) {
  source(file.path(lib, f))
}
suppressPackageStartupMessages({ library(dplyr); library(yaml) })

cfg <- load_fieldloop_config(skill)
if (!isTRUE(cfg$found)) stop("skills/hfc-fieldloop/config.json is not fully configured. Reason: ", cfg$reason)

roles <- yaml::read_yaml(hfc_path(code_output_dir, "config", "role_map.yaml"))
modules <- yaml::read_yaml(hfc_path(code_output_dir, "config", "modules.yaml"))
proj_yaml <- yaml::read_yaml(hfc_path(code_output_dir, "project.yaml"))
ds <- load_latest_dataset(cfg$input_data_dir, proj_yaml$data_file)
ds <- prepare_ds_for_checks(ds, roles, code_output_dir)
if (any(!ds$.hfc_completed)) ds <- ds[ds$.hfc_completed, , drop = FALSE]

res <- check_m6(ds, roles, modules)
res$findings <- dedupe_finding_ids(res$findings)
message("M6 (Numeric Outliers): ", nrow(res$findings), " findings")
print(as.data.frame(res$findings))
