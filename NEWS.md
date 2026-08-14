# pkgaudit 0.5.0

## Breaking changes

* A finding's phases are now resolved from **both** the file context it sits in
  and the code context within that file, rather than from one flattened
  namespace. `patterns$code_context` therefore reports only where code sits
  inside its file: `top_level`, `in_function`, a lifecycle hook, or a part of a
  help file. The contexts named for locations -- `data`, `demo`, `exec`,
  `tests`, `tools`, `citation`, `Rprofile`, `vignettes` -- are gone; the same
  information is in `file_context`, and the phases they conferred are unchanged.
* `R` and `Other` are renamed `top_level` and `in_function`. `Other` was never
  only "other": it meant code inside a function definition, and now says so.
* Code inside a function definition no longer reports as running at no phase
  everywhere. It inherits the phases of the code around it, except under `R/`.
  A helper called by a test file now reports `at_check` instead of nothing,
  which is the under-report this release fixes. Findings move out of `"none"`
  and never into it.
* `load_rules()` returns a sixth element, `phase_overrides`, and
  `file_contexts` no longer carries `namespace_source` -- a file-context rule
  now names the code-context rules that can apply inside it, which is both more
  precise and one fewer field.

## Rules

* Rule set 0.5.0. `Rd_examples` and the three `Rd_Sexpr_*` contexts are now
  rules with their own versions, messages and examples, matched on a label the
  extractor stamps rather than hardcoded in the package. Every context a
  finding can carry is now defined by a rule.

## Evidence

* Every phase pkgaudit reports is measured by the `execution_surface` probe
  package, including the two readings of a function body: one called from
  top-level code, which fires wherever that code does, and one nothing calls,
  which fires nowhere. A rule that overrides `in_function` is choosing between
  two measurements rather than asserting something unmeasured.
* The probe now covers `tests/testthat/`, `inst/tinytest/` and
  `inst/unitTests/`, which previously rested on inference from plain `tests/`.
  All three run at check and nowhere else. It also measures that a `.onLoad`
  defined outside `R/` never fires, which is what confines the hook rules to
  the directories whose code becomes the namespace.

# pkgaudit 0.4.0

* pkgaudit now accounts for every file it can identify as code, in a new
  `coverage` frame, and says what it made of each one: `parsed`, `matched`,
  `exportable`, `unexamined`, or `error`. A clean scan can be checked rather
  than trusted, because the scan states what it did not read.
* `export_unscanned()` writes the code pkgaudit cannot read -- C, C++, Fortran,
  Rust, Python, JavaScript -- into a directory a scanner such as Semgrep can be
  pointed at, blank-padded so line numbers still point into the original file.
* `emit_sarif()` renders a result as SARIF 2.1.0, so findings open on the line
  they were found in any editor or code-scanning platform that reads it.
* Extraction and analysis dispatch on two independent axes: a file's *type*
  decides how it is read, a segment's *language* decides how it is analysed.
  Adding a file format and adding a language are now separate, additive
  changes.
* Rules reach parity across R and shell, and the rule set roughly doubles:
  decoding, interpreters, software installation, sockets, credential files,
  and persistence via startup files are now caught in both.
* Indirect calls are attributed to the rule that owns the name, so
  `do.call("system", ...)` reports as a `system` finding.
* Four vignettes, one audience each: getting started, R package security,
  rule coverage, and internals -- the last with a call graph derived from
  pkgaudit's own parse trees, so it cannot fall behind the code.
* Every documented function's examples run, against `untrustedpkg`, the small
  package pkgaudit ships to be scanned. Nothing is held back behind
  `\dontrun{}`, so `R CMD check` exercises the documentation.
* Testing follows a stated principle rather than a coverage target: every
  documented function has a happy path, every `stop()`, `warning()` and
  handler is reached by a test, and anything reading untrusted bytes or
  writing to disk is tested adversarially. The principle is in
  `CONTRIBUTING.md`.

# pkgaudit 0.3.0

A redesign. 0.2.0 matched specific function calls inside lifecycle hooks;
0.3.0 replaced that with independent rule categories that compose.

* Rules split into **file contexts** (files R executes during build, check or
  install), **code contexts** (where R code runs), and **patterns**
  (security-relevant calls), so a capability and the moment it runs are
  described separately rather than enumerated as pairs.
* Every finding carries the **lifecycle phases** it runs in -- `at_build`,
  `at_install_src`, `at_load` and their kin -- which is what distinguishes code
  that executes on `library()` from code that runs only when someone calls it.
* `audit_package()` and `audit_tarball()` return a `pkgaudit` object: ordinary
  data frames plus scan metadata, with `print()` and `summary()` methods.
* The rules ship in a SQLite database verified against a SHA-256 sidecar on
  every load, and `validate_tar()` and `hash_manifest()` establish provenance
  before a scan runs.
* Relicensed under Apache 2.0.

# pkgaudit 0.2.0

* First working scanner: `audit_package()` and `audit_tarball()` over a
  YAML-authored, database-backed rule set.
