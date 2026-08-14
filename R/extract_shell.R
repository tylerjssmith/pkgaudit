# Methods for the files R hands to a shell or to make: configure, cleanup,
# src/Makevars and their platform variants.
#
# `make` inherits from `shell`. The two are separate rule types because a
# Makefile is not a shell script, but reading them is identical and both yield
# shell segments, so one method serves both.
#
# The shell segments this produces are analysed in analyze_shell.R, as are the
# {bash} and {sh} chunks a vignette yields.

#' @export
extract_segments.shell <- function(source) {
  read <- read_code(source$path)

  errors <- if (is.null(read$error)) .empty_errors() else .error_row(
    step = "read_code", file_context = source$file_context,
    message = read$error
  )
  if (is.null(read$lines)) return(list(segments = list(), errors = errors))

  list(
    segments = list(new_segment(
      language     = "shell",
      lines        = read$lines,
      file_context = source$file_context,
      file_rule    = source$file_rule
    )),
    errors = errors
  )
}
