# Find code contexts, patterns and matches in one segment

Dispatches on the segment's language, which the extractor set. This is a
separate axis from the source's type: a help file and an R script both
yield R segments, and one literate file can yield several languages.

## Usage

``` r
analyze_segment(segment, rules)
```

## Arguments

- segment:

  A `pkgaudit_segment` from
  [`new_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/new_segment.md).

- rules:

  Named list of rules as returned by
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md).

## Value

A list of `patterns`, `matches`, `coverage` and `errors` data frames,
each with the columns
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
documents, less the phase columns.

## Method contract

A method must build its return value with
[`new_findings()`](https://tylerjssmith.github.io/pkgaudit/reference/new_findings.md),
which holds every analyser to the same frame shape.
[`UseMethod()`](https://rdrr.io/r/base/UseMethod.html) ends the generic,
so this cannot be enforced after dispatch.

A method must not evaluate the code it is given. It reads untrusted text
and reports what it finds; nothing in a scan is ever run.

## See also

[`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md),
the other axis of dispatch,
[`new_findings()`](https://tylerjssmith.github.io/pkgaudit/reference/new_findings.md),
and
[`vignette("internals")`](https://tylerjssmith.github.io/pkgaudit/articles/internals.md).

## Examples

``` r
# Adding a language outside pkgaudit: a method for segments the extractor
# labelled "python", reporting each line that calls eval().
analyze_segment.python <- function(segment, rules) {
  at <- grep("\\beval\\(", segment$lines)
  if (length(at) == 0L) return(new_findings())
  new_findings(matches = data.frame(
    rule = "py_eval", file_context = segment$file_context,
    line_number = at, column_number = NA_integer_,
    preview = trimws(segment$lines[at]),
    message = "eval() in Python code", attck = NA_character_))
}
registerS3method("analyze_segment", "python", analyze_segment.python)
```
