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

A named list of five data frames. In the four rule frames each row is a
rule, the common columns are `name` and `version`, and `message` is what
a finding reports; `phases` is keyed by `context` instead.

- file_contexts:

  `name`, `version`, `type`, `message`, `path`, `recursive`, `report`,
  `filename`, `code_context`, `assume_called`. `type` selects how a
  matched file is read. `report` is `TRUE` for a rule whose matches are
  findings in their own right. `code_context` names the code-context
  rules that can apply inside these files, space-separated – `NA` where
  none can, `"computed"` where only `top_level` and `in_function` can.
  `assume_called` says whether code inside a function definition is
  taken to run when the code around it runs, and is `NA` wherever
  `code_context` is.

- code_contexts:

  `name`, `version`, `language`, `message`, `kind`, `xpath`, `segment`.
  `kind` is `"xpath"` for a rule matched against the parse tree and
  `"segment"` for one matched against a label the extractor stamped;
  exactly one of the two columns is set accordingly.

- patterns:

  `name`, `version`, `language`, `message`, `attck`, `functions`,
  `xpath`. `functions` is the space-separated names the rule matches as
  a bare call, which is how
  [`find_indirect()`](https://tylerjssmith.github.io/pkgaudit/reference/find_indirect.md)
  attributes an indirect call back to it; empty for a rule matching on
  more than the callee.

- matches:

  `name`, `version`, `language`, `message`, `attck`, `regex`. A match
  rule is evaluated only against code in its `language`.

- phases:

  `context`, `version`, and one logical column per lifecycle phase. One
  row per file-context or code-context rule – pattern and match rules
  carry no phases of their own. The computed contexts `top_level` and
  `in_function` have none, and need none: they inherit.

The list carries a `"provenance"` attribute – `db_path`, `version` and
`sha256` – which
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
reports in a scan's `metadata`. The `sha256` is the hash computed during
verification, not re-read from the sidecar afterwards, so it records
what this call measured.

## Details

Before reading, the database is verified against its SHA-256 sidecar so
that a tampered or corrupted rules file is rejected rather than silently
trusted.

## Security considerations

The sidecar ships beside the database, so anyone who can rewrite one can
rewrite the other. It is an integrity check, not an authenticity check:
it catches a corrupted download or a database swapped for another, and
it cannot catch a deliberate edit of an installed copy. The out-of-band
anchor is the hash published in the README, which CI compares against
the shipped database on every push and pull request; checking an
installed copy against that detects a tampered install, and
[`rules_version()`](https://tylerjssmith.github.io/pkgaudit/reference/rules_version.md)
reports what a scan actually used.

Verification is time-of-check to time-of-use: the database is hashed and
then re-opened by path to query it, so a file swapped in between is not
detected. That does not weaken the bundled default, since an attacker
able to win the race already has write access to the installed package.
When loading rules from a path other parties can write, treat the check
as protection against corruption or a substituted database given an
authentic sidecar, not against an attacker modifying the file
concurrently.

## Examples

``` r
rules <- load_rules()
vapply(rules, nrow, integer(1))
#> file_contexts code_contexts      patterns       matches        phases 
#>            45            10            23            11            55 
```
