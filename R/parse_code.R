#' Parse R code into an XML parse tree
#'
#' Parses R code with `parse(keep.source = TRUE)`, converts the parse data to
#' XML with [xmlparsedata::xml_parse_data()], and reads it into an
#' `xml_document` with [xml2::read_xml()]. The parse and the XML
#' conversion-and-read are each wrapped in `tryCatch()` so malformed code yields
#' a recoverable error rather than aborting the audit.
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
#' Code is taken as text rather than read from a path so that one parser serves
#' both an R script, whose lines are the file itself, and a help file, whose R
#' code is extracted from `\examples{}` and `\Sexpr{}` by [extract_Rd_code()].
#'
#' `parse()` numbers lines from the start of what it is given, so a caller that
#' keeps its lines aligned to the file they came from gets source references
#' pointing into the original file with no further adjustment. Both readers do.
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
  # The scan still refuses to abort on one if it ever appears.
  if (inherits(tree, "condition")) {
    return(list(tree = NULL, error = conditionMessage(tree)))
  }
  # nocov end

  list(tree = tree, error = NULL)
}
