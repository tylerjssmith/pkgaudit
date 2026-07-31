# Format or print a pkgaudit result

`format.pkgaudit()` renders the scan metadata and finding counts as a
character vector of lines; `print.pkgaudit()` writes those lines and
returns the object invisibly.

## Usage

``` r
# S3 method for class 'pkgaudit'
format(x, path = TRUE, ...)

# S3 method for class 'pkgaudit'
print(x, path = TRUE, ...)
```

## Arguments

- x:

  A `pkgaudit` object.

- path:

  Logical; if `TRUE` (default) include the `Path:` line showing the
  local filesystem location scanned. Set `FALSE` to omit local paths.

- ...:

  Ignored, for S3 compatibility.

## Value

`format.pkgaudit()` returns a character vector of lines.
`print.pkgaudit()` returns `x` invisibly.

## See also

[`summary.pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/summary.pkgaudit.md)
for a sectioned report of the findings themselves rather than their
counts.

## Examples

``` r
if (FALSE) { # \dontrun{
result <- audit_package("/path/to/package")
print(result)
print(result, path = FALSE)   # omit the local Path: line for sharing
} # }
```
