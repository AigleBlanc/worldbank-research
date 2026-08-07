# Minimal, dependency-free .docx -> plain text extraction. A .docx file is
# just a zip archive containing word/document.xml (WordprocessingML), so
# this unzips that one entry with base R and strips markup — no new R
# package needed for SKILL.md's context_doc reading (A1 step 1b). Does not
# handle legacy binary .doc (not a zip container) — that still needs the
# user to export as .docx or PDF.
# Usage:
#   Rscript docx_text.R <path-to-docx> [out-path]
#   source(); out_path <- docx_to_text(path)

docx_to_text <- function(path, out_path = NULL) {
    stopifnot(file.exists(path))
    tmp_dir <- tempfile("docx_")
    dir.create(tmp_dir)
    utils::unzip(path, files = "word/document.xml", exdir = tmp_dir, junkpaths = TRUE)
    xml_path <- file.path(tmp_dir, "document.xml")
    if (!file.exists(xml_path)) {
        stop("Not a valid .docx (no word/document.xml found): ", path)
    }
    xml <- paste(readLines(xml_path, warn = FALSE, encoding = "UTF-8"), collapse = "")

    xml <- gsub("</w:p>", "\n", xml, fixed = TRUE)
    xml <- gsub("<w:tab/>", "\t", xml, fixed = TRUE)
    xml <- gsub("<[^>]+>", "", xml)
    xml <- gsub("&amp;", "&", xml, fixed = TRUE)
    xml <- gsub("&lt;", "<", xml, fixed = TRUE)
    xml <- gsub("&gt;", ">", xml, fixed = TRUE)
    xml <- gsub("&quot;", "\"", xml, fixed = TRUE)
    xml <- gsub("&apos;", "'", xml, fixed = TRUE)
    xml <- gsub("[ \t]+\n", "\n", xml)
    xml <- gsub("\n{3,}", "\n\n", xml)
    text <- trimws(xml)

    if (is.null(out_path)) {
        out_path <- file.path(tempdir(), paste0(tools::file_path_sans_ext(basename(path)), ".txt"))
    }
    writeLines(text, out_path)
    out_path
}

cmd_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", cmd_args, value = TRUE)
is_main <- length(file_arg) > 0 && grepl("docx_text\\.R$", file_arg[[1]])

if (is_main) {
    args <- commandArgs(trailingOnly = TRUE)
    if (!length(args)) stop("Usage: Rscript docx_text.R <path-to-docx> [out-path]")
    out <- docx_to_text(args[[1]], out_path = if (length(args) > 1) args[[2]] else NULL)
    cat(out, "\n")
}
