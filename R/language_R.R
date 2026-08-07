# Analysis of R code, whatever file it came out of: an .R script, a help file's
# \examples and \Sexpr, a vignette's chunks and inline code. Dispatch is on the
# segment's language; the extractors that produce them live in type_*.R.

#' @export
analyze_segment.R <- function(segment, rules) {
  parsed <- parse_code(segment$lines)
  if (!is.null(parsed$error)) {
    return(.findings(errors = .error_row(
      step = "parse_code", file_context = segment$file_context,
      message = parsed$error
    )))
  }
  tree   <- parsed$tree
  ctx    <- .empty_code_contexts(with_phases = FALSE)
  errors <- .empty_errors()

  if (isTRUE(segment$named_contexts)) {
    cc     <- find_code_contexts(tree, rules$code_contexts,
                                 segment$file_context)
    ctx    <- cc$code_contexts
    errors <- rbind(errors, cc$errors)
  }

  fp     <- find_patterns(tree, rules$patterns, segment$file_context)
  errors <- rbind(errors, fp$errors)

  pat <- fp$patterns
  pat$preview <- .preview(segment$lines, pat$line_number, pat$column_number,
                          continues = .node_continues(attr(pat, "nodes")))
  # An attribute rather than a context: guarded code sits in the same place and
  # runs at the same phases when it runs at all, so the phases stay an upper
  # bound and the guard is reported alongside them.
  pat$guarded <- pat$line_number %in% segment$guarded_lines

  if (nrow(pat) > 0L) {
    # Where the named rules are withheld, only the Top-level/Other distinction
    # is computed: code at the top level of the segment takes the segment's own
    # context, and code inside a function definition stays "Other", since it
    # runs only if something calls it.
    pat <- determine_code_contexts(
      tree, pat,
      if (isTRUE(segment$named_contexts)) rules
      else utils::modifyList(rules, list(code_contexts = NULL))
    )
    if (!is.na(segment$context)) {
      pat$code_context[pat$code_context == .context_top_level] <- segment$context
    }
  } else {
    pat$code_context <- character(0L)
  }
  # Drop the node handle before accumulating; rbind() ignores attributes.
  attr(pat, "nodes") <- NULL

  .findings(code_contexts = ctx, patterns = pat, errors = errors)
}


# TRUE for each matched node that does not end on the line it starts on, so a
# preview of its first line can say the construct carries on.
.node_continues <- function(nodes) {
  if (length(nodes) == 0L) return(logical(0L))
  vapply(nodes, function(n) {
    !identical(xml2::xml_attr(n, "line1"), xml2::xml_attr(n, "line2"))
  }, logical(1L))
}
