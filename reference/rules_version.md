# Return the current rules database version

Returns the version string of the rules database currently shipped with
the package. Findings reports should always record the rules version to
ensure reproducibility across audit cycles.

## Usage

``` r
rules_version(db_path = .db_path())
```

## Arguments

- db_path:

  Path to the SQLite rules database. Defaults to the database bundled
  with the installed package.

## Value

A character string giving the rules database version (e.g., `"0.1.0"`).

## Details

Like
[`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md),
this verifies the database against its SHA-256 sidecar before reading;
see its Security considerations.

## Examples

``` r
if (FALSE) { # \dontrun{
rules_version()
} # }
```
