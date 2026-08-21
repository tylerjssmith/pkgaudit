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
[SECURITY.md](https://github.com/tylerjssmith/pkgaudit/blob/main/.github/SECURITY.md).

## pkgaudit steps

[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
orchestrates a series of function calls, which may be grouped as
follows:

1.  **Discover.**
    [`find_file_contexts()`](https://tylerjssmith.github.io/pkgaudit/reference/find_file_contexts.md)
    runs one [`list.files()`](https://rdrr.io/r/base/list.files.html)
    per file-context rule, using a file context rule’s `path`,
    `filename` and `recursive` fields. If `report = TRUE` in a rule, the
    file context is reported in the pkgaudit object’s `$file_contexts`
    data frame.
2.  **Extract.**
    [`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md)
    reads each file into *segments*: contiguous runs of code in one
    language, blank-padded to the length of the source so that line *n*
    of a segment is line *n* of the file.
3.  **Analyze.**
    [`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md)
    finds code contexts, patterns, and matches in each segment.
4.  **Resolve.** A set of functions attaches and resolves the phases in
    which a pattern or match may run.

## Two axes of dispatch

Steps 2 and 3 are both S3 generics.

- [`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md)
  dispatches on the file-context rule’s **`type`**, such as an R source
  file, an Rd file containing examples, or an Rmd vignette containing
  code chunks. These methods live in `R/extract_*.R`.
- [`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md)
  dispatches on the segment’s **`language`**, such as R or shell. These
  methods live in `R/analyze_*.R`.

A type or language read exactly like another inherits from it rather
than repeating a method. For example, `make` inherits `shell`, and `qmd`
inherits `Rmd`.

Both defaults fail closed. A type with no reader yields no segments; a
language with no analyzer yields no findings and no error, and records a
coverage row instead, so an unhandled chunk engine is accounted for
rather than silently dropped.

Adding a file format is one new `R/extract_*.R` plus a rule. Adding a
language is one new `R/analyze_*.R` plus rules carrying that language.
Neither touches
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md),
and neither touches the other.

Both generics are exported, along with
[`new_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/new_segment.md)
and
[`new_findings()`](https://tylerjssmith.github.io/pkgaudit/reference/new_findings.md),
which build what a method returns. A method can therefore be registered
from another package rather than only by editing this one – though the
rule that points the scan at the new files still has to reach the rules
database, which means the issue thread `CONTRIBUTING.md` describes.

## Call list

The graph below is derived from pkgaudit’s own source. It is not
maintained by hand and cannot fall behind the code. A name appears once,
at the first place it is reached; a function called from several places
is not repeated. The tree is cut at four levels deep.

    audit_package()
    ├─ .check_path()
    │  └─ .stop_arg()
    ├─ .check_rules()
    │  └─ .stop_arg()
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
    ├─ .report_file_contexts()
    ├─ .load_rd_macros()
    ├─ .scan_file_contexts()
    │  └─ .named_contexts()
    ├─ new_source()
    │  └─ .source_class()
    ├─ extract_segments()
    │  ├─ .over_scan_limit()
    │  ├─ .error_row()
    │  ├─ extract_segments.R()
    │  │  ├─ read_code()
    │  │  └─ new_segment()
    │  ├─ extract_segments.Rd()
    │  │  ├─ read_Rd_code()
    │  │  │  ├─ .empty_Rd_code()
    │  │  │  ├─ .parse_Rd_safe()
    │  │  │  └─ .Rd_fragments()
    │  │  └─ new_segment()
    │  ├─ extract_segments.Rmd()
    │  │  ├─ read_code()
    │  │  ├─ .rmd_chunks()
    │  │  │  ├─ .rmd_header()
    │  │  │  ├─ .unquote_lines()
    │  │  │  └─ .rmd_pipe_eval()
    │  │  ├─ new_segment()
    │  │  ├─ .blank_except()
    │  │  └─ .rmd_inline()
    │  │     ├─ .inline_code()
    │  │     └─ .mask_verbatim()
    │  ├─ extract_segments.Rnw()
    │  │  ├─ read_code()
    │  │  ├─ .rnw_code()
    │  │  │  └─ .inline_code()
    │  │  ├─ new_segment()
    │  │  └─ .blank_except()
    │  ├─ extract_segments.rsp()
    │  │  ├─ read_code()
    │  │  ├─ .rsp_code()
    │  │  │  └─ .fixed_positions()
    │  │  └─ new_segment()
    │  ├─ extract_segments.shell()
    │  │  ├─ read_code()
    │  │  └─ new_segment()
    │  └─ extract_segments.default()
    ├─ analyze_segment()
    │  ├─ analyze_segment.R()
    │  │  ├─ parse_code()
    │  │  ├─ new_findings()
    │  │  ├─ .error_row()
    │  │  ├─ .applicable_contexts()
    │  │  ├─ find_code_contexts()
    │  │  │  ├─ .empty_code_contexts()
    │  │  │  └─ .xml_find_all_safe()
    │  │  ├─ find_patterns()
    │  │  │  ├─ .empty_found()
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
    │  │  └─ new_findings()
    │  └─ analyze_segment.default()
    │     ├─ new_findings()
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
    │  ├─ .empty_phase_cols()
    │  └─ .phase_lookup()
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
also refuses a database with a gap in its phase model: a rule without
phases, a file-context rule naming a code context that does not exist,
or one that leaves `assume_called` undecided where code contexts can
arise – or decides it where they cannot. A rule can never ship whose
findings would silently carry no phases.

### Every rule is verified against its own examples

Each rule carries positive and negative examples in its YAML.
`build_db.R` writes them out as fixtures, and
`tests/testthat/test-fixtures.R` requires every positive to match its
rule and every negative not to. A rule is trusted because its
documentation is executable, not because it is documented.

For a code-context rule matched on a segment label rather than on the
parse tree, the examples are help files and the test is a round trip:
the extractor must stamp the label the rule claims, on a page carrying
that kind of code and on no other. That is the only thing tying such a
rule to the extractor, since its label is checked against a fixed
vocabulary when the database is built but nothing there confirms the
extractor produces it.

The same file checks two further contracts that would otherwise drift. A
pattern rule’s `functions` field – the names it claims for
`do.call("name", ...)` – is accepted only if calling that name bare
would have matched the rule’s own XPath, so an indirect finding can
never be attributed to a rule that would not have reported the direct
call. And `eval_parse`’s source list is required to cover every function
the capability rules it composes declare.

Documentation is held to the same standard. The rule set’s vignette is
generated from the shipped database rather than written alongside it,
and every rule in that database must be described there, so a rule that
ships without a description fails the vignette build. Neither that nor a
failing example can be fixed by editing prose.

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
  model, and every result in SARIF output carries the same `level`.
- It does not reach the network, and it writes only where a caller sends
  it.
- It does not trace call graphs. Whether a particular package calls a
  particular function is not something pkgaudit determines, which is why
  the phases of code inside a function definition are a stated reading
  rather than a finding.
- It does not identify a file by its contents, only by its name. An
  extensionless script – `tools/build` opening `#!/bin/sh` – earns no
  coverage row: 434 such files across 134 of CRAN’s 24,216 packages.
  Admitting a file on a leading `#!` would close this and is a candidate
  for a later release.
