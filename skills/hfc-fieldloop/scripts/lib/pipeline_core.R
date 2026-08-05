# Shared "run the checks and write the registry outputs" step — the one
# piece of real work both scripts/run_setup_build.R (Pipeline A) and
# scripts/rebuild_report.R (Pipeline B's post-resolution report refresh)
# need identically. Extracted so the two scripts can't drift apart on what
# "running the checks" actually means.
run_checks_and_write_registry <- function(project_root, ds, roles, modules, skill_dir) {
    message("Running checks...")
    check_res <- run_check_modules(ds, roles, modules, project_root = project_root)
    findings <- check_res$findings
    stats <- check_res$stats
    message("Findings: ", nrow(findings))

    readr::write_csv(findings, hfc_path(project_root, "registry", "findings.csv"))
    write_check_scripts(project_root, modules, skill_dir = skill_dir)
    write_main_r(project_root, skill_dir = skill_dir)

    list(findings = findings, stats = stats)
}
