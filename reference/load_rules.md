# Load security rules from the pkgaudit rules database

Loads the file-context, code-context, pattern, and match rules, and the
lifecycle phases of every context, from the bundled SQLite database as a
named list suitable for passing to
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
or
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md).

## Usage

``` r
load_rules(db_path = .db_path())
```

## Arguments

- db_path:

  Path to the rules database. Defaults to the database bundled with the
  installed package.

## Value

A named list with five data frames:

- file_contexts:

  Data frame with columns `name`, `version`, `type`, `message`, `path`,
  `recursive`, `report`, `namespace_source`, `filename`, `code_context`.
  `type` selects how a matched file is read and scanned; `report` is
  `TRUE` for a rule whose matches are findings in their own right, and
  `FALSE` for one that only tells the scanner which files to read;
  `namespace_source` is `TRUE` only where R code becomes the package
  namespace, which is where a lifecycle hook can actually run.

- code_contexts:

  Data frame with columns `name`, `version`, `language`, `message`,
  `xpath`.

- patterns:

  Data frame with columns `name`, `version`, `language`, `message`,
  `attck`, `functions`, `xpath`. `functions` is the space-separated
  names the rule matches as a bare call, which is how
  [`find_indirect()`](https://tylerjssmith.github.io/pkgaudit/reference/find_indirect.md)
  attributes an indirect call back to it; it is empty for a rule that
  matches on more than the callee.

- matches:

  Data frame with columns `name`, `version`, `language`, `message`,
  `attck`, `regex`. A match rule is evaluated against every segment in
  its `language`, which is what keeps a shell rule from being applied to
  R code.

- phases:

  Data frame with columns `context`, `version`, and one logical column
  per lifecycle phase. One row per context code can execute in: every
  file- and code-context rule, plus the computed contexts `"R"` and
  `"Other"`.

The list carries a `"provenance"` attribute recording the database the
rules were read from – a list of `db_path`, `version`, and `sha256` –
which
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
reports in a scan's `metadata`. The `sha256` is the hash computed from
the database during verification, not a value re-read from the sidecar
afterwards, so it records what this call measured.

## Details

Before reading, the database is verified against its SHA-256 sidecar so
that a tampered or corrupted rules file is rejected rather than silently
trusted.

## Security considerations

Verification is time-of-check to time-of-use (TOCTOU): the database is
hashed and then re-opened by path to query it, so a file swapped in the
interval between the two is not detected. This does not weaken the
bundled default – an attacker able to win that race already has write
access to the installed package and could replace the sidecar or this
package's code outright. If loading rules from a path other parties can
write, treat the SHA-256 check as protection against accidental
corruption or a substituted database given an authentic sidecar – not
against an attacker who can modify the file concurrently. Load from a
path only trusted writers control.

## Examples

``` r
rules <- load_rules()
vapply(rules, nrow, integer(1))
#> file_contexts code_contexts      patterns       matches        phases 
#>            45             6            21            11            65 
```
