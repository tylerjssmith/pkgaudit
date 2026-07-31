# Construct a pkgaudit object

Assembles the four result data frames and a metadata list into a
validated `pkgaudit` S3 object.
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
calls this at the end of a scan. It is also used to construct objects
directly (e.g., in tests).

## Usage

``` r
new_pkgaudit(file_contexts, code_contexts, patterns, errors, metadata)
```

## Arguments

- file_contexts, code_contexts, patterns, errors:

  Data frames with the columns documented in
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md).

- metadata:

  Named list with the fields documented in
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md),
  each a length-one value of the expected type.

## Value

A `pkgaudit` object: a named list of `file_contexts`, `code_contexts`,
`patterns`, `errors`, and `metadata`.
