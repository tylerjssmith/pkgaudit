# Find security-relevant file contexts in a package

Finds file contexts – files in an R package that can be executed by
`R CMD build`, `R CMD check`, or `R CMD INSTALL` (e.g., `configure`,
`src/Makevars`, `src/install.libs.R`).

## Usage

``` r
find_file_contexts(pkg, file_context_rules)
```

## Arguments

- pkg:

  Path to the root of the package being audited. Must exist and be a
  directory.

- file_context_rules:

  Data frame of file-context rules (`rules$file_contexts` from
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)),
  with columns `name`, `path`, `recursive`, `filename`, and `message`.

## Value

A list with two data frames:

- file_contexts:

  Data frame with columns `rule` (the matching rule's name),
  `file_context` (package-root-relative path; the join key), and
  `message`. The phase columns are not set here;
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
  attaches them from the rules database.

- errors:

  Data frame with columns `step`, `file_context`, `rule`, `message`.

## Security considerations

A rule whose directory is absent contributes nothing and reports nothing
– most packages have no `R/unix/`, and that is a clean result. `pkg`
itself is checked so that a root that does not exist is refused rather
than joining that silence as a package with nothing to scan.
