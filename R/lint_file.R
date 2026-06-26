#' Lint a single R source file for security issues
#'
#' Parses an R source file, converts the parse tree to XML, and applies each
#' rule's XPath expression to find dangerous patterns. Returns a data frame of
#' findings, one row per match.
#'
#' @param path Path to an R source file (`.R`, `.r`).
#' @param rules Named list of rule objects as returned by [load_rules()].
#'
#' @return A data frame with columns:
#'   \describe{
#'     \item{file}{Path to the source file.}
#'     \item{line}{Line number of the finding.}
#'     \item{column}{Column number of the finding.}
#'     \item{linter}{Name of the rule that matched.}
#'     \item{message}{Human-readable description of the dangerous pattern.}
#'     \item{type}{Severity: `"warning"` or `"message"`.}
#'     \item{attck}{MITRE ATT&CK technique identifier(s).}
#'   }
#'   Returns `NULL` if the file cannot be parsed or produces no findings.
#'
#' @details
#' Parse errors are caught and reported as messages rather than stopping
#' execution. This allows [lint_dir()] and [audit_package()] to continue
#' processing remaining files when one file is malformed.
#'
#' The XPath is evaluated against the full document produced by
#' [xmlparsedata::xml_parse_data()], with `keep.source = TRUE` to preserve
#' line and column number attributes.
#'
#' @examples
#' \dontrun{
#' rules    <- load_rules()
#' findings <- lint_file("R/zzz.R", rules = rules)
#' }
#'
#' @export
lint_file <- function(path, rules) {
  stopifnot(is.character(path), length(path) == 1L)
  stopifnot(is.list(rules), length(rules) > 0L)

  parsed <- tryCatch(
    parse(file = path, keep.source = TRUE),
    error = function(e) {
      message("Parse error in: ", path, "\n  ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(parsed)) return(NULL)

  xml <- tryCatch(
    xml2::read_xml(
      xmlparsedata::xml_parse_data(parsed, pretty = TRUE)
    ),
    error = function(e) {
      message("XML conversion error in: ", path, "\n  ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(xml)) return(NULL)

  results <- lapply(names(rules), function(rule_name) {
    rule  <- rules[[rule_name]]
    nodes <- tryCatch(
      xml2::xml_find_all(xml, rule$xpath),
      error = function(e) {
        message("XPath error for rule '", rule_name, "': ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(nodes) || length(nodes) == 0L) return(NULL)

    data.frame(
      file    = path,
      line    = as.integer(xml2::xml_attr(nodes, "line1")),
      column  = as.integer(xml2::xml_attr(nodes, "col1")),
      linter  = rule_name,
      message = rule$message,
      type    = rule$type,
      attck   = rule$attck,
      stringsAsFactors = FALSE
    )
  })

  # Compact and combine
  results <- Filter(Negate(is.null), results)
  if (length(results) == 0L) return(NULL)
  do.call(rbind, results)
}
