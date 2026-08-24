#' Parse R code into an XML parse tree
#'
#' Parses R code with `parse(keep.source = TRUE)`, converts it to XML with
#' [xmlparsedata::xml_parse_data()] and reads it with [xml2::read_xml()]. Each
#' step is wrapped so malformed code yields a recoverable error rather than
#' aborting the scan.
#'
#' @param lines Character vector of R source, one element per line, as returned
#'   by [read_code()].
#'
#' @return A list with two elements:
#'   \describe{
#'     \item{tree}{The `xml_document` parse tree, or `NULL` on failure.}
#'     \item{error}{`NULL` on success, or a character error message on failure.}
#'   }
#'
#' @details
#' Code is taken as text, not a path, so one parser serves both an R script and
#' the code [read_Rd_code()] recovers from a help file. `parse()` numbers lines
#' from the start of what it is given, so a caller whose lines stay aligned to
#' the source file gets source references pointing into it directly. Both
#' readers keep that alignment.
#'
#' @keywords internal
parse_code <- function(lines) {
  stopifnot(is.character(lines))

  # An empty file is an empty program, but parse() refuses a zero-length
  # argument, so it is normalized to one empty line.
  if (length(lines) == 0L) lines <- ""

  # Parser warnings are not security findings; the error is what we act on.
  parsed <- tryCatch(
    suppressWarnings(parse(text = lines, keep.source = TRUE)),
    error = function(e) e
  )
  if (inherits(parsed, "condition")) {
    return(list(tree = NULL, error = conditionMessage(parsed)))
  }

  tree <- tryCatch(
    xml2::read_xml(
      xmlparsedata::xml_parse_data(parsed, pretty = TRUE),
      options = "HUGE"
    ),
    error = function(e) e
  )
  # nocov start
  # No R source that parses has been found to produce a document xml2 rejects.
  if (inherits(tree, "condition")) {
    return(list(tree = NULL, error = conditionMessage(tree)))
  }
  # nocov end

  list(tree = tree, error = NULL)
}
