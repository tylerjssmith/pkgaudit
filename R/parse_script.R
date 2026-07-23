#' Parse an R script into an XML parse tree
#'
#' Parses a single R script with `parse(keep.source = TRUE)`, converts the parse
#' data to XML with [xmlparsedata::xml_parse_data()], and reads it into an
#' `xml_document` with [xml2::read_xml()]. Both the parse and the XML read are
#' wrapped in `tryCatch()` so a malformed or unreadable script yields a
#' recoverable error rather than aborting the audit.
#'
#' @param script Path to a single R script.
#'
#' @return A list with two elements:
#'   \describe{
#'     \item{tree}{The `xml_document` parse tree, or `NULL` on failure.}
#'     \item{error}{`NULL` on success, or a character error message on failure.}
#'   }
#'
#' @keywords internal
parse_script <- function(script) {
  stopifnot(is.character(script), length(script) == 1L)

  # suppressWarnings() muffles the connection warning R emits when a file is
  # unreadable (it raises a warning and then an error); the error is what we
  # act on. Parser warnings are not security findings.
  parsed <- tryCatch(
    suppressWarnings(parse(file = script, keep.source = TRUE)),
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
  if (inherits(tree, "condition")) {
    return(list(tree = NULL, error = conditionMessage(tree)))
  }

  list(tree = tree, error = NULL)
}
