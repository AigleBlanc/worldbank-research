# Automated 3-way merge verification — on the Uganda pilot this same check
# was reinvented by hand, differently, several times before trusting a
# merge: (a) row-count match, (b) added/dropped finding_id diffed against
# the FRESH check output (never against the merge-pending file itself,
# which is structurally always a superset of what a fresh run produces),
# (c) for finding_ids present in both, a content diff (Issue/Value text) to
# catch a threshold or config change that alters an existing finding's
# wording without changing its ID. Built once here; run automatically as
# part of merge_issues.R/merge_resolutions.R, right after the merge and
# before the merged_*.xlsx is written.

#' verify_findings_merge(current, snapshot, merged)
#' `current`: the live table BEFORE this merge. `snapshot`: today's FRESH
#' check output (the intermediate/ tracking snapshot) — the source of truth
#' for what should exist, not `current` or `merged` (which is structurally
#' a superset). `merged`: merge_preserve_existing(current, snapshot)'s
#' result, about to be written as merged_issue_tracking.xlsx.
#' `dropped`: a finding_id from `current` OR the fresh `snapshot` that's
#' missing from `merged` — merge_preserve_existing() should never drop
#' anything, so this is always a real bug indicator. `unexpected_added`: a
#' finding_id in `merged` that's in neither `current` nor `snapshot` — also
#' always a real bug indicator. `content_diffs`: Issue/Value text that
#' differs between `current` and the fresh `snapshot` for a finding_id
#' present in both — non-fatal review note (merge_preserve_existing() keeps
#' `current`'s row verbatim by design, so a wording/threshold change in the
#' fresh run for an already-tracked id won't get applied; worth a human
#' glance, not an error).
verify_findings_merge <- function(current, snapshot, merged) {
    cur_ids <- as.character(current$finding_id)
    snap_ids <- as.character(snapshot$finding_id)
    merged_ids <- as.character(merged$finding_id)

    dropped <- union(setdiff(cur_ids, merged_ids), setdiff(snap_ids, merged_ids))
    unexpected_added <- setdiff(merged_ids, union(cur_ids, snap_ids))

    both_ids <- intersect(cur_ids, snap_ids)
    content_diffs <- character()
    diff_cols <- intersect(c("issue", "value"), intersect(names(current), names(snapshot)))
    if (length(both_ids) && length(diff_cols)) {
        cur_m <- current[match(both_ids, cur_ids), , drop = FALSE]
        snap_m <- snapshot[match(both_ids, snap_ids), , drop = FALSE]
        for (col in diff_cols) {
        changed <- as.character(cur_m[[col]]) != as.character(snap_m[[col]])
        changed[is.na(changed)] <- FALSE
        if (any(changed)) {
            content_diffs <- c(content_diffs, sprintf("%s: %s text changed", both_ids[changed], col))
        }
        }
    }

    list(
        ok = length(dropped) == 0 && length(unexpected_added) == 0,
        dropped = dropped, unexpected_added = unexpected_added, content_diffs = content_diffs,
        n_current = nrow(current), n_snapshot = nrow(snapshot), n_merged = nrow(merged)
    )
}

#' verify_resolution_merge(current, clone, merged)
#' `clone`: today's resolutions/ clone (the field team/agent's edited
#' Status/Corrections) — the source of truth for what should have changed.
#' `dropped`: a finding_id from `current` missing from `merged` — should
#' never happen (merge_resolution_updates() only updates status/
#' corrections fields on existing rows, never removes any). `unexpected_
#' new_ids`: a finding_id present in `clone` but not in `current` at all —
#' suspicious (the clone should only ever contain ids that were already
#' being tracked).
verify_resolution_merge <- function(current, clone, merged) {
    cur_ids <- as.character(current$finding_id)
    clone_ids <- as.character(clone$finding_id)
    merged_ids <- as.character(merged$finding_id)

    dropped <- setdiff(cur_ids, merged_ids)
    unexpected_new_ids <- setdiff(clone_ids, cur_ids)

    list(
        ok = length(dropped) == 0 && length(unexpected_new_ids) == 0,
        dropped = dropped, unexpected_new_ids = unexpected_new_ids,
        n_current = nrow(current), n_clone = nrow(clone), n_merged = nrow(merged)
    )
}

#' Human-readable summary for either verification result above.
format_merge_verification <- function(v) {
    has_content_diffs <- length(v$content_diffs %||% character()) > 0
    if (isTRUE(v$ok) && !has_content_diffs) {
        return(sprintf("Merge verification: OK (%s -> %s rows).", v$n_current %||% NA, v$n_merged %||% NA))
    }
    lines <- character()
    if (length(v$dropped %||% character())) {
        lines <- c(lines, paste0("DROPPED (would silently disappear from tracking): ", paste(v$dropped, collapse = ", ")))
    }
    if (length(v$unexpected_added %||% character())) {
        lines <- c(lines, paste0("UNEXPECTED new id(s) in the merge result: ", paste(v$unexpected_added, collapse = ", ")))
    }
    if (length(v$unexpected_new_ids %||% character())) {
        lines <- c(lines, paste0("UNEXPECTED id(s) in the clone not already tracked: ", paste(v$unexpected_new_ids, collapse = ", ")))
    }
    if (has_content_diffs) {
        lines <- c(lines, paste0("Content changed but kept as-is (review note): ", paste(v$content_diffs, collapse = "; ")))
    }
    header <- if (isTRUE(v$ok)) "Merge verification: passed, with review notes" else "Merge verification: BLOCKED"
    paste0(header, "\n  ", paste(lines, collapse = "\n  "))
}
