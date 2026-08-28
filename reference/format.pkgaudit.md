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
  local filesystem location scanned, with the home directory written as
  `~`. Set `FALSE` to omit the line.

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
# untrustedpkg is a small package shipped with pkgaudit to be scanned.
tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)
result <- audit_tarball(tarball)

print(result)
#> --- pkgaudit ----------------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> Path:      ~/work/_temp/Library/pkgaudit/extdata/untrustedpkg/untrustedpkg_0.1.0.tar.gz
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-28 02:27 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> File contexts:  1
#> Patterns:       4
#> Matches:        1
#> Errors:         0
print(result, path = FALSE)   # omit the local Path: line for sharing
#> --- pkgaudit ----------------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-28 02:27 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> File contexts:  1
#> Patterns:       4
#> Matches:        1
#> Errors:         0
```
