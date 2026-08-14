# Extraction for R source files: R/, and every other place a package carries
# plain R that something evaluates.
#
# The R segments this produces are analysed in analyze_R.R -- as are the R
# segments an .Rd, .Rmd, .Rnw or .rsp yields. Reading a file and analysing what
# comes out dispatch on different axes, so they live in different files.

#' @export
extract_segments.R <- function(source) {
  read <- read_code(source$path)

  errors <- if (is.null(read$error)) .empty_errors() else .error_row(
    step = "read_code", file_context = source$file_context,
    message = read$error
  )
  if (is.null(read$lines)) return(list(segments = list(), errors = errors))

  list(
    segments = list(new_segment(
      language      = "R",
      lines         = read$lines,
      file_context  = source$file_context,
      # An R script carries no segment label. What its top-level code belongs to
      # is a property of the file context, resolved when phases are attached,
      # rather than of anything the segment itself can say.
      context       = NA_character_,
      file_rule     = source$file_rule,
      code_contexts = source$code_contexts
    )),
    errors = errors
  )
}
