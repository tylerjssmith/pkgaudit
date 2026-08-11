# Changelog

## pkgaudit 0.4.0

- pkgaudit now accounts for every file it can identify as code, in a new
  `coverage` frame, and says what it made of each one: `parsed`,
  `matched`, `exportable`, `unexamined`, or `error`. A clean scan can be
  checked rather than trusted, because the scan states what it did not
  read.
- [`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
  writes the code pkgaudit cannot read – C, C++, Fortran, Rust, Python,
  JavaScript – into a directory a scanner such as Semgrep can be pointed
  at, blank-padded so line numbers still point into the original file.
- [`emit_sarif()`](https://tylerjssmith.github.io/pkgaudit/reference/emit_sarif.md)
  renders a result as SARIF 2.1.0, so findings open on the line they
  were found in any editor or code-scanning platform that reads it.
- Extraction and analysis dispatch on two independent axes: a file’s
  *type* decides how it is read, a segment’s *language* decides how it
  is analysed. Adding a file format and adding a language are now
  separate, additive changes.
- Rules reach parity across R and shell, and the rule set roughly
  doubles: decoding, interpreters, software installation, sockets,
  credential files, and persistence via startup files are now caught in
  both.
- Indirect calls are attributed to the rule that owns the name, so
  `do.call("system", ...)` reports as a `system` finding.
- Four vignettes, one audience each: getting started, R package
  security, rule coverage, and internals – the last with a call graph
  derived from pkgaudit’s own parse trees, so it cannot fall behind the
  code.
- Every documented function’s examples run, against `untrustedpkg`, the
  small package pkgaudit ships to be scanned. Nothing is held back
  behind `\dontrun{}`, so `R CMD check` exercises the documentation.
- Testing follows a stated principle rather than a coverage target:
  every documented function has a happy path, every
  [`stop()`](https://rdrr.io/r/base/stop.html),
  [`warning()`](https://rdrr.io/r/base/warning.html) and handler is
  reached by a test, and anything reading untrusted bytes or writing to
  disk is tested adversarially. The principle is in `CONTRIBUTING.md`.

## pkgaudit 0.3.0

A redesign. 0.2.0 matched specific function calls inside lifecycle
hooks; 0.3.0 replaced that with independent rule categories that
compose.

- Rules split into **file contexts** (files R executes during build,
  check or install), **code contexts** (where R code runs), and
  **patterns** (security-relevant calls), so a capability and the moment
  it runs are described separately rather than enumerated as pairs.
- Every finding carries the **lifecycle phases** it runs in –
  `at_build`, `at_install_src`, `at_load` and their kin – which is what
  distinguishes code that executes on
  [`library()`](https://rdrr.io/r/base/library.html) from code that runs
  only when someone calls it.
- [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
  and
  [`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
  return a `pkgaudit` object: ordinary data frames plus scan metadata,
  with [`print()`](https://rdrr.io/r/base/print.html) and
  [`summary()`](https://rdrr.io/r/base/summary.html) methods.
- The rules ship in a SQLite database verified against a SHA-256 sidecar
  on every load, and
  [`validate_tar()`](https://tylerjssmith.github.io/pkgaudit/reference/validate_tar.md)
  and
  [`hash_manifest()`](https://tylerjssmith.github.io/pkgaudit/reference/hash_manifest.md)
  establish provenance before a scan runs.
- Relicensed under Apache 2.0.

## pkgaudit 0.2.0

- First working scanner:
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
  and
  [`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
  over a YAML-authored, database-backed rule set.
