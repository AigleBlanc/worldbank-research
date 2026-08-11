# Plain-text dump of EVERY sheet in a SurveyCTO/XLSForm instrument workbook,
# not just the first one. A raw `Read` of an .xlsx file only surfaces its
# first sheet, but a real instrument routinely spreads what the agent needs
# across several: `survey` (question name/type/label/relevant/required —
# question text and skip logic), `choices` (list_name/value/label — the
# value labels behind every select_one/select_multiple question, e.g. what
# code 1 vs 2 actually means), and `settings` (form_title/form_id/version).
# Reading `survey` alone misses the choice-code meanings entirely, which
# matters for judging gate pass values, sentinel codes, and consent-option
# wording (SKILL.md A1 steps 7b/9a). Same role for the instrument as
# docx_text.R plays for a .docx context_doc: dump to plain text once, then
# `Read` the dump instead of the binary workbook.
# Usage:
#   Rscript form_text.R <path-to-xlsx> [out-path]
#   source(); out_path <- form_to_text(path)

# Cap per sheet so one huge admin-boundary choice list doesn't blow out the
# agent's read — the header always states the true row count either way.
FORM_TEXT_MAX_ROWS <- 300L

form_to_text <- function(path, out_path = NULL) {
    stopifnot(file.exists(path))
    if (!requireNamespace("readxl", quietly = TRUE)) {
        stop("readxl package required to read: ", path)
    }
    sheets <- readxl::excel_sheets(path)
    blocks <- vapply(sheets, function(sh) {
        dat <- tryCatch(
        as.data.frame(readxl::read_excel(path, sheet = sh, col_types = "text"), stringsAsFactors = FALSE),
        error = function(e) NULL
        )
        if (is.null(dat)) {
        return(sprintf("=== SHEET: %s (could not be read) ===\n", sh))
        }
        if (!nrow(dat) || !ncol(dat)) {
        return(sprintf("=== SHEET: %s (0 rows) ===\n", sh))
        }
        clean_cell <- function(x) {
        x[is.na(x)] <- ""
        gsub("\\s+", " ", trimws(x))
        }
        dat[] <- lapply(dat, clean_cell)
        n_show <- min(nrow(dat), FORM_TEXT_MAX_ROWS)
        header <- paste(names(dat), collapse = " | ")
        rows <- apply(dat[seq_len(n_show), , drop = FALSE], 1, paste, collapse = " | ")
        note <- if (nrow(dat) > n_show) {
        sprintf("\n... %d more rows truncated ...", nrow(dat) - n_show)
        } else ""
        sprintf(
        "=== SHEET: %s (%d rows x %d cols) ===\n%s\n%s%s\n",
        sh, nrow(dat), ncol(dat), header, paste(rows, collapse = "\n"), note
        )
    }, character(1))

    text <- paste(blocks, collapse = "\n")
    if (is.null(out_path)) {
        out_path <- file.path(tempdir(), paste0(tools::file_path_sans_ext(basename(path)), "_allsheets.txt"))
    }
    writeLines(text, out_path)
    out_path
}

cmd_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", cmd_args, value = TRUE)
is_main <- length(file_arg) > 0 && grepl("form_text\\.R$", file_arg[[1]])

if (is_main) {
    args <- commandArgs(trailingOnly = TRUE)
    if (!length(args)) stop("Usage: Rscript form_text.R <path-to-xlsx> [out-path]")
    suppressPackageStartupMessages({
        if (requireNamespace("readxl", quietly = TRUE)) library(readxl)
    })
    out <- form_to_text(args[[1]], out_path = if (length(args) > 1) args[[2]] else NULL)
    cat(out, "\n")
}
