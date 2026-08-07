# pkgaudit 0.4.0

pkgaudit now looks inside the shell scripts and Make-like files it flags,
rather than only reporting that they exist, and scans the R code carried by
help files.

## Terminology

pkgaudit's vocabulary is not standard in R, so it has to be self-explanatory.
Four names collided with each other or with core R concepts and have been
changed. The first three affect rules and results released in 0.3.0.

* A rule's `type` meant two different things. On a file-context rule it names
  the **format of the file** and selects how the file is read, and it keeps that
  name. On a code-context or pattern rule it named the **language of the code**
  the rule is evaluated against, and is now **`language`**. These are separate
  axes: one file can yield code in more than one language.
* The file-context field `pattern`, a regular expression matched against file
  names, is now **`filename`**. `patterns` is also a rule category and a
  findings frame, and one word could not carry both.
* `errors$stage` is now **`errors$step`**. It names a step of the scan pipeline,
  and `stage` is about to be needed for its `\Sexpr[stage=]` sense.
* The `regex` rule category and the `expressions` findings frame are both now
  **`matches`**. `expression` collides with a core R concept -- `expression()`,
  `parse()`, `eval()` -- while naming the one frame that contains no R at all,
  and `regex` was the only category named for its mechanism rather than its
  result. `find_regex()` is now `find_matches()`.

## Extraction and analysis dispatch on two axes

* Reading a file and analysing what comes out are now S3 generics.
  `extract_segments()` dispatches on the file-context rule's `type`;
  `analyze_segment()` dispatches on the language of the code that came out.
  These are separate axes because one file can yield code in more than one
  language, so a single class cannot carry both decisions.
* Methods live one script per type -- `R/type_R.R`, `R/type_Rd.R`,
  `R/type_shell.R` -- so a new variety of file is a new script plus a rule, with
  no edit to `audit_package()`. A type read exactly like another inherits from
  it: `make` inherits `shell` rather than repeating a method.
* A *stream* is now a **segment**: a contiguous, line-aligned run of code in one
  language. `.read_streams()` and `.analyze_stream()` are gone.
* Both defaults fail closed. A type with no reader yields no segment, which is
  how `other` is reported but never read; a language with no analyser yields no
  findings and no error, so an unhandled chunk engine is a segment nothing
  matches rather than a forgotten branch.
* The scanning size limit now runs in `extract_segments()` before it dispatches,
  so no reader can be written that skips it.
* An analyser returns `.findings()`, which holds every method to the same frame
  shape. `rbind()` accepts a frame with an extra column without complaint, so an
  unconformed frame would corrupt the accumulated result silently.

## Coverage: where else a package carries code

* New file contexts for `data/`, `demo/`, `tests/`, `tests/testthat/`,
  `inst/tinytest/`, `tools/`, `inst/CITATION`, `exec/`, `.Rprofile`, and
  vignettes in `.Rmd`, `.qmd` and `.Rnw`. All are non-recursive: testthat does
  not source subdirectories, and a `tests/testthat/fixtures/` corpus of
  deliberately suspicious code is not an execution surface.
* Each carries a computed code context of its own -- `data_R`, `demo_R`,
  `test_R`, `tools_R`, `citation_R`, `rprofile_R`, `vignette` -- because
  `Top-level`'s phases are correct for `R/` and wrong everywhere else. A
  file-context rule names the context its top-level code belongs to, in a new
  **`code_context`** field. Every one of these phase profiles was measured with
  an instrumented probe package rather than read off the manual.
* Notably: `data/*.R` is evaluated at build and when installing from a source
  *directory*, and does not survive into a tarball -- build replaces it with the
  `.rda` it produced. `demo/` and `tools/` run at no lifecycle phase at all.
  `inst/CITATION` runs under `R CMD check`, while a plain `.R` file under
  `inst/` is never sourced.
* File-context rules carry a **`namespace_source`** field, `TRUE` only for `R/`,
  `R/unix/` and `R/windows/`. The named code-context rules are applied only
  there. A `.onLoad` defined in, say, `data/` ships as an ordinary lazy-data
  object of class function and is never called, so reporting it as
  `onLoad_base` -- with `at_load` set -- was a false attribution rather than a
  cautious one.
* Vignette chunks are extracted without filtering on engine: a `bash` chunk is a
  shell segment and is matched as one, and an engine with no analyser yields a
  segment nothing matches rather than being silently dropped.

## Rd stages, and code that ships without running

* `Rd_Sexpr` becomes three contexts -- **`Rd_Sexpr_build`**,
  **`Rd_Sexpr_install`** and **`Rd_Sexpr_render`** -- because the stages do not
  share a phase profile. `stage=render` runs at neither install; `stage=build`
  does not run when a tarball is installed, its result having been frozen into
  the Rd at build time. An unlabelled `\Sexpr` measured identically to
  `stage=install`, which is what Writing R Extensions documents.
* `patterns` gains a logical **`guarded`** column: `TRUE` for code inside
  `\dontrun{}` or `\donttest{}`, and for a vignette chunk marked
  `eval=FALSE`. `\dontshow{}` and `\testonly{}` are *not* guarded -- check
  runs them, and `\dontshow{}` in particular runs without appearing on the
  rendered page.
* Guarded code keeps its context and its phases, which therefore read as an
  upper bound. A different phase profile earns a context; suppression of an
  otherwise-known profile is an attribute.

## Guidance when an Rd macro cannot be expanded

* An unexpandable Rd macro is now reported as what it is. It was described as a
  help file that "could not be read in full", which is wrong: the file was read,
  and only the code the macro produces is missing. The `extract_Rd_code` note
  now distinguishes an unexpandable macro from a file `parse_Rd()` only warned
  about.
* Where the macro comes from a package pkgaudit recognises, the note names it:
  "installing Rdpack would recover it". Covers Rdpack, mathjaxr, lifecycle and
  details, which between them account for 590 of the 24,216 packages on CRAN
  that declare `RdMacros`. Every one of their macros expands to a `\Sexpr`
  carrying a real call, so an unexpanded macro hides code that runs at build or
  render time rather than merely producing a warning.
* The provider is looked up by **macro name** against a fixed list, never taken
  from the audited package's `RdMacros` field. That field is chosen by the
  package under audit; echoing it would let a hostile package have pkgaudit
  advise the analyst to install something of its choosing. An unrecognised macro
  is still counted as lost coverage, just without a suggestion.

## R.rsp vignettes

* New `rsp` file context and extractor for `vignettes/*.rsp`. An R.rsp vignette
  is a template where everything is output except the R between `<%` and `%>`;
  `<%= %>` writes a value out, `<%: %>` echoes one, `<%@ %>` is a directive,
  `<%% %>` an escaped delimiter and `<%-- --%>` a comment. Phases are the
  vignette context's: build and check.
* Extraction blanks the surrounding template rather than removing it, so a
  finding's line and column point straight into the `.rsp` file even where a
  region spans lines.

## Provenance is validated before a scan runs

* `audit_package()` checks its `.origin` argument up front, alongside `path` and
  `rules`. It becomes the scan's provenance, and two failure modes made that
  worth doing.
* `is_tarball` was read through `isTRUE()`, so a missing, `NA` or misspelled
  value became `FALSE` rather than an error: the result was a valid object whose
  metadata claimed a directory scan while carrying a tarball's path and hash. A
  provenance record that contradicts itself is worse than a refused one.
* A malformed `.origin` otherwise surfaced at `new_pkgaudit()` as a complaint
  about `metadata$pkg_path`, after every file had been read -- naming the wrong
  thing, minutes after the mistake.
* An `NA` `path` or `sha256` is still accepted: hashing can fail and the scan
  records what it could. `is_tarball` may not be `NA`, being a claim about what
  was scanned rather than a measurement that might be unavailable.

## `report` has a stated criterion

* `report: TRUE` now means one thing, and it is checkable: the file executes
  automatically during at least one lifecycle phase, **and** its contents are
  matched as text rather than parsed. Together those say pkgaudit cannot tell a
  reviewer what the file does, only that it runs -- so the file itself is the
  finding. In practice that is `configure`, `cleanup`, `src/Makevars` and their
  variants.
* The new file contexts added in this release -- `data/`, `demo/`, `tests/`,
  `vignettes/` and the rest -- therefore do **not** report. Nothing about them
  is scanned any less: a pattern in a vignette or a test file is reported with
  its context and phases either way. Only the row asserting the file exists is
  withheld, and for a parsed file the findings already say what is there.
* Without this, `file_contexts` stopped being a short list. Across 400 CRAN
  packages it had grown to 2390 rows, 91% of them from `tests/testthat/`,
  `tests/`, `vignettes/*.Rmd` and `inst/CITATION` alone; it is now 91 rows.
* `src/install.libs.R` is the one exception, and reports despite being parsed:
  its presence replaces R's default handling of compiled artifacts, a
  structural change that follows from the file existing rather than from
  anything written in it.
* A test asserts the field against both conditions, so it cannot drift as rules
  are added.
* Related fix: a match's phases are now resolved against every file context
  found, not just the reported ones. `report` decides what a reviewer is shown
  and says nothing about when a file runs, so an unreported shell context used
  to give its matches no phases at all -- a finding that silently claimed to run
  nowhere.

## exec/ is split by language

* `exec_scripts` becomes `exec_scripts_R` (parsed) and `exec_scripts_shell`
  (matched). Surveying the 33 CRAN packages that ship `exec/` found 90 files, of
  which **49 are R by extension and 6 more are Rscript by shebang** -- so typing
  the whole directory as `shell` meant roughly 60% of it was matched with two
  regexes instead of parsed against eighteen pattern rules. A `system()` or
  `eval(parse())` in an `exec/` R script was invisible.
* The shell rule claims `.sh`, `.bash`, `.ksh`, `.zsh` and `.csh` explicitly
  rather than every filename. `exec/` also holds Perl, Python, batch, PHP, JS
  and Tcl files, and extensionless scripts whose language is known only from a
  shebang. Those are **not scanned**: a language pkgaudit cannot read is better
  left to a tool that can than matched badly, and their absence from the
  findings is not evidence that they are clean.
* R under `exec/` gets a computed context of its own, `exec_R`, with every phase
  FALSE. `Top-level` would have conferred build, check and install-from-source
  phases on code that no lifecycle command runs.

## summary() takes a phase

* `summary()` gains a `phase` argument: a character vector of lifecycle phases,
  or `"none"` for occurrences that execute in no phase. `summary(result, phase =
  "at_load")` is what runs when the package is loaded.
* This is the only place the report can be narrowed. A summary is expanded by
  phase before it is returned -- an occurrence contributes one row per phase it
  runs in -- so it cannot be subset afterwards.
* The default reports every phase. A filtered report names its phases in the
  header, beside `Package:` and `SHA-256:`, so it cannot be read as a full scan
  of a package whose findings are simply in a phase nobody asked for.
* An unrecognised phase is an error rather than an empty report.

## Help files

* `man/*.Rd` is scanned for patterns. A help file carries R code in two places,
  and they run at different times, so each is a computed code context of its
  own: **`Rd_examples`** for `\examples{}`, which `R CMD check` runs, and
  **`Rd_Sexpr`** for `\Sexpr{}` macros, which are evaluated whenever the page is
  rendered.
* Those phases were established by running an instrumented package through each
  lifecycle command. `\examples{}` runs only under `R CMD check`. `\Sexpr{}`
  runs during `R CMD build`, installation from source, and `R CMD check`, but
  not on installation from a binary package, whose help ships pre-rendered.
* `\dontrun{}`, `\donttest{}`, `\dontshow{}`, and `\testonly{}` are all
  unwrapped and scanned. Whether the code is reached is a question for the
  reviewer; all four ship in the package.
* A pattern inside a function definition in an example is `Other`, not
  `Rd_examples` -- it runs only if something calls it, exactly as in a script.
* User-defined Rd macros are expanded, so a `\Sexpr{}` reaching a page through a
  macro is found and reported against the page that uses it. `man/macros/` is
  not scanned directly: `tools::parse_Rd()` returns a `\newcommand` body as an
  opaque token, so there is nothing to find there until the macro is expanded.

## Findings carry a preview

* `patterns` and `matches` gain a **`preview`** column: a one-line,
  display-only excerpt of the source each finding sits on, so the frames can be
  skimmed without opening the files. A `download_file` finding now shows whether
  it fetches a caller-supplied `url` or a hardcoded address.
* The preview is the line at `line_number`, not the matched span. Most pattern
  rules match a bare function name, so the span would only repeat `rule`, while
  the arguments that decide whether a finding matters are on the line around it.
* A line too long to show whole is windowed on the match rather than cut off at
  its start, so what matched stays visible. Whitespace is collapsed and a
  trailing `...` means there is more to see. `column_number` does not index into
  the preview.
* A preview from a help file comes from the extracted code rather than the `.Rd`
  text, so a `\Sexpr{}` finding previews the macro's code alone and is not a
  substring of the line it is numbered on.

## Uniform file discovery

* Every file the scan reads is now found by a file-context rule. `find_scripts()`
  is gone, replaced by rules for `R/`, `R/unix/`, and `R/windows/`; new rules
  cover `man/`, `man/unix/`, and `man/windows/`.
* File-context rules carry a **`report`** field separating discovery from
  reporting. Rules for `R/` and `man/` exist to tell the scan what to read and do
  not report, so `file_contexts` remains the short list of security-relevant
  files it has always been rather than an inventory of the package.
* A rule's `type` now selects how a matched file is read: `R` is parsed as it
  stands, `Rd` has its code extracted first, `shell` and `make` are matched line
  by line, and `other` is reported but never read.

## Internals

* `parse_script()` is now `parse_code()` and takes lines rather than a path, so
  one parser serves R scripts and the code extracted from help files alike. The
  corresponding `errors$step` value is `"parse_code"`.
* New `read_code()` reads every file context except help files, which
  `extract_Rd_code()` reads instead. The 10 MB size limit applies to both, so it
  now covers every file type rather than only shell and Make-like files;
  invalid-UTF-8 handling applies to what `read_code()` returns. `find_matches()`
  takes lines.
* New `extract_Rd_code()` recovers the `\examples{}` and `\Sexpr{}` code from a
  help file as text aligned to the lines of the `.Rd`, so a finding's
  `line_number` points into the original file with no adjustment.

## Security considerations

* pkgaudit does not execute the code it scans, and a regression test now asserts
  it end to end: a package whose every execution site would create a marker file
  leaves no marker behind after a full scan. R's Rd machinery separates parsing
  from rendering -- `tools::parse_Rd()` and `tools::loadPkgRdMacros()` only read,
  while `tools::prepare_Rd()` and the `Rd2*()` family evaluate `\Sexpr{}` as a
  matter of course. pkgaudit calls only the former.
* The `examples` code is not guaranteed to parse. R never syntax-checks
  `\dontrun{}`, so packages ship blocks that are not valid R; those are recorded
  as `parse_code` errors like any other unparseable file.

## Match rules

* A fourth rule category, **matches**, evaluates regular expressions against
  the text of the file contexts whose type is `shell` or `make` (e.g.
  `configure`, `src/Makevars`). Rules live in `inst/rules/matches/` and carry
  `language` and `regex` keys alongside the `name`, `version`, `message`,
  `attck`, and example keys the other categories use.
* A match rule is evaluated against every segment in its `language`, which is
  what keeps a shell rule from ever being applied to R code.
* Initial rules for `curl` and `wget`, each labelled `T1041` and `T1105`.
* Findings are called **matches**, not patterns. Matching text is less precise
  than matching a parse tree: a match has no syntax behind it, so one inside a
  comment, a quoted string, or a branch that never runs is reported the same as
  a live command.
* `load_rules()` returns a fifth data frame, `matches`. The rules database
  gains a `matches` table.

## Results

* `audit_package()` and `audit_tarball()` return a fifth data frame,
  `matches`, with `rule`, `file_context`, `line_number`, `column_number`,
  `message`, `attck`, and the phase columns. It mirrors `patterns`, but carries
  no `code_context`: a shell script or Make-like file has no R parse tree, so a
  match inherits its phases from the file context it was found in. Where a
  file matches more than one file-context rule, its phases are the union of
  theirs.
* `print()` reports a `Matches:` count alongside the others.
* `summary()` returns a fourth summary data frame, `matches`, counting each
  match rule by the phase and file context it executes in.

## Reports

* The `summary()` report is now three sections: `R Patterns` (formerly
  `Patterns`), `Shell / Make Matches`, and `Errors`. The `Contexts` section
  has been removed; `summary()` still returns the `file_contexts` and
  `code_contexts` summaries for programmatic use.
* An error from the match scan is reported like any other, with a note
  stating what coverage was lost. A file that could not be read and a rule that
  could not be evaluated are counted separately, so a file that was never opened
  is not reported as a rule that failed.

## Security considerations

* A file above 10 MB is not read, and lines that are not valid UTF-8 are
  excluded from matching. Both are recorded as errors so the summary reports the
  lost coverage rather than a clean scan of a file that was never fully
  examined. Excluding a line does not shift the line numbers reported after it.
* `build_db.R` refuses a regex that does not compile under PCRE, and one that
  matches the empty string: such an expression matches at every position of
  every line, so a single rule would bury a scan in findings.


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
