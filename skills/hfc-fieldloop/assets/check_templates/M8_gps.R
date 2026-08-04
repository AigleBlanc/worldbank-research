# HFC FieldLoop generated check: M8
# Standalone, runnable script: reproduces this project's M8 (GPS Location)
# findings using the same shared logic the build itself calls. Copied into
# hfc/code/checks/M8_gps.R at build time with the path line below
# substituted for your project's real path — this file, as shipped in the
# skill's assets/check_templates/, is the copy-source template.
#
# Usage: Rscript hfc/code/checks/M8_gps.R

# Set project path (ONLY place to change for a new machine) ----
path <- "your/path/to/survey_project/"

skill <- file.path(path, ".claude", "skills", "hfc-fieldloop")
lib <- file.path(skill, "scripts", "lib")
for (f in c("utils.R", "geo_timezone.R", "media.R", "form_logic.R", "profile_roles.R", "run_checks.R")) {
  source(file.path(lib, f))
}
suppressPackageStartupMessages({ library(dplyr); library(yaml) })

roles <- yaml::read_yaml(hfc_path(path, "config", "role_map.yaml"))
modules <- yaml::read_yaml(hfc_path(path, "config", "modules.yaml"))
proj_yaml <- yaml::read_yaml(hfc_path(path, "project.yaml"))
ds <- load_latest_dataset(path, proj_yaml$data_file)
ds <- prepare_ds_for_checks(ds, roles, path)

res <- check_m8(ds, roles, modules)
res$findings <- dedupe_finding_ids(res$findings)
message("M8 (GPS Location): ", nrow(res$findings), " findings")
print(as.data.frame(res$findings))
