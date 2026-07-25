#' Find security-relevant code contexts in a parsed script
#'
#' Finds code contexts -- top-level code or lifecycle hooks (e.g., `.onLoad`,
#' `.onAttach`, `.onUnload`, `.onDetach`, `.Last.lib`, `rlang::on_load`) whose
#' bodies execute when a package namespace is loaded, attached, unloaded, or
#' detached.
#'
#' @param tree The `xml_document` parse tree for one script (from
#'   [parse_script()]).
#' @param code_context_rules Data frame of code-context rules
#'   (`rules$code_contexts` from [load_rules()]), with columns `name`, `xpath`,
#'   and `message`.
#' @param file_context Package-root-relative path of the script, carried through
#'   for joining to the file-contexts table.
#'
#' @return A list with two data frames:
#'   \describe{
#'     \item{code_contexts}{Data frame with columns `code_context`,
#'       `file_context`, `line_number`, `column_number`, `message`.}
#'     \item{errors}{Data frame with columns `stage`, `file_context`, `rule`,
#'       `message`.}
#'   }
#'
#' @details
#' For each code-context rule, this function evaluates the rule's XPath against
#' the parse tree with `.xml_find_all_safe()`. Every matching node is a code
#' context found. A failing or invalid XPath (including one that libxml2 reports
#' only as a warning) comes back as a condition, which is recorded in the errors
#' data frame before the loop moves on to the next rule.
#'
#' @keywords internal
find_code_contexts <- function(tree, code_context_rules, file_context) {
  found  <- list()
  errors <- .empty_errors()

  if (is.null(code_context_rules) || nrow(code_context_rules) == 0L) {
    return(list(code_contexts = .empty_code_contexts(), errors = errors))
  }

  for (i in seq_len(nrow(code_context_rules))) {
    rule  <- code_context_rules[i, , drop = FALSE]
    nodes <- .xml_find_all_safe(tree, rule$xpath)

    if (inherits(nodes, "condition")) {
      errors <- rbind(errors, .error_row(
        stage        = "find_code_contexts",
        file_context = file_context,
        rule         = rule$name,
        message      = conditionMessage(nodes)
      ))
      next
    }
    if (length(nodes) == 0L) next

    found[[length(found) + 1L]] <- data.frame(
      code_context  = rule$name,
      file_context  = file_context,
      line_number   = as.integer(xml2::xml_attr(nodes, "line1")),
      column_number = as.integer(xml2::xml_attr(nodes, "col1")),
      message       = rule$message,
      stringsAsFactors = FALSE
    )
  }

  code_contexts <- if (length(found) == 0L) {
    .empty_code_contexts()
  } else {
    do.call(rbind, found)
  }

  list(code_contexts = code_contexts, errors = errors)
}
