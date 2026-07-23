#' Find code contexts in a parsed script
#'
#' A *code context* is top-level code or a lifecycle hook (`.onLoad`,
#' `.onAttach`, `.onUnload`, `.onDetach`, `.Last.lib`, `rlang::on_load`) whose
#' body executes when a package namespace is loaded, attached, unloaded, or
#' detached. For each code-context rule this function evaluates the rule's XPath
#' against the parse tree; every matching node is a code context found.
#'
#' Each `xml_find_all()` call is wrapped in `tryCatch()`; a failure is recorded
#' in the errors data frame and the loop moves on to the next rule. When a rule
#' matches more than once in a script, every match is returned.
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
#'     \item{code_contexts}{Columns `code_context`, `file_context`,
#'       `line_number`, `column_number`, `message`.}
#'     \item{errors}{Columns `stage`, `file_context`, `rule`, `message`.}
#'   }
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


# Evaluate an XPath, promoting libxml2 warnings (e.g. invalid XPath) to errors
# so an ill-formed expression is caught rather than silently returning nothing.
# Returns the node set on success or the caught condition on failure.
.xml_find_all_safe <- function(tree, xpath) {
  tryCatch(
    withCallingHandlers(
      xml2::xml_find_all(tree, xpath),
      warning = function(w) stop(conditionMessage(w))
    ),
    error = function(e) e
  )
}
