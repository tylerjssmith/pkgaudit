#' Determine the code context of each pattern occurrence
#'
#' Assigns every pattern found by [find_patterns()] the code context it would
#' execute in. Named contexts are defined by `rules$code_contexts`: a pattern
#' occurs in a named context iff its node is a descendant of that context's
#' node. When a pattern sits inside more than one named context, the
#' most-specific (innermost) one wins.
#'
#' `"Top-level"` and `"Other"` are not rule-matched; they are computed here as
#' the fallback, because top-level code is the whole file scope minus every
#' function body.
#'
#' \enumerate{
#'   \item inside one or more named contexts -> most-specific wins;
#'   \item else no `function` ancestor -> `"Top-level"` (runs when the script is
#'     sourced during namespace construction);
#'   \item else (a `function` ancestor, but no named hook contains it) ->
#'     `"Other"` (an ordinary function that only runs when called).
#' }
#'
#' Containment is tested by exact XML path identity, never by path-prefix
#' comparison (sibling paths such as `expr[1]` and `expr[12]` would false-match).
#'
#' @param tree The `xml_document` parse tree for one script.
#' @param patterns Data frame from [find_patterns()], carrying its matched nodes
#'   in the `"nodes"` attribute aligned to the rows.
#' @param rules Loaded rules; only `rules$code_contexts` (columns `name`,
#'   `xpath`) is used. It must not contain a "top-level" entry -- top-level is
#'   computed here.
#'
#' @return `patterns` with an added `code_context` column (a named context,
#'   `"Top-level"`, or `"Other"`; never `NA`). The `"nodes"` attribute is
#'   dropped from the result.
#'
#' @keywords internal
determine_code_contexts <- function(tree, patterns, rules) {
  if (nrow(patterns) == 0L) {
    patterns$code_context <- character(0L)
    attr(patterns, "nodes") <- NULL
    return(patterns)
  }

  pattern_nodes <- attr(patterns, "nodes")

  # ---- Collect named code-context nodes via their rule XPaths ----------------
  # Single source of truth: the same XPaths used by find_code_contexts(). Errors
  # here are already surfaced by find_code_contexts(), so treat a failed XPath
  # as "no context" rather than double-reporting it.
  ctx_paths <- character(0L)
  ctx_names <- character(0L)
  cc <- rules$code_contexts
  if (!is.null(cc) && nrow(cc) > 0L) {
    for (i in seq_len(nrow(cc))) {
      nodes <- .xml_find_all_safe(tree, cc$xpath[i])
      if (inherits(nodes, "condition") || length(nodes) == 0L) next
      ctx_paths <- c(ctx_paths, xml2::xml_path(nodes))
      ctx_names <- c(ctx_names, rep(cc$name[i], length(nodes)))
    }
  }

  code_context <- character(nrow(patterns))
  for (j in seq_len(nrow(patterns))) {
    pnode <- pattern_nodes[[j]]

    winner <- if (length(ctx_paths) > 0L) {
      .deepest_context(pnode, ctx_paths, ctx_names)
    } else {
      NA_character_
    }

    code_context[[j]] <- if (!is.na(winner)) {
      winner
    } else if (.has_function_ancestor(pnode)) {
      "Other"
    } else {
      "Top-level"
    }
  }

  patterns$code_context <- code_context
  attr(patterns, "nodes") <- NULL
  patterns
}


# Most-specific named context containing pnode, or NA if none. Ancestors are
# returned root-first, so scanning from the end finds the innermost match. Uses
# exact xml_path() equality -- unambiguous node identity, not a prefix test.
.deepest_context <- function(pnode, ctx_paths, ctx_names) {
  ancestors <- xml2::xml_find_all(pnode, "ancestor::*")
  if (length(ancestors) == 0L) return(NA_character_)
  ancestor_paths <- xml2::xml_path(ancestors)
  for (k in rev(seq_along(ancestor_paths))) {
    idx <- match(ancestor_paths[[k]], ctx_paths)
    if (!is.na(idx)) return(ctx_names[[idx]])
  }
  NA_character_
}


# TRUE iff pnode has a function-definition ancestor. xmlparsedata tags the
# `function` keyword as <FUNCTION>, a child of the function-definition <expr>;
# a node in the body therefore has that expr as an ancestor. This is the
# Top-level/Other discriminator.
.has_function_ancestor <- function(pnode) {
  len <- tryCatch(
    length(xml2::xml_find_all(pnode, "ancestor::expr[FUNCTION]")),
    error = function(e) 0L
  )
  isTRUE(len > 0L)
}
