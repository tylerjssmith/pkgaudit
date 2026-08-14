# This script finds calls made through a function's name rather than the
# function, and attributes them to the rule that owns the name.

# Calls that resolve a function from a string. do.call() and match.fun() take
# the name as their first argument, as getFunction() does; all three run, or
# hand back, whatever that string names.
#
# This is mechanism rather than a rule: it carries no message and no ATT&CK
# technique of its own, and every finding it produces is reported under another
# rule. That is why the XPath lives here instead of in inst/rules/.
#
# The literal must sit in the first argument position, so do.call(fn, "system")
# -- where the string is data passed to some other function -- does not match.
.indirect_xpath <- paste(
  "//expr[",
  "  expr/SYMBOL_FUNCTION_CALL[",
  "    (text() = 'do.call' or text() = 'match.fun'",
  "      or text() = 'getFunction')",
  "    and not(preceding-sibling::OP-DOLLAR)",
  "    and not(preceding-sibling::OP-AT)",
  "  ]",
  "  and expr[preceding-sibling::OP-LEFT-PAREN][1]/STR_CONST",
  "]",
  collapse = " "
)

# The literal naming the target, relative to a matched call.
.indirect_target_xpath <- "./expr[preceding-sibling::OP-LEFT-PAREN][1]/STR_CONST"


#' Find calls made through a function's name
#'
#' Finds `do.call("system", ...)` and its siblings: a call to a function named
#' by a string literal, which no pattern rule's XPath can see because the target
#' is not a call site.
#'
#' @param tree The `xml_document` parse tree for one segment (from
#'   [parse_code()]).
#' @param pattern_rules Data frame of pattern rules (`rules$patterns` from
#'   [load_rules()]). Only the `functions` column decides what is found; the
#'   matched rule supplies the row's `rule`, `message`, and `attck`.
#' @param file_context Package-root-relative path, carried through for joining.
#'
#' @return A list with two data frames, shaped exactly as [find_patterns()]
#'   returns them so the two can be combined:
#'   \describe{
#'     \item{patterns}{The columns [find_patterns()] produces, plus `indirect`,
#'       which is `TRUE` on every row. Carries the matched nodes as a `"nodes"`
#'       attribute, aligned to the rows.}
#'     \item{errors}{Data frame with columns `step`, `file_context`, `rule`,
#'       `message`.}
#'   }
#'
#' @details
#' A finding is reported under the rule that owns the name, not under a rule of
#' its own, so filtering for `rule == "system"` returns every call to `system`
#' however it was spelled, and the `indirect` column says which is which. The
#' line and column point at the string literal rather than at `do.call`, since
#' the literal is what a reviewer needs to look at.
#'
#' @section Security considerations:
#' A name is claimed by a rule only if calling it bare would have matched that
#' rule's own XPath, which `inst/scripts/build_db.R` verifies when the database
#' is built. An indirect finding therefore can never be attributed to a rule
#' that would not have reported the direct call.
#'
#' A name the rules do not declare is not reported, so this under-covers rather
#' than guesses -- as does a target assembled at runtime, such as
#' `do.call(paste0("sys", "tem"), ...)`, which carries no literal to read.
#'
#' @keywords internal
find_indirect <- function(tree, pattern_rules, file_context) {
  empty <- .empty_indirect()
  if (is.null(pattern_rules) || nrow(pattern_rules) == 0L ||
      is.null(pattern_rules$functions)) {
    return(list(patterns = empty, errors = .empty_errors()))
  }

  owner <- .function_owners(pattern_rules)
  if (length(owner) == 0L) {
    return(list(patterns = empty, errors = .empty_errors()))
  }

  nodes <- .xml_find_all_safe(tree, .indirect_xpath)
  if (inherits(nodes, "condition")) {
    return(list(patterns = empty, errors = .error_row(
      step = "find_indirect", file_context = file_context,
      message = conditionMessage(nodes)
    )))
  }
  if (length(nodes) == 0L) {
    return(list(patterns = empty, errors = .empty_errors()))
  }

  rows     <- list()
  node_bag <- list()
  for (i in seq_along(nodes)) {
    literal <- xml2::xml_find_first(nodes[[i]], .indirect_target_xpath)
    target  <- .string_value(xml2::xml_text(literal))
    if (is.na(target) || !target %in% names(owner)) next

    rule <- pattern_rules[match(owner[[target]], pattern_rules$name), ,
                          drop = FALSE]
    rows[[length(rows) + 1L]] <- data.frame(
      rule          = rule$name,
      file_context  = file_context,
      # The literal, not the do.call, is what a reviewer opens the file to read.
      line_number   = as.integer(xml2::xml_attr(literal, "line1")),
      column_number = as.integer(xml2::xml_attr(literal, "col1")),
      message       = rule$message,
      attck         = rule$attck,
      indirect      = TRUE,
      stringsAsFactors = FALSE
    )
    node_bag[[length(node_bag) + 1L]] <- nodes[[i]]
  }

  patterns <- if (length(rows) == 0L) empty else do.call(rbind, rows)
  attr(patterns, "nodes") <- node_bag
  list(patterns = patterns, errors = .empty_errors())
}


# A named vector mapping each declared function name to the rule that owns it.
#
# A name declared by two rules would make attribution arbitrary, so the first in
# the rules' order wins and is stable; build_db.R does not forbid the overlap
# because two rules can legitimately match the same call.
.function_owners <- function(pattern_rules) {
  declared <- strsplit(pattern_rules$functions, "[[:space:]]+")
  owner    <- character(0L)
  for (i in seq_along(declared)) {
    names_i <- declared[[i]][nzchar(declared[[i]])]
    new     <- setdiff(names_i, names(owner))
    owner[new] <- pattern_rules$name[[i]]
  }
  owner
}


# The value of an R string literal, as written in source, or NA if it is not one
# the parser recorded whole. Only the plain quoted forms are read: a raw string
# or an escape would have to be unescaped to compare, and getting that subtly
# wrong would attribute a finding to the wrong rule.
.string_value <- function(text) {
  if (length(text) != 1L || is.na(text)) return(NA_character_)
  if (!grepl('^(".*"|\'.*\')$', text)) return(NA_character_)
  inner <- substr(text, 2L, nchar(text) - 1L)
  if (grepl("\\\\", inner)) return(NA_character_)
  inner
}


# The frame find_indirect() returns when it finds nothing: the columns
# find_patterns() produces, plus indirect, which is what it returns when it
# finds something.
.empty_indirect <- function() {
  out <- .empty_found()
  out$indirect <- logical(0L)
  attr(out, "nodes") <- list()
  out
}
