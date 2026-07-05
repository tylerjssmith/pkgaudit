#' Audit a single R source file for security-relevant patterns
#'
#' Parses an R source file, converts the parse tree to XML, and applies each
#' rule's XPath expression to find matching patterns.
#'
#' @param path Path to an R source file (`.R`, `.r`).
#' @param rules Named list of rule objects as returned by [load_rules()].
#'
#' @return A `pkgaudit_result` with two fields:
#'   \describe{
#'     \item{findings}{Data frame with columns `file`, `line`, `column`,
#'       `rule`, `message`, `type`, and `attck`. Zero rows when no patterns
#'       match.}
#'     \item{errors}{Named character vector of parse or XML errors, where
#'       names are file paths and values are error messages. Zero-length when
#'       the file was successfully inspected.}
#'   }
#'
#' @details
#' Parse and XML errors are caught and reported as messages rather than
#' stopping execution, so [audit_dir()] and [audit_package()] can continue
#' processing remaining files. The error is also recorded in `$errors` so
#' callers can distinguish a failed inspection from a clean one.
#'
#' The XPath is evaluated against the full document produced by
#' [xmlparsedata::xml_parse_data()], with `keep.source = TRUE` to preserve
#' line and column number attributes.
#'
#' @examples
#' \dontrun{
#' rules  <- load_rules()
#' result <- audit_file("R/zzz.R", rules = rules)
#' result$findings
#' result$errors
#' }
#'
#' @export
audit_file <- function(path, rules) {
  stopifnot(is.character(path), length(path) == 1L)
  stopifnot(is.list(rules), length(rules) > 0L)

  res <- tryCatch(
    list(val = parse(file = path, keep.source = TRUE), err = NULL),
    error = function(e) list(val = NULL, err = conditionMessage(e))
  )
  if (!is.null(res$err)) {
    message("Parse error in: ", path, "\n  ", res$err)
    return(.pkgaudit_result(.empty_findings(), setNames(res$err, path)))
  }
  parsed <- res$val

  res <- tryCatch(
    list(val = xml2::read_xml(xmlparsedata::xml_parse_data(parsed, pretty = TRUE)), err = NULL),
    error = function(e) list(val = NULL, err = conditionMessage(e))
  )
  if (!is.null(res$err)) {
    message("XML error in: ", path, "\n  ", res$err)
    return(.pkgaudit_result(.empty_findings(), setNames(res$err, path)))
  }
  xml <- res$val

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
      rule    = rule_name,
      message = rule$message,
      type    = rule$type,
      attck   = rule$attck
    )
  })

  results  <- Filter(Negate(is.null), results)
  findings <- if (length(results) == 0L) .empty_findings() else do.call(rbind, results)
  .pkgaudit_result(findings)
}
