# pkgaudit Internals

This vignette is for someone reading pkgaudit’s source code. For how to
use pkgaudit and what it reports, see [Getting
Started](https://tylerjssmith.github.io/pkgaudit/articles/pkgaudit.md);
for the rule set, see [Rule
Coverage](https://tylerjssmith.github.io/pkgaudit/articles/rules.md).

## pkgaudit steps

[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
orchestrates a series of function calls, which may be loosely grouped as
four steps:

1.  Discover
2.  Extract
3.  Analyze
4.  Resolve

### Discover

[`find_file_contexts()`](https://tylerjssmith.github.io/pkgaudit/reference/find_file_contexts.md)
runs one [`list.files()`](https://rdrr.io/r/base/list.files.html) per
file-context rule, using a file context rule’s `path`, `filename` and
`recursive` fields. If `report = TRUE` in a rule, the file context is
reported in the pkgaudit object’s `$file_contexts` data frame.

### Extract

For each file context, whether reported or not,
[`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md)
dispatches to S3 methods that read each file into *segments*: contiguous
runs of code in one language, blank-padded so that line *n* of a segment
is line *n* of the source file. Dispatch is based on the file-context
rule’s `type`. The methods live in `R/extract_*.R`.

| Extractors      |
|-----------------|
| extract_R.R     |
| extract_Rd.R    |
| extract_rmd.R   |
| extract_rnw.R   |
| extract_rsp.R   |
| extract_shell.R |

A type read like another inherits from it rather than repeating a
method. For example, `make` inherits `shell` and `qmd` inherits `Rmd`.
[`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md)
has a default method that fails closed: a type with no extractor yields
no segments.

### Analyze

For each segment extracted,
[`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md)
dispatches to S3 methods that call functions to find code contexts,
patterns, or matches in each segment. Dispatch is based on the segment’s
`language`, such as R or shell. The methods live in `R/analyze_*.R`.

| Analyzers       |
|-----------------|
| analyze_R.R     |
| analyze_shell.R |

`analyze_segment.R` (in `R/analyze_R.R`) calls functions including
[`parse_code()`](https://tylerjssmith.github.io/pkgaudit/reference/parse_code.md),
which uses [`parse()`](https://rdrr.io/r/base/parse.html) and
[`xmlparsedata::xml_parse_data()`](https://rdrr.io/pkg/xmlparsedata/man/xml_parse_data.html)
to derive an XML parse tree for R code; and
[`find_patterns()`](https://tylerjssmith.github.io/pkgaudit/reference/find_patterns.md)
and
[`find_indirect()`](https://tylerjssmith.github.io/pkgaudit/reference/find_indirect.md),
which use the parse tree and
[`xml2::xml_find_all()`](http://xml2.r-lib.org/reference/xml_find_all.md)
to find patterns and indirect calls using function names (e.g.,
`do.call("system", ...)`).
[`determine_code_contexts()`](https://tylerjssmith.github.io/pkgaudit/reference/determine_code_contexts.md)
determines the code context of patterns and indirect calls.

`analyze_segment.shell` (in `R/analyze_shell.R`) calls functions
including
[`find_matches()`](https://tylerjssmith.github.io/pkgaudit/reference/find_matches.md),
which uses `gregexpr(perl = TRUE)` to find text matching regular
expressions in shell and Make-like files, and `bash`, `sh`, and `zsh`
vignette chunks.

[`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md)
has a default method that fails closed: a language with no analyzer
yields no findings and no error, recording a coverage row instead.

### Resolve

A set of internal functions uses file or code contexts to resolve the
phases in which a pattern or match may run. The supported phases are:

| Phase            | Code executes when                           |
|------------------|----------------------------------------------|
| `at_autoconf`    | Autoconf is run to generate `configure`      |
| `at_build`       | `R CMD build`                                |
| `at_check`       | `R CMD check`                                |
| `at_install_src` | `R CMD INSTALL` from source                  |
| `at_install_bin` | a prebuilt binary package is installed       |
| `at_load`        | the namespace is loaded                      |
| `at_attach`      | the package is attached to the search path   |
| `at_unload`      | the namespace is unloaded                    |
| `at_detach`      | the package is detached from the search path |

Pattern phases are resolved from code and file contexts, in that order.
A pattern in a code context defined by a rule, such as `.onLoad`, takes
that context’s phases. A pattern in top-level code takes its file
context’s phases. A pattern in a regular function definition depends on
the `assume_called` field of the file-context rule: if `TRUE`, it takes
the phases of whatever encloses it; if `FALSE`, as under `R/`, it
receives no phase. (A helper defined under `R/` may still be called from
a lifecycle hook, and human reviewers should verify whether that
occurs.) Match phases are resolved from file contexts. A rule can belong
to several phases.

Phases were established by running instrumented packages and recording
which sites fired, rather than read from documentation.

## Call list

The
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
call list below is derived from pkgaudit’s source code. A name appears
once, at the first place it is reached; a function called from several
places is not repeated. The tree is cut at four levels deep.

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

### Scanned files are never executed

Since pkgaudit is intended for reviewing untrusted packages, it must
never execute code contained in those packages.
`tests/testthat/test-no_execution.R` builds a package where every
execution site writes a marker file, scans it, exports it, and requires
that none of the markers exist afterwards.

Three calls in the read path look like execution and are not.
[`tools::parse_Rd()`](https://rdrr.io/r/tools/parse_Rd.html) parses
without evaluating;
[`tools::loadPkgRdMacros()`](https://rdrr.io/r/tools/loadRdMacros.html)
reads macro definitions as text; and `parse(text = )` produces an
unevaluated expression. Macros come from the package’s own `man/macros/`
and from any provider named in its `RdMacros` field; both are read as
text, not evaluated.

### File size limits are applied before extraction

A file over 10 MB is not read.
[`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md)
applies this restriction before
[`UseMethod()`](https://rdrr.io/r/base/UseMethod.html) so that no method
can skip it. `tests/testthat/test-segments.R` verifies that an oversized
file is not scanned and that the refusal is recorded in `errors`.

### Failures are contained and counted

Listing files, reading a file, parsing code, and evaluating an XPath or
a regular expression are each wrapped in
[`tryCatch()`](https://rdrr.io/r/base/conditions.html): a failure
becomes a row in `errors` rather than aborting the scan.

### Rules are integrity-checked

Rules live in a SQLite database built from YAML by
`inst/scripts/build_db.R`.
[`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
verifies the database against its SHA-256 sidecar on every call. The
check is time-of-check to time-of-use; see “Security considerations” in
[`?load_rules`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md).

[`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
also refuses a database with a gap in its phase model, so a rule whose
findings would carry no phases can never ship.

### Every rule is verified against its own examples

Each rule carries positive and negative examples in its YAML.
`build_db.R` writes them out as fixtures, and
`tests/testthat/test-fixtures.R` requires every positive to match its
rule and every negative to not match.
