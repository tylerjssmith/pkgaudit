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
* Inline R in an `.Rmd` or `.qmd` -- `` `r system("id")` ``, and Quarto's
  `` `{r} system("id")` `` -- is now read. It runs when the vignette is
  rendered, at `R CMD build` and again under `R CMD check`, and was previously
  skipped without being reported as skipped. Findings carry the line and column
  the expression occupies in the source. The same rewrite fixed the Sweave
  extractor, which read only the first `\Sexpr{}` on a line.
* Quarto chunk options are honoured: a chunk suppressed with `#| eval: false`
  is marked `guarded`, as one marked `eval=FALSE` in its header already was.
  A document-wide `execute: eval: false` is still not read.
* The two axes of dispatch are exported, so a file format or a language can be
  added from another package rather than only by editing this one:
  `extract_segments()` and `analyze_segment()`, with `new_segment()` and
  `new_findings()` to build what a method returns.
* The four entry points report a bad argument by naming it. Passing a path that
  does not exist now says ``` `path` is not an existing directory ``` rather
  than `dir.exists(path) is not TRUE`.
* Extraction and analysis dispatch on two independent axes: a file's *type*
  decides how it is read, a segment's *language* decides how it is analysed.
  Adding a file format and adding a language are now separate, additive
  changes.
* Rules reach parity across R and shell, and the rule set roughly doubles:
  decoding, interpreters, software installation, sockets, credential files,
  and persistence via startup files are now caught in both.
* A finding's phases are resolved from both the file context it sits in and the
  code context within that file, rather than from one flattened namespace.
  `patterns$code_context` now reports only where code sits inside its file:
  `top_level`, `in_function`, a lifecycle hook, or a part of a help file. The
  contexts named for locations -- `data`, `demo`, `exec`, `tests`, `tools`,
  `citation`, `Rprofile`, `vignettes` -- are gone, since `file_context` already
  says where the file sits. `R` and `Other` are renamed `top_level` and
  `in_function`; `Other` always meant code inside a function definition, and now
  says so.
* Code inside a function definition inherits the phases of the code around it,
  except under `R/`. A helper called by a test file reports `at_check` instead
  of nothing, which is an under-report this release fixes: findings move out of
  `"none"` and never into it.
* `Rd_examples` and the three `Rd_Sexpr_*` contexts are rules rather than
  constants in the package, matched on a label the extractor stamps rather than
  on an XPath. Every context a finding can carry is now defined by a rule, with
  its own version, message and examples.
* A file-context rule names the code-context rules that can apply inside it,
  replacing the `namespace_source` flag, and carries `assume_called`: whether
  code inside a function definition there is taken to run when the code around
  it runs. There are exactly two measured answers, so it is a flag rather than a
  set of phases -- a rule can choose between the two measurements but cannot
  state a third.
* Every phase pkgaudit reports is measured by an instrumented probe package,
  including both readings of a function body: one called from top-level code,
  which fires wherever that code does, and one nothing calls, which fires
  nowhere. A rule that overrides `in_function` is choosing between two
  measurements rather than asserting something unmeasured. The probe now covers
  `tests/testthat/`, `inst/tinytest/` and `inst/unitTests/`, which previously
  rested on inference from plain `tests/`, and confirms that a `.onLoad`
  defined outside `R/` never fires. It also measures the Rd example wrappers,
  which is why only `\dontrun{}` is reported as `guarded`: `\dontshow{}` and
  `\testonly{}` run under any example run, and `\donttest{}` runs under
  `R CMD check --as-cran`.
* Indirect calls are attributed to the rule that owns the name, so
  `do.call("system", ...)` reports as a `system` finding.
* Four vignettes, one audience each: getting started, R package security,
  rule coverage, and internals -- the last with a call graph derived from
  pkgaudit's own parse trees, so it cannot fall behind the code.
* Every documented function's examples run, against `untrustedpkg`, the small
  package pkgaudit ships to be scanned. Nothing is held back behind
  `\dontrun{}`, so `R CMD check` exercises the documentation.
* The `Path:` line in `print()` and `summary()` output writes the home
  directory as `~`, so a report can be shared without disclosing a username
  while still saying which copy was scanned. `path = FALSE` still omits the
  line.
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
