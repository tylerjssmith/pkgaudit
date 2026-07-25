# pkgaudit 0.3.0

This is a major redesign of pkgaudit. The previous model matched specific
function calls inside lifecycle hooks (e.g. `system()` in `.onLoad()`); 0.3.0
replaces it with three independent rule classes.

## Rule model

* **File contexts** are files that R executes during build, check, or install.
* **Code contexts** are top-level code and lifecycle hooks whose bodies run automatically when a namespace is loaded, attached, unloaded, or detached.
* **Patterns** are security-relevant function calls. Each pattern finding is attributed to the code context it executes in, so a `system()` call inside `.onLoad` is distinguished from one inside an ordinary function (`Other`) or at top level (`Top-level`).

## Results and metadata

* `audit_package()` and `audit_tarball()` now return a `pkgaudit` S3 object: a
  named list of `file_contexts`, `code_contexts`, `patterns`, and `errors` data
  frames plus a `metadata` list, with `format()` and `print()` methods.
* `metadata` records provenance: package name and version (from `DESCRIPTION`),
  a SHA-256 (the tarball hash for tarball scans, or a directory manifest hash
  for directory scans), the pkgaudit and rules versions, the rules-database
  hash, and the scan time.
* `audit_package()`'s first argument is now `path` (was `pkg`), consistent with
  `audit_tarball()`.

## Provenance and integrity

* `audit_tarball()` selects the extracted package directory by name and warns
  when the tarball filename disagrees with the `DESCRIPTION` `Package`/`Version`
  (a mislabeled or repackaged tarball). The warning is a catchable
  `pkgaudit_provenance_mismatch` condition carrying structured fields.
* `audit_tarball()` now validates a tarball before extracting it, failing closed
  on link entries (symlink/hard link), non-standard typeflags (GNU long-name,
  PAX), path traversal, absolute/drive-qualified paths, decompression bombs, and
  archives without exactly one top-level directory. A refusal is a
  `pkgaudit_invalid_tarball` condition, so it stops for a single-package caller
  but can be caught and recorded by batch callers. Validation caps
  (`max_entries`, `max_bytes`, `max_ratio`) are exposed and default to values
  calibrated against all of CRAN.
* Rules are stored in a versioned, hash-verified SQLite database. `load_rules()`
  verifies the database against its bundled SHA-256 sidecar on every call and
  refuses to load a modified database.

## New exported functions

* `hash_manifest()` — reproducible SHA-256 manifest hash of a directory.
* `validate_tar()` — fail-closed structural validation of a source tarball
  before extraction.

## Removed

* `audit_file()` and `audit_dir()` (replaced by the context pipeline) and the
  `pkgaudit_result` class (replaced by the `pkgaudit` object).
