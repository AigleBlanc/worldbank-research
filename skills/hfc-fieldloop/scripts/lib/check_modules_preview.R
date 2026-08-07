# Writes hfc/config/modules.yaml itself — commented, human-readable, and
# directly editable — as the pre-decision artifact the user reviews before
# confirming (SKILL.md A2), replacing the old check_modules.html tree
# preview entirely. Written once as a draft (this module's proposed
# defaults) BEFORE the review AskUserQuestion window opens, so the agent
# can give the user a real, already-existing path to open; written again
# after any chat corrections so the file on disk always matches what was
# actually confirmed.
#
# yaml::write_yaml()/as.yaml() can't emit comments on their own, so this
# hand-assembles the output: a short header block, then per module (in
# MODULE_ORDER) a wrapped "# M<n> — <label>: <desc>" comment — desc from
# module_desc() (build_outputs.R/module_desc.R), which is already
# config-aware (states the actual configured threshold, not just "a
# threshold exists") — directly above that module's own yaml block.

# Wrap `text` into "# "-prefixed lines no wider than `width` — keeps the
# generated comments readable in a normal-width editor pane instead of one
# giant unwrapped line per module.
.wrap_comment <- function(text, width = 78) {
    words <- strsplit(text, "\\s+")[[1]]
    lines <- character()
    cur <- ""
    for (w in words) {
        cand <- if (nzchar(cur)) paste(cur, w) else w
        if (nchar(cand) > width && nzchar(cur)) {
            lines <- c(lines, cur)
            cur <- w
        } else {
            cur <- cand
        }
    }
    if (nzchar(cur)) lines <- c(lines, cur)
    paste0("# ", lines)
}

write_commented_modules_yaml <- function(modules, modules_path) {
    dir.create(dirname(modules_path), recursive = TRUE, showWarnings = FALSE)

    header <- c(
        "# HFC FieldLoop check-module configuration",
        "#",
        "# Controls which data-quality checks run and how they're tuned. Each",
        "# module below (M1-M13) has a short description of what it does, then",
        "# its settings.",
        "#",
        "# - To turn a check off entirely: change its \"on: yes\" to \"on: no\".",
        "# - To change a threshold or variable list: edit the value directly.",
        "# - Save the file when you're done — changes take effect the next time",
        "#   the report is built or rebuilt.",
        ""
    )

    blocks <- lapply(MODULE_ORDER, function(code) {
        m <- modules[[code]] %||% list()
        label <- module_label(code)
        desc <- module_desc(code, modules)
        comment_lines <- .wrap_comment(sprintf("%s — %s: %s", code, label, desc))
        # `desc` is also written as its own yaml key (Title Case, e.g. "Completion",
        # "GPS Location") -- not just folded into the comment above -- so anyone
        # opening this file cold can tell what a module is without cross-referencing
        # check_modules.md.
        m_with_desc <- c(list(desc = label), m)
        yaml_block <- strsplit(yaml::as.yaml(setNames(list(m_with_desc), code)), "\n")[[1]]
        c(comment_lines, yaml_block, "")
    })

    lines <- c(header, unlist(blocks, use.names = FALSE))
    writeLines(lines, modules_path)
    invisible(normalizePath(modules_path))
}
