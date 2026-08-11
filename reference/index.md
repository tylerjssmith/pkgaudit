# Package index

## Scanning a package

The entry points. Both return a pkgaudit object: what was found, and
what the scan made of every file it could identify as code.

- [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
  : Audit an R source package
- [`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
  : Audit an R source package tarball

## Reading a result

- [`format(`*`<pkgaudit>`*`)`](https://tylerjssmith.github.io/pkgaudit/reference/format.pkgaudit.md)
  [`print(`*`<pkgaudit>`*`)`](https://tylerjssmith.github.io/pkgaudit/reference/format.pkgaudit.md)
  : Format or print a pkgaudit result
- [`summary(`*`<pkgaudit>`*`)`](https://tylerjssmith.github.io/pkgaudit/reference/summary.pkgaudit.md)
  [`print(`*`<summary.pkgaudit>`*`)`](https://tylerjssmith.github.io/pkgaudit/reference/summary.pkgaudit.md)
  : Summarize a pkgaudit result

## Carrying a result to another tool

R is parsed and shell is matched as text; everything else is handed on.

- [`emit_sarif()`](https://tylerjssmith.github.io/pkgaudit/reference/emit_sarif.md)
  : Render a scan as SARIF
- [`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
  : Export the code pkgaudit could not read

## Rules

The rules are data, not code, and ship in a hash-verified database.

- [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
  : Load security rules from the pkgaudit rules database
- [`rules_version()`](https://tylerjssmith.github.io/pkgaudit/reference/rules_version.md)
  : Return the current rules database version

## Provenance

- [`hash_manifest()`](https://tylerjssmith.github.io/pkgaudit/reference/hash_manifest.md)
  : Compute a manifest hash for a directory
- [`validate_tar()`](https://tylerjssmith.github.io/pkgaudit/reference/validate_tar.md)
  : Validate a source package tarball before extraction
