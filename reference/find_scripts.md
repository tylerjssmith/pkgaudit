# Find R scripts executed at install/load time

Returns the R source files that R evaluates when a source package is
installed or its namespace is loaded: the top level of `R/`, `R/unix/`,
and `R/windows/`, plus `src/install.libs.R` when present. Subdirectories
of `R/` other than `unix/` and `windows/` are not processed by R and are
excluded.

## Usage

``` r
find_scripts(pkg)
```

## Arguments

- pkg:

  Path to the root of the package being audited.

## Value

A character vector of absolute paths to R scripts. Empty if none.

## Details

The [`list.files()`](https://rdrr.io/r/base/list.files.html) calls are
intentionally not wrapped in
[`tryCatch()`](https://rdrr.io/r/base/conditions.html): a failure to
list the package's own directories is unrecoverable, so it propagates
and aborts the audit (see
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)).
