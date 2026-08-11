# pkgaudit Internals

This vignette is for someone reading pkgaudit’s source before trusting
it. It describes how a scan works, states the invariants the design
rests on, and says where in the source each one is enforced, so that the
claims can be checked rather than taken on trust.

For what pkgaudit reports, see [Getting
Started](https://tylerjssmith.github.io/pkgaudit/articles/pkgaudit.md);
for the rule set, see [Rule
Coverage](https://tylerjssmith.github.io/pkgaudit/articles/rules.md).
pkgaudit’s own security model and its vulnerability reporting policy are
in
[SECURITY.md](https://github.com/tylerjssmith/pkgaudit/blob/master/.github/SECURITY.md).

## A scan in four movements

[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
reads top to bottom as a sequence of named concerns. It names no file
format and no language: those are decided by dispatch.

1.  **Discover.**
    [`find_file_contexts()`](https://tylerjssmith.github.io/pkgaudit/reference/find_file_contexts.md)
    runs one [`list.files()`](https://rdrr.io/r/base/list.files.html)
    per file-context rule, using the rule’s `path`, `filename` and
    `recursive` fields. Every rule tells the scan which files to read;
    only a rule with `report = TRUE` contributes a row to
    `file_contexts`.
2.  **Extract.**
    [`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md)
    reads each file into *segments*: contiguous runs of code in one
    language, blank-padded to the length of the source so that line *n*
    of a segment is line *n* of the file. That padding is why a
    finding’s line and column point into the original file with no
    offset to apply.
3.  **Analyse.**
    [`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md)
    finds code contexts, patterns and matches in each segment.
4.  **Resolve.** Lifecycle phases are attached once, at the end, from
    `rules$phases`.

The findings frames are built **without** phase columns throughout and
joined once in step 4. Nothing before it knows about phases.

## Two axes of dispatch

Steps 2 and 3 are both S3 generics, and they dispatch on different
things.

- [`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md)
  dispatches on the file-context rule’s **`type`** – how the file is
  read. Methods live one per file in `R/type_*.R`.
- [`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md)
  dispatches on the segment’s **`language`** – how the code is analysed.
  Methods live in `R/language_*.R`.

They cannot be one axis, because one file can yield code in more than
one language: an `.Rmd` yields an R segment for each `{r}` chunk and a
shell segment for each `{bash}` chunk. An `.Rd` yields several segments
that are all R.

A type read exactly like another inherits from it rather than repeating
a method: `make` inherits `shell`, and `qmd` inherits `Rmd`.

Both defaults fail closed. A type with no reader yields no segments; a
language with no analyser yields no findings and no error, and records a
coverage row instead, so an unhandled chunk engine is accounted for
rather than silently dropped.

Adding a file format is one new `R/type_*.R` plus a rule. Adding a
language is one new `R/language_*.R` plus rules carrying that language.
Neither touches
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md),
and neither touches the other.

## The call graph

The graph below is derived from pkgaudit’s own source, by parsing it
with the same parser the scan uses. It is not maintained by hand and
cannot fall behind the code.

    audit_package()
    ├─ .validate_origin()
    ├─ .empty_patterns()
    │  └─ .empty_phase_cols()
    ├─ .empty_matches()
    │  └─ .empty_phase_cols()
    ├─ .empty_coverage()
    │  └─ .empty_phase_cols()
    ├─ .empty_errors()
    ├─ find_file_contexts()
    │  ├─ .empty_file_contexts()
    │  │  └─ .empty_phase_cols()
    │  ├─ .error_row()
    │  └─ .relativize()
    ├─ .reported_contexts()
    ├─ .load_rd_macros()
    ├─ .scan_targets()
    │  └─ isTRUE_vec()
    ├─ new_source()
    │  └─ .source_class()
    ├─ extract_segments()
    │  ├─ .over_scan_limit()
    │  ├─ .error_row()
    │  ├─ extract_segments.default()
    │  ├─ extract_segments.R()
    │  │  ├─ read_code()
    │  │  └─ new_segment()
    │  ├─ extract_segments.Rd()
    │  │  ├─ extract_Rd_code()
    │  │  │  ├─ .empty_Rd_code()
    │  │  │  ├─ .parse_Rd_safe()
    │  │  │  └─ .Rd_fragments()
    │  │  └─ new_segment()
    │  ├─ extract_segments.Rmd()
    │  │  ├─ read_code()
    │  │  ├─ .rmd_chunks()
    │  │  │  └─ .rmd_header()
    │  │  ├─ new_segment()
    │  │  └─ .blank_except()
    │  ├─ extract_segments.Rnw()
    │  │  ├─ read_code()
    │  │  ├─ .rnw_code()
    │  │  ├─ new_segment()
    │  │  └─ .blank_except()
    │  ├─ extract_segments.rsp()
    │  │  ├─ read_code()
    │  │  ├─ .rsp_code()
    │  │  │  └─ .fixed_positions()
    │  │  └─ new_segment()
    │  └─ extract_segments.shell()
    │     ├─ read_code()
    │     └─ new_segment()
    ├─ analyze_segment()
    │  ├─ analyze_segment.R()
    │  │  ├─ parse_code()
    │  │  ├─ .findings()
    │  │  ├─ .error_row()
    │  │  ├─ find_code_contexts()
    │  │  │  ├─ .empty_code_contexts()
    │  │  │  └─ .xml_find_all_safe()
    │  │  ├─ find_patterns()
    │  │  │  └─ .xml_find_all_safe()
    │  │  ├─ find_indirect()
    │  │  │  ├─ .empty_indirect()
    │  │  │  ├─ .function_owners()
    │  │  │  ├─ .xml_find_all_safe()
    │  │  │  └─ .string_value()
    │  │  ├─ .preview()
    │  │  ├─ .node_continues()
    │  │  └─ determine_code_contexts()
    │  │     ├─ .xml_find_all_safe()
    │  │     ├─ .deepest_context()
    │  │     └─ .has_function_ancestor()
    │  ├─ analyze_segment.shell()
    │  │  ├─ find_matches()
    │  │  │  ├─ .gregexpr_safe()
    │  │  │  └─ .error_row()
    │  │  ├─ .rules_for()
    │  │  ├─ .preview()
    │  │  └─ .findings()
    │  └─ analyze_segment.default()
    │     ├─ .findings()
    │     └─ .segment_coverage()
    ├─ .merge_coverage()
    ├─ build_coverage()
    │  ├─ .claiming_rule()
    │  ├─ .in_scope()
    │  ├─ .file_extension()
    │  ├─ .error_reason()
    │  ├─ .segment_language()
    │  └─ .coverage_lines()
    ├─ .attach_phases()
    │  └─ .phase_lookup()
    │     └─ .empty_phase_cols()
    ├─ .resolve_pattern_phases()
    │  └─ .phase_lookup()
    │     └─ .empty_phase_cols()
    ├─ .resolve_match_phases()
    │  └─ .empty_phase_cols()
    ├─ hash_manifest()
    ├─ .build_metadata()
    │  ├─ .read_description()
    │  ├─ .rules_provenance()
    │  └─ .pkgaudit_version()
    └─ new_pkgaudit()
       ├─ .validate_result_df()
       └─ .validate_metadata()

A name appears once, at the first place it is reached; a function called
from several places is not repeated. The tree is cut at four levels
deep.

## Invariants

Each of these is a property a contributor could otherwise break, and
each is asserted by a test rather than left to review.

### Nothing that is scanned is ever executed

This is not a property any single function can be inspected for. R’s own
help machinery will evaluate `\Sexpr` if asked, and
`tools::prepare_Rd()`, `Rd2HTML()` and their kin do exactly that. It is
therefore asserted end to end: `tests/testthat/test-no_execution.R`
builds a package whose every execution site writes a marker file, scans
it, exports it, and requires that no marker exists afterwards.

Three calls in the read path look like execution and are not.
[`tools::parse_Rd()`](https://rdrr.io/r/tools/parse_Rd.html) parses
without evaluating;
[`tools::loadPkgRdMacros()`](https://rdrr.io/r/tools/loadRdMacros.html)
reads macro definitions as text; and `parse(text = )` produces an
unevaluated expression. A macro provider is looked up by macro name
against a fixed list and never taken from the audited package’s
`RdMacros` field, which the package under audit chooses.

### The size limit runs before dispatch

[`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md)
applies the scanning limit before
[`UseMethod()`](https://rdrr.io/r/base/UseMethod.html), so no reader can
be written that skips it. A per-method guard is exactly what once let
help files bypass the limit for a whole release.

### Failures are contained, and counted

Listing files, reading a file, parsing code, and evaluating an XPath or
a regular expression are each wrapped: a failure becomes a row in
`errors` rather than aborting the scan. The `Errors` section of
[`summary()`](https://rdrr.io/r/base/summary.html) follows the table
with one note per step, stating what coverage that step’s failures cost.

A file pkgaudit tried to read and could not is `error` in the coverage
frame, which is a different claim from `unexamined`, where it never
tried. Only a failure at a *reading* step counts: a rule that fails on a
file says nothing about the file.

### The rules are data, and integrity-checked

Rules live in a SQLite database built from YAML by
`inst/scripts/build_db.R`.
[`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
verifies the database against its SHA-256 sidecar on every call. The
check is time-of-check to time-of-use; see “Security considerations” in
[`?load_rules`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md).

[`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
also refuses a database missing phases for any context a finding could
be attributed to, so a rule can never ship whose findings would silently
carry no phases.

### Every rule is verified against its own examples

Each rule carries positive and negative examples in its YAML.
`build_db.R` writes them out as fixtures, and
`tests/testthat/test-fixtures.R` requires every positive to match its
rule and every negative not to. A rule is trusted because its
documentation is executable, not because it is documented.

The same file checks two contracts that would otherwise drift. A pattern
rule’s `functions` field – the names it claims for
`do.call("name", ...)` – is accepted only if calling that name bare
would have matched the rule’s own XPath, so an indirect finding can
never be attributed to a rule that would not have reported the direct
call. And `eval_parse`’s source list is required to cover every function
the capability rules it composes declare.

## What pkgaudit does not do

- It does not execute, install, build, or load the package under audit.
- It does not resolve values. A path assembled at runtime, a name built
  by [`paste0()`](https://rdrr.io/r/base/paste.html), or a chunk option
  computed at render time is not followed.
- It does not read compiled code, or any language other than R and
  shell.
  [`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
  hands those to a tool that does.
- It does not rank findings or return a verdict. There is no severity
  model, and the `level` in SARIF output is a mapping of the phase
  model, not a judgement.
- It does not reach the network, and it writes only where a caller sends
  it.

## Examples are tests

Every example in the rule YAML is a fixture, and the rules vignette is
generated from the shipped database rather than written alongside it. A
rule that ships without a description fails the vignette build; a rule
whose examples stop matching fails the test suite. Neither can be fixed
by editing prose.
