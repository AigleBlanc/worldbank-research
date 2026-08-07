# Shared "run the checks and write the output artifacts" step — the one
# piece of real work both scripts/run_setup_build.R (Pipeline A) and
# scripts/rebuild_report.R (Pipeline B's post-resolution report refresh)
# need identically. Extracted so the two scripts can't drift apart on what
# "running the checks" actually means.
run_checks_and_write_issues <- function(code_output_dir, ds, roles, modules, skill_dir, target_ds = NULL) {
    message("Running checks...")
    check_res <- run_check_modules(ds, roles, modules, code_output_dir = code_output_dir, target_ds = target_ds)
    findings <- check_res$findings
    stats <- check_res$stats
    message("Findings: ", nrow(findings))

    # issues.csv lives in hfc/outputs/ (never the OneDrive-synced folder —
    # copy_report_to_sync_folder() only ever copies the HTML report path
    # it's explicitly given, see scripts/lib/sync_fpaths.R).
    readr::write_csv(findings, hfc_path(code_output_dir, "outputs", "issues.csv"))
    write_check_scripts(code_output_dir, modules, skill_dir = skill_dir)
    write_main_r(code_output_dir, skill_dir = skill_dir)

    list(findings = findings, stats = stats)
}
