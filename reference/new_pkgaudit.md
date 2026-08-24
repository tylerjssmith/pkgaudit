# Construct a pkgaudit object

Assembles the five result data frames and a metadata list into a
validated `pkgaudit` S3 object.
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
calls this at the end of a scan.

## Usage

``` r
new_pkgaudit(file_contexts, patterns, matches, coverage, errors, metadata)
```

## Arguments

- file_contexts, patterns, matches, coverage, errors:

  Data frames with the columns documented in
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md).

- metadata:

  Named list with the fields documented in
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md),
  each a length-one value of the expected type.

## Value

A `pkgaudit` object: a named list of `file_contexts`, `patterns`,
`matches`, `coverage`, `errors`, and `metadata`.
