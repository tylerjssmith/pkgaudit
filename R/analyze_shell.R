# Analysis of shell code, whatever file it came out of: a configure script, a
# Makevars, a {bash} chunk in a vignette. Dispatch is on the segment's language;
# the extractors that produce them live in extract_*.R.

#' @export
analyze_segment.shell <- function(segment, rules) {
  fm  <- find_matches(segment$lines, .rules_for(rules$matches, "shell"),
                      segment$file_context)
  mat <- fm$matches
  mat$preview <- .preview(segment$lines, mat$line_number, mat$column_number)

  new_findings(matches = mat, errors = fm$errors)
}


# A match rule is evaluated only against segments in its own language, so a
# shell rule is never applied to R code. Rules that name no language are kept:
# a rules list assembled by hand in a test should not silently match nothing.
.rules_for <- function(match_rules, language) {
  if (is.null(match_rules) || nrow(match_rules) == 0L) return(match_rules)
  if (is.null(match_rules$language)) return(match_rules)
  match_rules[is.na(match_rules$language) | match_rules$language == language, ,
              drop = FALSE]
}
