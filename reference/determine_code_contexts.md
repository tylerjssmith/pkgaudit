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
  [`parse_code()`](https://tylerjssmith.github.io/pkgaudit/reference/parse_code.md)).

- patterns:

  Data frame from
  [`find_patterns()`](https://tylerjssmith.github.io/pkgaudit/reference/find_patterns.md),
  carrying its matched nodes in the `"nodes"` attribute aligned to the
  rows.

- rules:

  Loaded rules; only `rules$code_contexts` (columns `name`, `xpath`) is
  used.

## Value

`patterns` with an added `code_context` column – a named context,
`"top_level"` or `"in_function"`, never `NA`. The `"nodes"` attribute is
dropped from the result.

## Details

A pattern occurs in a named context iff its node is a descendant of that
context's node; where it sits inside more than one, the innermost wins.
Containment is tested by exact XML path identity, never by path-prefix
comparison, since sibling paths such as `expr[1]` and `expr[12]` would
false-match.

`"top_level"` and `"in_function"` are not rule-matched. They are
computed here for a pattern in no named context: `"in_function"` when it
has a function-definition ancestor, `"top_level"` when it does not.
