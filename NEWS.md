# pkgaudit 0.3.0

This is a major redesign of pkgaudit. The previous model matched specific
function calls inside lifecycle hooks (e.g. `system()` in `.onLoad()`); 0.3.0
replaces it with three independent rule categories.

## Rule model

* **File contexts** are files that R executes during build, check, or install.
* **Code contexts** are lifecycle hooks whose bodies run automatically when a namespace is loaded, attached, unloaded, or detached.
* **Patterns** are security-relevant function calls. Each pattern finding is attributed to the code context it executes in, so a `system()` call inside `.onLoad` is distinguished from one inside an ordinary function (`Other`) or at top level (`Top-level`).

* A rule's `name` does not repeat its category, which is already known from
  where the rule lives: `configure`, `onLoad_base`, `system`. The YAML file
  names carry the category as a `file_`, `code_`, `pattern_`, or `phase_`
  prefix. A code context is named for the hook it matches and the package that
  defines it, following their own capitalization and separators
  (`onLoad_base`, `on_load_rlang`); a pattern covering one package's functions
  carries that package's name (`system_callr`), so a finding points at the
  calls behind it.
* Pattern rules carry no `T1195.002` ATT&CK label, which would have applied to
  every rule and so distinguished none of them. It remains on `options_repos`,
  where redirecting the package repository is the technique itself.

## Results and metadata

* `audit_package()` and `audit_tarball()` now return a `pkgaudit` S3 object: a
  named list of `file_contexts`, `code_contexts`, `patterns`, and `errors` data
  frames plus a `metadata` list, with `format()` and `print()` methods.
* Every findings data frame names the rule that produced the row in a `rule`
  column, and identifies the file in a `file_context` column holding the
  package-root-relative path. `file_contexts` previously carried the path twice,
  as `file_context` and `file_path`, and did not record the rule; the
  `code_context` and `pattern` columns that named a rule are now `rule`. In
  `patterns`, `code_context` keeps its name and its meaning: the code context
  the pattern executes in, which is a `code_contexts$rule` value or one of the
  computed contexts `Top-level` and `Other`.
* `summary()` on a `pkgaudit` object returns a `summary.pkgaudit` object and
  prints a sectioned report of the findings themselves: the distinct file and
  code contexts found, how often each pattern was found in each context and
  lifecycle phase along with the MITRE ATT&CK techniques it carries, and any
  errors, each followed by a note stating what scan coverage the failure cost.
  Like `print()`, it takes `path = FALSE` to omit local paths from shared
  output.
* Both reports are 77 characters wide, so output prefixed with `#> ` in a
  knitted document still fits in 80 columns.

## Lifecycle phases

* Every findings data frame carries one logical column per package lifecycle
  phase -- `at_autoconf`, `at_build`, `at_check`, `at_install_src`,
  `at_install_bin`, `at_load`, `at_attach`, `at_unload`, `at_detach` -- so
  findings can be filtered by when they execute, e.g.
  `subset(result$patterns, at_install_src)`. Every phase is prefixed `at_`, so a
  phase is not mistaken for a code context of a similar name.
* A file or code context takes its phases from the rule that matched it; a
  pattern inherits them from the code context it sits in. A pattern inside an
  ordinary function is `FALSE` for every phase: it runs only if something calls
  it. A finding can belong to several phases, so the columns do not partition
  the rows.
* `summary()` counts patterns by the phase and code context they execute in. An
  occurrence is counted once per phase, and one that executes in no phase at all
  is gathered under `none`.
* The rules database gains a `phases` table with one row per context: every
  file- and code-context rule, plus the computed contexts `Top-level` and
  `Other`, which are authored in `inst/rules/phases/`. `load_rules()` returns it
  as a fourth element and refuses a database that is missing phases for any
  context.
* Phase assignments were established by running `R CMD build`, `R CMD check`,
  and `R CMD INSTALL` against instrumented packages rather than from
  documentation. Notably, `cleanup` runs during `R CMD build` and, at install
  time, only under `--clean`/`--preclean`; `.onAttach()` runs during a plain
  `R CMD INSTALL`; `configure`, `src/Makevars`, and the load hooks all run
  during `R CMD build`; and top-level code in `R/` runs once when the lazy-load
  database is built, not when the namespace is loaded.

## Context rule corrections (rules v0.3.0)

* `src/GNUmakefile` is no longer a file context. R looks only for
  `src/Makefile` and names its makefiles explicitly with `-f`, which suppresses
  GNU make's preference for `GNUmakefile`, so it is not used to compile code.
* New `cleanup.ucrt` file-context rule, which takes precedence over
  `cleanup.win`.
* `cleanup`, `cleanup.win`, and `cleanup.ucrt` messages corrected: they run at
  the end of `R CMD build`, and during installation only under
  `R CMD INSTALL --clean` or `--preclean`.
* `.Last.lib()` message now states the two conditions for it to run at all: the
  package must export it, and it must not define `.onDetach()`, which supersedes
  it.
* `.onAttach()` message no longer lists `attach()` as a trigger, which does not
  invoke it.
* The `configure`, `src/Makefile*`, `src/Makevars*`, `src/install.libs.R`,
  `.onLoad()`, `rlang::on_load()`, and `.onAttach()` messages now say that
  `R CMD check` and `R CMD build` execute them too, not installation alone.
* `metadata` records provenance: package name and version (from `DESCRIPTION`),
  a SHA-256 (the tarball hash for tarball scans, or a directory manifest hash
  for directory scans), the pkgaudit and rules versions, the rules-database
  hash, and the scan time.
* `audit_package()`'s first argument is now `path` (was `pkg`), consistent with
  `audit_tarball()`.

* A rule's `type` is now the language or format of what it matches, everywhere.
  A pattern rule's `type` was a severity (`warning` or `note`) and a code
  context rule's was a structural kind (`hook`); both are now `R`, the language
  they are matched in. Severity is a property of a pattern together with the
  context it was found in -- the same `system()` call weighs differently in
  `.onLoad()` than in a function nothing calls -- so a rule, evaluated without
  knowing its context, is not in a position to declare one. This puts all three
  categories on the axis file contexts already used, whose `type` remains `R`,
  `shell`, `make`, or `other`, and reserves the field for matching languages
  other than R.

## Pattern rule coverage (rules v0.2.0)

* New pattern rules: `decoding` (base64 and `memDecompress()`),
  `deserialization` (`readRDS()`, `load()`, `unserialize()`, `dget()`),
  `dynload` (`dyn.load()`, `library.dynam()`), `indirection` (resolving a
  function from a string literal at runtime), `install` (installing from a
  specified or remote source), `socket` (raw network sockets), and
  `system_callr`, `system_processx`, and `system_sys` (callr, processx, and sys
  process execution).
* `system` also matches `pipe()`, and now carries T1059.003 alongside
  T1059.004 because it covers the Windows `shell()`.
* `eval_parse` also matches `evalq()`, `str2lang()`, and `str2expression()`,
  and now fires only when the evaluated code is produced by a decoding or
  decompression call.
* `download_file` also matches `url()`.
* `curl` also matches `curl()`, `curl_fetch_multi()`, `curl_upload()`,
  `multi_download()`, and `send_mail()`.

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
* `load_rules()` records the database it read on the list it returns, as a
  `"provenance"` attribute of `db_path`, `version`, and `sha256`, and a scan's
  `metadata` reports those. Previously `pkgaudit_rules_version` and
  `pkgaudit_rules_sha256` always described the bundled database, so a scan run
  with rules from another `db_path` reported a version and hash that were not
  the ones it used. A rules list not produced by `load_rules()` carries no
  provenance and both fields are now `NA` rather than the bundled values.
* The recorded `sha256` is the hash computed from the database while verifying
  it, not a later re-read of the sidecar. The time-of-check to time-of-use
  window is unchanged, but a scan now reports what it measured: were the
  database and its sidecar both replaced after verification, the recorded hash
  would no longer match the file, rather than agreeing with it.

## New exported functions

* `hash_manifest()` — reproducible SHA-256 manifest hash of a directory.
* `validate_tar()` — fail-closed structural validation of a source tarball
  before extraction.

## Documentation

* New vignette, "Getting Started with pkgaudit", which scans an example source
  package end to end: `audit_package()` and `audit_tarball()`, the `print()` and
  `summary()` methods, the result components, `validate_tar()`, database
  integrity, and how to weigh a finding. The example package is shipped in
  `inst/extdata/untrustedpkg/` and generated by `data-raw/create_untrustedpkg.R`.
* New vignette, "How pkgaudit Works", which explains how a scan is carried
  out and walks through one rule from each category -- a file context, a code
  context, and a pattern -- showing how its fields decide what it matches.
* New vignette, "pkgaudit Rule Coverage", which documents the full rule set:
  every file-context, code-context, and pattern rule, with the file, hook, or
  function calls it covers and a link to its defining YAML. It is generated from
  the shipped rules database, so it cannot drift from the rules in force.
* New vignette, "R Package Security", which sets out why R packages are an
  attack vector: the code R runs on install and load, a worked malicious
  `.onLoad()` hook, and comparable incidents in adjacent ecosystems.

## Licensing

* pkgaudit is now released under the Apache License 2.0, previously the MIT
  License. The Apache License adds an express patent grant and explicit terms
  for redistribution and contribution, which organizations reviewing the package
  before adoption commonly require. `LICENSE.md` carries the full license text
  and the MIT `LICENSE` template file has been removed.

## Removed

* `audit_file()` and `audit_dir()` (replaced by the context pipeline) and the
  `pkgaudit_result` class (replaced by the `pkgaudit` object).
