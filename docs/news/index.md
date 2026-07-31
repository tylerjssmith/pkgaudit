# Changelog

## pkgaudit 0.3.0

This is a major redesign of pkgaudit. The previous model matched
specific function calls inside lifecycle hooks
(e.g. [`system()`](https://rdrr.io/r/base/system.html) in `.onLoad()`);
0.3.0 replaces it with three independent rule categories.

### Rule model

- **File contexts** are files that R executes during build, check, or
  install.
- **Code contexts** are lifecycle hooks whose bodies run automatically
  when a namespace is loaded, attached, unloaded, or detached.
- **Patterns** are security-relevant function calls. Each pattern
  finding is attributed to the code context it executes in, so a
  [`system()`](https://rdrr.io/r/base/system.html) call inside `.onLoad`
  is distinguished from one inside an ordinary function (`Other`) or at
  top level (`Top-level`).

### Results and metadata

- [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
  and
  [`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
  now return a `pkgaudit` S3 object: a named list of `file_contexts`,
  `code_contexts`, `patterns`, and `errors` data frames plus a
  `metadata` list, with [`format()`](https://rdrr.io/r/base/format.html)
  and [`print()`](https://rdrr.io/r/base/print.html) methods.
- Every findings data frame names the rule that produced the row in a
  `rule` column, and identifies the file in a `file_context` column
  holding the package-root-relative path. `file_contexts` previously
  carried the path twice, as `file_context` and `file_path`, and did not
  record the rule; the `code_context` and `pattern` columns that named a
  rule are now `rule`. In `patterns`, `code_context` keeps its name and
  its meaning: the code context the pattern executes in, which is a
  `code_contexts$rule` value or one of the computed contexts `Top-level`
  and `Other`.
- [`summary()`](https://rdrr.io/r/base/summary.html) on a `pkgaudit`
  object returns a `summary.pkgaudit` object and prints a sectioned
  report of the findings themselves: the findings counted by the
  lifecycle phase they execute in, the distinct file and code contexts
  found, how often each pattern was found and the MITRE ATT&CK
  techniques it carries, and any errors, each followed by a note stating
  what scan coverage the failure cost. Like
  [`print()`](https://rdrr.io/r/base/print.html), it takes
  `path = FALSE` to omit local paths from shared output.

### Lifecycle phases

- Every findings data frame carries one logical column per package
  lifecycle phase – `at_autoconf`, `at_build`, `at_check`,
  `at_install_src`, `at_install_bin`, `on_load`, `on_attach`,
  `on_unload`, `on_detach` – so findings can be filtered by when they
  execute, e.g. `subset(result$patterns, at_install_src)`.
- A file or code context takes its phases from the rule that matched it;
  a pattern inherits them from the code context it sits in. A pattern
  inside an ordinary function is `FALSE` for every phase: it runs only
  if something calls it. A finding can belong to several phases, so the
  columns do not partition the rows.
- [`summary()`](https://rdrr.io/r/base/summary.html) gains a “Findings
  by Phase” section counting each kind of finding per phase, with a
  trailing `none` row for findings that execute in no phase.
- The rules database gains a `phases` table with one row per context:
  every file- and code-context rule, plus the computed contexts
  `Top-level` and `Other`, which are authored in `inst/rules/phases/`.
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
  returns it as a fourth element and refuses a database that is missing
  phases for any context.
- Phase assignments were established by running `R CMD build`,
  `R CMD check`, and `R CMD INSTALL` against instrumented packages
  rather than from documentation. Notably, `cleanup` runs during
  `R CMD build` and, at install time, only under `--clean`/`--preclean`;
  `.onAttach()` runs during a plain `R CMD INSTALL`; `configure`,
  `src/Makevars`, and the load hooks all run during `R CMD build`; and
  top-level code in `R/` runs once when the lazy-load database is built,
  not when the namespace is loaded.

### Context rule corrections (rules v0.3.0)

- `src/GNUmakefile` is no longer a file context. R looks only for
  `src/Makefile` and names its makefiles explicitly with `-f`, which
  suppresses GNU make’s preference for `GNUmakefile`, so it is not used
  to compile code.

- New `cleanup.ucrt` file-context rule, which takes precedence over
  `cleanup.win`.

- `cleanup`, `cleanup.win`, and `cleanup.ucrt` messages corrected: they
  run at the end of `R CMD build`, and during installation only under
  `R CMD INSTALL --clean` or `--preclean`.

- `.Last.lib()` message now states the two conditions for it to run at
  all: the package must export it, and it must not define `.onDetach()`,
  which supersedes it.

- `.onAttach()` message no longer lists
  [`attach()`](https://rdrr.io/r/base/attach.html) as a trigger, which
  does not invoke it.

- The `configure`, `src/Makefile*`, `src/Makevars*`,
  `src/install.libs.R`, `.onLoad()`,
  [`rlang::on_load()`](https://rlang.r-lib.org/reference/on_load.html),
  and `.onAttach()` messages now say that `R CMD check` and
  `R CMD build` execute them too, not installation alone.

- `metadata` records provenance: package name and version (from
  `DESCRIPTION`), a SHA-256 (the tarball hash for tarball scans, or a
  directory manifest hash for directory scans), the pkgaudit and rules
  versions, the rules-database hash, and the scan time.

- [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)’s
  first argument is now `path` (was `pkg`), consistent with
  [`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md).

- A rule’s `type` is now the language or format of what it matches,
  everywhere. A pattern rule’s `type` was a severity (`warning` or
  `note`) and a code context rule’s was a structural kind (`hook`); both
  are now `R`, the language they are matched in. Severity is a property
  of a pattern together with the context it was found in – the same
  [`system()`](https://rdrr.io/r/base/system.html) call weighs
  differently in `.onLoad()` than in a function nothing calls – so a
  rule, evaluated without knowing its context, is not in a position to
  declare one. This puts all three categories on the axis file contexts
  already used, whose `type` remains `R`, `shell`, `make`, or `other`,
  and reserves the field for matching languages other than R.

### Pattern rule coverage (rules v0.2.0)

- Seven new pattern rules: `decoding_pattern` (base64 and
  [`memDecompress()`](https://rdrr.io/r/base/memCompress.html)),
  `deserialization_pattern`
  ([`readRDS()`](https://rdrr.io/r/base/readRDS.html),
  [`load()`](https://rdrr.io/r/base/load.html),
  [`unserialize()`](https://rdrr.io/r/base/serialize.html),
  [`dget()`](https://rdrr.io/r/base/dput.html)), `dynload_pattern`
  ([`dyn.load()`](https://rdrr.io/r/base/dynload.html),
  [`library.dynam()`](https://rdrr.io/r/base/library.dynam.html)),
  `indirection_pattern` (resolving a function from a string literal at
  runtime), `install_pattern` (installing from a specified or remote
  source), `socket_pattern` (raw network sockets), and
  `system_other_pattern` (callr, processx, and sys process execution).
- `system_pattern` also matches
  [`pipe()`](https://rdrr.io/r/base/connections.html), and now carries
  T1059.003 alongside T1059.004 because it covers the Windows `shell()`.
- `eval_parse_pattern` also matches
  [`evalq()`](https://rdrr.io/r/base/eval.html),
  [`str2lang()`](https://rdrr.io/r/base/parse.html), and
  [`str2expression()`](https://rdrr.io/r/base/parse.html), and now fires
  only when the evaluated code is produced by a decoding or
  decompression call.
- `download_file_pattern` also matches
  [`url()`](https://rdrr.io/r/base/connections.html).
- `curl_pattern` also matches `curl()`, `curl_fetch_multi()`,
  `curl_upload()`, `multi_download()`, and `send_mail()`.

### Provenance and integrity

- [`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
  selects the extracted package directory by name and warns when the
  tarball filename disagrees with the `DESCRIPTION` `Package`/`Version`
  (a mislabeled or repackaged tarball). The warning is a catchable
  `pkgaudit_provenance_mismatch` condition carrying structured fields.
- [`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
  now validates a tarball before extracting it, failing closed on link
  entries (symlink/hard link), non-standard typeflags (GNU long-name,
  PAX), path traversal, absolute/drive-qualified paths, decompression
  bombs, and archives without exactly one top-level directory. A refusal
  is a `pkgaudit_invalid_tarball` condition, so it stops for a
  single-package caller but can be caught and recorded by batch callers.
  Validation caps (`max_entries`, `max_bytes`, `max_ratio`) are exposed
  and default to values calibrated against all of CRAN.
- Rules are stored in a versioned, hash-verified SQLite database.
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
  verifies the database against its bundled SHA-256 sidecar on every
  call and refuses to load a modified database.
- [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
  records the database it read on the list it returns, as a
  `"provenance"` attribute of `db_path`, `version`, and `sha256`, and a
  scan’s `metadata` reports those. Previously `pkgaudit_rules_version`
  and `pkgaudit_rules_sha256` always described the bundled database, so
  a scan run with rules from another `db_path` reported a version and
  hash that were not the ones it used. A rules list not produced by
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
  carries no provenance and both fields are now `NA` rather than the
  bundled values.
- The recorded `sha256` is the hash computed from the database while
  verifying it, not a later re-read of the sidecar. The time-of-check to
  time-of-use window is unchanged, but a scan now reports what it
  measured: were the database and its sidecar both replaced after
  verification, the recorded hash would no longer match the file, rather
  than agreeing with it.

### New exported functions

- [`hash_manifest()`](https://tylerjssmith.github.io/pkgaudit/reference/hash_manifest.md)
  — reproducible SHA-256 manifest hash of a directory.
- [`validate_tar()`](https://tylerjssmith.github.io/pkgaudit/reference/validate_tar.md)
  — fail-closed structural validation of a source tarball before
  extraction.

### Documentation

- New vignette, “Getting Started with pkgaudit”, which scans an example
  source package end to end:
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
  and
  [`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md),
  the [`print()`](https://rdrr.io/r/base/print.html) and
  [`summary()`](https://rdrr.io/r/base/summary.html) methods, the result
  components,
  [`validate_tar()`](https://tylerjssmith.github.io/pkgaudit/reference/validate_tar.md),
  database integrity, and how to weigh a finding. The example package is
  shipped in `inst/extdata/untrustedpkg/` and generated by
  `data-raw/create_untrustedpkg.R`.
- New vignette, “How pkgaudit Works”, which explains how a scan is
  carried out and walks through one rule from each category – a file
  context, a code context, and a pattern – showing how its fields decide
  what it matches.
- New vignette, “pkgaudit Rule Coverage”, which documents the full rule
  set: every file-context, code-context, and pattern rule, with the
  file, hook, or function calls it covers and a link to its defining
  YAML. It is generated from the shipped rules database, so it cannot
  drift from the rules in force.
- New vignette, “R Package Security”, which sets out why R packages are
  an attack vector: the code R runs on install and load, a worked
  malicious `.onLoad()` hook, and comparable incidents in adjacent
  ecosystems.

### Licensing

- pkgaudit is now released under the Apache License 2.0, previously the
  MIT License. The Apache License adds an express patent grant and
  explicit terms for redistribution and contribution, which
  organizations reviewing the package before adoption commonly require.
  `LICENSE.md` carries the full license text and the MIT `LICENSE`
  template file has been removed.

### Removed

- `audit_file()` and `audit_dir()` (replaced by the context pipeline)
  and the `pkgaudit_result` class (replaced by the `pkgaudit` object).
