# Determine the code context of each pattern occurrence

Assigns every pattern found by
[`find_patterns()`](https://tylerjssmith.github.io/pkgaudit/reference/find_patterns.md)
the code context it would execute in.

## Usage

``` r
determine_code_contexts(tree, patterns, rules)
```

## Arguments

- tree:

  The `xml_document` parse tree for one script (from
  [`parse_script()`](https://tylerjssmith.github.io/pkgaudit/reference/parse_script.md)).

- patterns:

  Data frame from
  [`find_patterns()`](https://tylerjssmith.github.io/pkgaudit/reference/find_patterns.md),
  carrying its matched nodes in the `"nodes"` attribute aligned to the
  rows.

- rules:

  Loaded rules; only `rules$code_contexts` (columns `name`, `xpath`) is
  used.

## Value

`patterns` with an added `code_context` column (a named context,
`"Top-level"`, or `"Other"`; never `NA`). The `"nodes"` attribute is
dropped from the result.

## Details

Named contexts are defined by `rules$code_contexts`: a pattern occurs in
a named context iff its node is a descendant of that context's node.
When a pattern sits inside more than one named context, the
most-specific (innermost) one wins.

`"Top-level"` and `"Other"` are not rule-matched; they are computed here
as fallbacks for a pattern in no named context. `"Top-level"` is
assigned when the pattern has no function-definition ancestor; `"Other"`
when it has one.

Containment is tested by exact XML path identity, never by path-prefix
comparison (sibling paths such as `expr[1]` and `expr[12]` would
false-match).
