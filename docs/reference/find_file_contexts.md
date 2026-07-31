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

  Path to the root of the package being audited.

- file_context_rules:

  Data frame of file-context rules (`rules$file_contexts` from
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)),
  with columns `name`, `path`, `recursive`, `pattern`, and `message`.

## Value

A list with two data frames:

- file_contexts:

  Data frame with columns `rule` (the matching rule's name),
  `file_context` (package-root-relative path; the join key), and
  `message`. The phase columns are not set here;
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
  attaches them from the rules database.

- errors:

  Data frame with columns `stage`, `file_context`, `rule`, `message`.
