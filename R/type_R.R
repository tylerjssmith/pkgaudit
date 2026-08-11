# Extraction for R source files: R/, and every other place a package carries
# plain R that something evaluates.
#
# The R segments this produces are analysed in language_R.R -- as are the R
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
      language       = "R",
      lines          = read$lines,
      file_context   = source$file_context,
      # NA leaves determine_code_contexts() to place patterns as usual. A rule
      # naming any other context replaces `R` with it, so a finding in
      # data/ or tests/ carries that file type's phases instead of R/'s.
      context = if (identical(source$code_context, .context_top_level))
                  NA_character_ else source$code_context,
      # The named hook rules apply only where the code becomes the namespace.
      named_contexts = source$namespace_source
    )),
    errors = errors
  )
}
