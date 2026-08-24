# pkgaudit Internals

This vignette is for someone reading pkgaudit’s source before trusting
it. For how to use pkgaudit and what it reports, see [Getting
Started](https://tylerjssmith.github.io/pkgaudit/articles/pkgaudit.md);
for the rule set, see [Rule
Coverage](https://tylerjssmith.github.io/pkgaudit/articles/rules.md).

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
    dispatches to S3 methods that read each file into *segments*:
    contiguous runs of code in one language, blank-padded so that line
    *n* of a segment is line *n* of the source file.
3.  **Analyze.**
    [`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md)
    dispatches to S3 methods that call functions to find code contexts,
    patterns, or matches in each segment.
4.  **Resolve.** A set of functions attaches and resolves the phases in
    which a pattern or match may run.

## Extraction and analysis

Steps 2 and 3 dispatch to S3 methods.

- [`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md)
  dispatches on the file-context rule’s **`type`**, such as an R source
  file, an Rd file containing examples, or an Rmd vignette containing
  code chunks. These methods live in `R/extract_*.R`.
- [`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md)
  dispatches on the segment’s **`language`**, such as R or shell. These
  methods live in `R/analyze_*.R`.

A type or language read like another inherits from it rather than
repeating a method. For example, `make` inherits `shell`, and `qmd`
inherits `Rmd`.

The default methods fail closed. A type with no extractor yields no
segments; a language with no analyzer yields no findings and no error,
recording a coverage row instead.

## Call list

The
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
call list below is derived from pkgaudit’s source code. It is not
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
unevaluated expression. A macro provider is looked up by macro name
against a fixed list and never taken from the audited package’s
`RdMacros` field, since the untrusted package determines the field
value.

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
