# Package index

## Scanning a package

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

- [`emit_sarif()`](https://tylerjssmith.github.io/pkgaudit/reference/emit_sarif.md)
  : Render a scan as SARIF
- [`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
  : Export the code pkgaudit could not read

## Rules

- [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
  : Load security rules from the pkgaudit rules database
- [`rules_version()`](https://tylerjssmith.github.io/pkgaudit/reference/rules_version.md)
  : Return the current rules database version

## Provenance

- [`hash_manifest()`](https://tylerjssmith.github.io/pkgaudit/reference/hash_manifest.md)
  : Compute a manifest hash for a directory
- [`validate_tar()`](https://tylerjssmith.github.io/pkgaudit/reference/validate_tar.md)
  : Validate a source package tarball before extraction

## Extending pkgaudit

See
[CONTRIBUTING.md](https://tylerjssmith.github.io/pkgaudit/CONTRIBUTING.md).

- [`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md)
  : Read one source file into the code segments it contains

- [`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md)
  : Find code contexts, patterns and matches in one segment

- [`new_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/new_segment.md)
  : Build one code segment

- [`new_findings()`](https://tylerjssmith.github.io/pkgaudit/reference/new_findings.md)
  :

  Build the return value of an
  [`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md)
  method
