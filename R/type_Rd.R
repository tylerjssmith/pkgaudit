# Extraction for help files. An .Rd yields a segment per kind of code that runs
# at its own time: the \examples, and one per \Sexpr stage. All are R, and are
# analysed by the methods in language_R.R.

#' @export
extract_segments.Rd <- function(source) {
  rd <- extract_Rd_code(source$path, macros = source$macros)

  errors <- .empty_errors()
  if (!is.null(rd$error)) {
    errors <- .error_row(
      step = "extract_Rd_code", file_context = source$file_context,
      message = rd$error
    )
    # Whatever was recovered is still scanned; the error records that the
    # account of the file is incomplete.
  }

  # One segment per kind of code that runs at its own time: the examples, and
  # one per \Sexpr stage.
  parts <- c(
    list(list(text = rd$examples, context = .context_rd_examples,
              guarded = rd$guarded)),
    lapply(names(.context_rd_sexpr), function(stage) {
      list(text = rd$sexpr[[stage]], context = .context_rd_sexpr[[stage]],
           guarded = integer(0L))
    })
  )

  segments <- list()
  for (part in parts) {
    if (!nzchar(trimws(part$text))) next
    segments[[length(segments) + 1L]] <- new_segment(
      language     = "R",
      lines        = strsplit(part$text, "\n", fixed = TRUE)[[1L]],
      file_context = source$file_context,
      context      = part$context,
      # A help file defines no code contexts of its own: a hook assigned in an
      # example is not a hook.
      named_contexts = FALSE,
      guarded_lines  = part$guarded
    )
  }
  list(segments = segments, errors = errors)
}
