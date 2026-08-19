# Build the return value of an [`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md) method

Each frame is reduced to its canonical columns and an omitted one is
empty. [`rbind()`](https://rdrr.io/r/base/cbind.html) accepts a stray
column silently, so conforming here is what keeps a malformed frame out
of the result.

## Usage

``` r
new_findings(
  patterns = NULL,
  matches = NULL,
  coverage = NULL,
  errors = .empty_errors()
)
```

## Arguments

- patterns, matches, coverage:

  Data frames with the columns
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
  documents, less the phase columns, or `NULL` for none. Extra columns
  are dropped; the phases are resolved later, from context.

- errors:

  Data frame with columns `step`, `file_context`, `rule` and `message`.

## Value

A list of the four frames, each conformed to its canonical columns.

## See also

[`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md),
whose methods return this.

## Examples

``` r
# An analyser that found nothing still returns all four frames.
str(new_findings(), max.level = 1)
#> List of 4
#>  $ patterns:'data.frame':    0 obs. of  12 variables:
#>  $ matches :'data.frame':    0 obs. of  7 variables:
#>  $ coverage:'data.frame':    0 obs. of  9 variables:
#>  $ errors  :'data.frame':    0 obs. of  4 variables:
```
