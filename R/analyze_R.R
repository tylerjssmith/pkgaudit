# Analysis of R code, whatever file it came out of: an .R script, a help file's
# \examples and \Sexpr, a vignette's chunks and inline code. Dispatch is on the
# segment's language; the extractors that produce them live in extract_*.R.

#' @export
analyze_segment.R <- function(segment, rules) {
  parsed <- parse_code(segment$lines)
  if (!is.null(parsed$error)) {
    return(new_findings(errors = .error_row(
      step = "parse_code", file_context = segment$file_context,
      message = parsed$error
    )))
  }
  tree   <- parsed$tree
  errors <- .empty_errors()

  # Only the rules this segment's file context names, and of those only the ones
  # matched against the parse tree. A `kind: segment` rule claims the segment as
  # a whole and has no XPath to evaluate.
  applicable <- .applicable_contexts(rules$code_contexts, segment$code_contexts)

  # Run for its errors: determine_code_contexts() evaluates the same XPaths to
  # place patterns but skips one that fails, so without this a broken
  # code-context rule would quietly stop matching.
  if (nrow(applicable) > 0L) {
    errors <- rbind(errors, find_code_contexts(tree, applicable,
                                               segment$file_context)$errors)
  }

  fp     <- find_patterns(tree, rules$patterns, segment$file_context)
  errors <- rbind(errors, fp$errors)

  # A call made through a function's name is reported under the rule that owns
  # the name, so the two sets of findings are one frame from here on and get
  # previews, guards and code contexts alike.
  fi     <- find_indirect(tree, rules$patterns, segment$file_context)
  errors <- rbind(errors, fi$errors)

  fp$patterns$indirect <- rep(FALSE, nrow(fp$patterns))
  pat   <- rbind(fp$patterns, fi$patterns)
  # rbind() drops attributes, so the node handles are carried across by hand.
  nodes <- c(attr(fp$patterns, "nodes"), attr(fi$patterns, "nodes"))
  attr(pat, "nodes") <- nodes

  pat$preview <- .preview(segment$lines, pat$line_number, pat$column_number,
                          continues = .node_continues(nodes))
  # An attribute rather than a context: guarded code sits in the same place and
  # runs at the same phases when it runs at all, so the phases stay an upper
  # bound and the guard is reported alongside them.
  pat$guarded <- pat$line_number %in% segment$guarded_lines

  if (nrow(pat) > 0L) {
    # Where no named rule applies, only the top_level/in_function distinction is
    # computed: whether the code sits inside a function definition. What that
    # means for phases is decided later, from the file context.
    # Assigned rather than merged: modifyList() recurses when both sides are
    # lists, and a data frame is a list, so it would splice columns together.
    applicable_rules <- rules
    applicable_rules$code_contexts <- applicable
    pat <- determine_code_contexts(tree, pat, applicable_rules)
    # A segment carrying a label attributes its top-level code to that label --
    # a help file's \examples run when the examples do. Code inside a function
    # keeps in_function and inherits the label's phases when they are resolved,
    # so the fact that it sits in a function is not lost here.
    if (!is.na(segment$context)) {
      pat$code_context[pat$code_context == .context_top_level] <- segment$context
    }
  } else {
    pat$code_context <- character(0L)
  }
  # Drop the node handle before accumulating; rbind() ignores attributes.
  attr(pat, "nodes") <- NULL

  # Where the code sat, which resolving its phases needs alongside where it is.
  pat$file_rule       <- rep(segment$file_rule, nrow(pat))
  pat$rd_context <- rep(segment$context, nrow(pat))

  new_findings(patterns = pat, errors = errors)
}


# The code-context rules that apply to a segment, from the names its file
# context declared, restricted to those matched against the parse tree.
#
# A file context naming none yields none: that is how the lifecycle hooks stay
# out of data/ and tests/, where the probe package measures that a .onLoad never
# fires.
.applicable_contexts <- function(code_contexts, names) {
  empty <- code_contexts[0L, , drop = FALSE]
  if (is.null(code_contexts) || nrow(code_contexts) == 0L) return(empty)
  if (is.null(names) || length(names) == 0L) return(empty)
  code_contexts[code_contexts$name %in% names &
                code_contexts$kind == "xpath", , drop = FALSE]
}


# TRUE for each matched node that does not end on the line it starts on, so a
# preview of its first line can say the construct carries on.
.node_continues <- function(nodes) {
  if (length(nodes) == 0L) return(logical(0L))
  vapply(nodes, function(n) {
    !identical(xml2::xml_attr(n, "line1"), xml2::xml_attr(n, "line2"))
  }, logical(1L))
}
