# Changelog

## pkgaudit (development version)

- Rules database 0.5.0. The `credentials` rule is split into
  `credentials_environment` and `credentials_files`, which flagged the
  same finding under one name and one message although a secret read out
  of the environment and a secret read off disk are different behaviors
  to review. `credentials_environment` additionally flags
  [`Sys.getenv()`](https://rdrr.io/r/base/Sys.getenv.html) called with
  no arguments, which returns every environment variable at once.
- A new `jsonlite` rule flags `fromJSON()` given a literal `http://` or
  `https://` URL, which fetches it rather than parsing it – an outbound
  connection from a function whose name says nothing about the network.
- A new `lazyload` rule flags `makeLazyLoadDB()` and the four front ends
  that reach it. They write the `.rdb`/`.rdx` files holding an installed
  package’s objects, so a call at run time can replace a benign function
  with a malicious one, or restore the benign one after the malicious
  one has run.
- On a random sample of 1,000 CRAN source packages, `jsonlite` flagged
  0.3% of them (95% CI 0.1% to 0.9%), `credentials_files` 0.1% (95% CI 0
  to 0.6%), and `credentials_environment` 3.5% (95% CI 2.5% to 4.8%).
  `lazyload` flagged none, which the sample bounds below 0.4% rather
  than establishing as zero.
- CI verifies that the rules-database version published in the README is
  the one
  [`rules_version()`](https://tylerjssmith.github.io/pkgaudit/reference/rules_version.md)
  returns, alongside the SHA-256 check it already made.

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
  Every result carries `level` `note`: pkgaudit does not rank findings,
  and when a finding’s code runs is carried in `properties.phases`.
- The `description` rule no longer claims `at_build` and `at_check`.
  Measured against R 4.6.1, `R CMD build`, `check` and `INSTALL` all
  refuse an `Authors@R` field containing anything outside `person`,
  `as.person`, `c`, `list`, `paste` and `paste0`, and the check recurses
  into arguments, so none of the seventeen expressions tried executed.
  The field is still not inert: `desc` evaluates it with no allowlist,
  so reading a package’s authors – or printing a `desc` object – runs
  whatever it holds. That is developer tooling rather than a lifecycle
  phase, so the rule now declares no phases and says why.
- The `data_serialized` rule no longer claims `.Rdata`, `.RDS` and
  `.Rds` files under `data/`. Measured against R 4.6.1, a file with one
  of those extensions is never deserialized: `R CMD INSTALL` copies it
  into the installed package untouched rather than moving it into the
  lazy-load database, no object from it is reachable once the namespace
  loads, and `R CMD check` reports it under “Files not of a type allowed
  in a ‘data’ directory”.
- Inline R in an `.Rmd` or `.qmd` – `` `r system("id")` ``, and Quarto’s
  `` `{r} system("id")` `` – is now read. It runs when the vignette is
  rendered, at `R CMD build` and again under `R CMD check`, and was
  previously skipped without being reported as skipped. Findings carry
  the line and column the expression occupies in the source. The same
  rewrite fixed the Sweave extractor, which read only the first
  `\Sexpr{}` on a line. Everywhere knitr evaluates is read: inline R in
  the YAML front matter, the `` `r#expr` `` spelling, chunks inside
  blockquotes, and Sweave chunks ended by an `@ %def x` line, which
  previously swallowed the rest of the file.
- Quarto chunk options are honoured: a chunk suppressed with
  `#| eval: false` is marked `guarded`, as one marked `eval=FALSE` in
  its header already was. A document-wide `execute: eval: false` is
  still not read.
- Extraction and analysis dispatch on two independent axes: a file’s
  *type* decides how it is read, a segment’s *language* decides how it
  is analysed. Both axes are exported –
  [`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md)
  and
  [`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md),
  with
  [`new_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/new_segment.md)
  and
  [`new_findings()`](https://tylerjssmith.github.io/pkgaudit/reference/new_findings.md)
  to build what a method returns – so a file format or a language can be
  added from another package rather than only by editing this one.
- [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md),
  [`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md),
  [`emit_sarif()`](https://tylerjssmith.github.io/pkgaudit/reference/emit_sarif.md)
  and
  [`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
  report a bad argument by naming it. Passing a path that does not exist
  now says `` `path` is not an existing directory `` rather than
  `dir.exists(path) is not TRUE`.
- Rules reach parity across R and shell, and the rule set roughly
  doubles: decoding, interpreters, software installation, sockets,
  credential files, file-permission changes –
  [`Sys.chmod()`](https://rdrr.io/r/base/files2.html),
  [`fs::file_chmod()`](https://fs.r-lib.org/reference/file_chmod.html),
  `chmod` – and persistence via startup files are now caught in both.
- A finding’s phases are resolved from both the file context it sits in
  and the code context within that file, rather than from one flattened
  namespace. `patterns$code_context` now reports only where code sits
  inside its file: `top_level`, `in_function`, a lifecycle hook, or a
  part of a help file. The contexts named for locations – `data`,
  `demo`, `exec`, `tests`, `tools`, `citation`, `Rprofile`, `vignettes`
  – are gone, since `file_context` already says where the file sits. `R`
  and `Other` are renamed `top_level` and `in_function`; `Other` always
  meant code inside a function definition, and now says so.
- Code inside a function definition inherits the phases of the code
  around it, except under `R/`. A helper called by a test file reports
  `at_check` instead of nothing, which is an under-report this release
  fixes: findings move out of `"none"` and never into it.
- `Rd_examples` and the three `Rd_Sexpr_*` contexts are rules rather
  than constants in the package, matched on a label the extractor stamps
  rather than on an XPath. Every context a finding can carry is now
  defined by a rule, with its own version, message and examples.
- A file-context rule names the code-context rules that can apply inside
  it, replacing the `namespace_source` flag, and carries
  `assume_called`: whether code inside a function definition there is
  taken to run when the code around it runs. There are exactly two
  measured answers, so it is a flag rather than a set of phases – a rule
  can choose between the two measurements but cannot state a third.
- Every phase pkgaudit reports is measured by an instrumented probe
  package, including both readings of a function body: one called from
  top-level code, which fires wherever that code does, and one nothing
  calls, which fires nowhere. A rule that overrides `in_function` is
  choosing between two measurements rather than asserting something
  unmeasured. The probe now covers `tests/testthat/`, `inst/tinytest/`
  and `inst/unitTests/`, which previously rested on inference from plain
  `tests/`, and confirms that a `.onLoad` defined outside `R/` never
  fires. It also measures the Rd example wrappers, which is why only
  `\dontrun{}` is reported as `guarded`: `\dontshow{}` and `\testonly{}`
  run under any example run, and `\donttest{}` runs under
  `R CMD check --as-cran`.
- Indirect calls are attributed to the rule that owns the name, so
  `do.call("system", ...)` reports as a `system` finding – including
  when the target is passed by name, as in
  `do.call(args = list("id"), what = "system")`.
- A symlinked file is never followed. Scanning it would attribute its
  target’s code to a path the package does not ship, so it is reported
  in `coverage` as `unexamined` with reason `symlink` instead.
  [`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
  already refused archives carrying symlinks; directory scans now state
  what they skipped.
- [`validate_tar()`](https://tylerjssmith.github.io/pkgaudit/reference/validate_tar.md)
  refuses bzip2-, xz-, zstd- and compress-compressed archives by their
  magic bytes, whatever the filename says.
  [`gzfile()`](https://rdrr.io/r/base/connections.html) would otherwise
  decompress them silently, and only gzip’s bounded expansion keeps the
  decompression-bomb ratio cap meaningful.
- Four vignettes, one audience each: getting started, R package
  security, rule coverage, and internals – the last with a call graph
  derived from pkgaudit’s own parse trees, so it cannot fall behind the
  code.
- Every documented function’s examples run, against `untrustedpkg`, the
  small package pkgaudit ships to be scanned. Nothing is held back
  behind `\dontrun{}`, so `R CMD check` exercises the documentation.
- The `Path:` line in [`print()`](https://rdrr.io/r/base/print.html) and
  [`summary()`](https://rdrr.io/r/base/summary.html) output writes the
  home directory as `~`, so a report can be shared without disclosing a
  username while still saying which copy was scanned. `path = FALSE`
  still omits the line.
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
