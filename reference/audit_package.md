# Audit an R source package

Finds security-relevant file and code contexts and code patterns for
review before an R source package is trusted.

## Usage

``` r
audit_package(path = ".", rules = load_rules(), .origin = NULL)
```

## Arguments

- path:

  Path to an R source package root directory. Defaults to the current
  directory.

- rules:

  Named list of rules. Defaults to the rules bundled with the package as
  returned by
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md).

- .origin:

  Internal. Used by
  [`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
  to record tarball provenance. Leave `NULL` for a directory scan.

## Value

A
[`new_pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/new_pkgaudit.md)
object: a named list with class `pkgaudit` containing four data frames
and a `metadata` list.

- file_contexts:

  `rule`, `file_context`, `message`, and the phase columns.

- code_contexts:

  `rule`, `file_context`, `line_number`, `column_number`, `message`, and
  the phase columns. Join to `file_contexts` on `file_context`.

- patterns:

  `rule`, `file_context`, `line_number`, `column_number`, `message`,
  `attck`, `code_context`, and the phase columns. Join to the other
  tables on `file_context`, and to `code_contexts$rule` on
  `code_context`.

- errors:

  `stage`, `file_context`, `rule`, `message`.

- metadata:

  List of `pkg_name`, `pkg_version`, `pkg_path`, `pkg_is_tarball`,
  `pkg_sha256`, `pkgaudit_version`, `pkgaudit_rules_version`,
  `pkgaudit_rules_sha256`, and `scanned`. The two rules fields describe
  the database `rules` was read from, and are `NA` for a rules list that
  did not come from
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md).

The phase columns are the nine described under Details.

## Details

Recoverable failures in the orchestrated finders are collected in the
`errors` data frame rather than aborting the audit. File paths in every
returned data frame are relative to the package root.

Each findings data frame also carries one logical column per package
lifecycle phase – `at_autoconf`, `at_build`, `at_check`,
`at_install_src`, `at_install_bin`, `on_load`, `on_attach`, `on_unload`,
and `on_detach` – which is `TRUE` when that finding's code runs during
the phase, so findings can be filtered by when they execute. A file or
code context takes its phases from the rule that matched; a pattern
inherits them from its `code_context`. A pattern in an ordinary function
is `FALSE` for every phase: it runs only if something calls it. A
finding can belong to several phases, so the phase columns do not
partition the rows.

When called by
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md),
`.origin` is a list with `path`, `sha256`, and `is_tarball`, which are
used for the `metadata` list. When calling `audit_package()` on a
package directory directly, leave `NULL`, in which case the directory is
hashed with
[`hash_manifest()`](https://tylerjssmith.github.io/pkgaudit/reference/hash_manifest.md).

## Examples

``` r
if (FALSE) { # \dontrun{
rules  <- load_rules()
result <- audit_package("/path/to/somepackage", rules = rules)
result$file_contexts
result$patterns
print(result)
} # }
```
