#' Find security-relevant patterns in a parsed script
#'
#' Finds patterns -- syntactic constructs of interest (e.g., `system()`,
#' `eval(parse())`, an outbound HTTP call).
#'
#' @param tree The `xml_document` parse tree for one script (from
#'   [parse_code()]).
#' @param pattern_rules Data frame of pattern rules (`rules$patterns` from
#'   [load_rules()]), with columns `name`, `xpath`, `message`, and `attck`.
#' @param file_context Package-root-relative path of the script, carried through
#'   for joining to the file-contexts table.
#'
#' @return A list with two data frames:
#'   \describe{
#'     \item{patterns}{Data frame with columns `rule` (the matching rule's
#'       name), `file_context`, `line_number`, `column_number`, `message`,
#'       `attck`. Carries a `"nodes"` attribute holding the matched nodes
#'       aligned to the rows. The phase columns are not set here;
#'       [audit_package()] attaches them from the code context each pattern is
#'       assigned.}
#'     \item{errors}{Data frame with columns `step`, `file_context`, `rule`,
#'       `message`.}
#'   }
#'
#' @details
#' Each rule's XPath is evaluated with `.xml_find_all_safe()`, so an invalid one
#' -- including one libxml2 reports only as a warning -- is recorded in `errors`
#' and the scan moves on.
#'
#' The `"nodes"` attribute holds the matched XML nodes aligned row-for-row, so
#' [determine_code_contexts()] can test containment by node identity without
#' re-running the pattern XPaths.
#'
#' @keywords internal
find_patterns <- function(tree, pattern_rules, file_context) {
  rows      <- list()
  node_bag  <- list()
  errors    <- .empty_errors()

  if (is.null(pattern_rules) || nrow(pattern_rules) == 0L) {
    out <- .empty_found()
    attr(out, "nodes") <- list()
    return(list(patterns = out, errors = errors))
  }

  for (i in seq_len(nrow(pattern_rules))) {
    rule  <- pattern_rules[i, , drop = FALSE]
    nodes <- .xml_find_all_safe(tree, rule$xpath)

    if (inherits(nodes, "condition")) {
      errors <- rbind(errors, .error_row(
        step         = "find_patterns",
        file_context = file_context,
        rule         = rule$name,
        message      = conditionMessage(nodes)
      ))
      next
    }
    if (length(nodes) == 0L) next

    rows[[length(rows) + 1L]] <- data.frame(
      rule          = rule$name,
      file_context  = file_context,
      line_number   = as.integer(xml2::xml_attr(nodes, "line1")),
      column_number = as.integer(xml2::xml_attr(nodes, "col1")),
      message       = rule$message,
      attck         = rule$attck,
      stringsAsFactors = FALSE
    )
    for (n in seq_along(nodes)) {
      node_bag[[length(node_bag) + 1L]] <- nodes[[n]]
    }
  }

  patterns <- if (length(rows) == 0L) .empty_found() else do.call(rbind, rows)

  attr(patterns, "nodes") <- node_bag
  list(patterns = patterns, errors = errors)
}
