# pkgaudit 0.3.0

This is a major redesign of pkgaudit. The previous model matched specific
function calls inside lifecycle hooks (e.g. `system()` in `.onLoad()`); 0.3.0
replaces it with three independent rule classes and organizes findings by where
in the package lifecycle code can run.

## Rule model

* **File contexts** — files R itself executes at build, check, or install
  (e.g. `configure`, `src/Makevars`, `src/install.libs.R`).
* **Code contexts** — top-level code and lifecycle hooks (`.onLoad`,
  `.onAttach`, `.onUnload`, `.onDetach`, `.Last.lib`, `rlang::on_load`) whose
  bodies run on install from source or namespace load/attach/unload/detach.
* **Patterns** — security-relevant calls (`system()`/`system2()`/`shell()`,
  `eval(parse())`, `source()`, `download.file()`, `options(repos=)`, and
  outbound HTTP via `curl`, `httr`, `httr2`, `RCurl`), each attributed to the
  code context it executes in (a named hook, `Top-level`, or `Other`). This
  means, for example, that all `system()` calls can be seen but stratified by
  those in specific hooks, in top-level code, or in ordinary functions.

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
* Rules are stored in a versioned, hash-verified SQLite database. `load_rules()`
  verifies the database against its bundled SHA-256 sidecar on every call and
  refuses to load a modified database.

## New exported functions

* `hash_manifest()` — reproducible SHA-256 manifest hash of a directory.
* `new_pkgaudit()` — constructor and validator for `pkgaudit` objects.

## Removed

* `audit_file()` and `audit_dir()` (replaced by the context pipeline) and the
  `pkgaudit_result` class (replaced by the `pkgaudit` object).
