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

  A `pkgaudit_segment` from `new_segment()`.

- rules:

  Named list of rules as returned by
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md).

## Value

A list of `patterns`, `matches`, `coverage` and `errors` data frames,
each with the columns
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
documents, less the phase columns.

## Method contract

A method must build its return value with `.findings()`, which holds
every analyser to the same frame shape.
[`UseMethod()`](https://rdrr.io/r/base/UseMethod.html) ends the generic,
so this cannot be enforced after dispatch.
