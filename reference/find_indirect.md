# Find calls made through a function's name

Finds `do.call("system", ...)` and its siblings: a call to a function
named by a string literal, which no pattern rule's XPath can see because
the target is not a call site.

## Usage

``` r
find_indirect(tree, pattern_rules, file_context)
```

## Arguments

- tree:

  The `xml_document` parse tree for one segment (from
  [`parse_code()`](https://tylerjssmith.github.io/pkgaudit/reference/parse_code.md)).

- pattern_rules:

  Data frame of pattern rules (`rules$patterns` from
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)).
  Only the `functions` column decides what is found; the matched rule
  supplies the row's `rule`, `message`, and `attck`.

- file_context:

  Package-root-relative path, carried through for joining.

## Value

A list with two data frames, shaped exactly as
[`find_patterns()`](https://tylerjssmith.github.io/pkgaudit/reference/find_patterns.md)
returns them so the two can be combined:

- patterns:

  The columns
  [`find_patterns()`](https://tylerjssmith.github.io/pkgaudit/reference/find_patterns.md)
  produces, plus `indirect`, which is `TRUE` on every row. Carries the
  matched nodes as a `"nodes"` attribute, aligned to the rows.

- errors:

  Data frame with columns `step`, `file_context`, `rule`, `message`.

## Details

A finding is reported under the rule that owns the name, not under a
rule of its own, so filtering for `rule == "system"` returns every call
to `system` however it was spelled, and the `indirect` column says which
is which. The line and column point at the string literal rather than at
`do.call`, since the literal is what a reviewer needs to look at.

## Security considerations

A name is claimed by a rule only if calling it bare would have matched
that rule's own XPath, which `inst/scripts/build_db.R` verifies when the
database is built. An indirect finding therefore can never be attributed
to a rule that would not have reported the direct call.

A name the rules do not declare is not reported, so this under-covers
rather than guesses – as does a target assembled at runtime, such as
`do.call(paste0("sys", "tem"), ...)`, which carries no literal to read.
