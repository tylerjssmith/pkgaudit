# Build one code segment

A contiguous, line-aligned run of code in one language, classed by that
language so
[`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md)
can dispatch on it. An
[`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md)
method returns these.

## Usage

``` r
new_segment(
  language,
  lines,
  file_context,
  context = NA_character_,
  file_rule = NA_character_,
  code_contexts = NULL,
  guarded_lines = integer(0L)
)
```

## Arguments

- language:

  The language of the code, which selects the analyzer.

- lines:

  Character vector of the segment's lines, blank-padded to the line
  numbers they occupy in the file so a finding's line is the real one.

- file_context:

  Package-root-relative path of the file it came from.

- context:

  The segment's label, matched by a `kind: segment` code-context rule,
  or `NA` where it has none. It is the only record of which part of a
  help file the code came from.

- file_rule:

  The file-context rule that claimed the file.

- code_contexts:

  The code-context rules that can apply, from the source.

- guarded_lines:

  Integer vector of line numbers whose code ships but the lifecycle does
  not run – a `\dontrun{}` block, or a chunk marked `eval=FALSE`. Phases
  still come from the context, so they are an upper bound.

## Value

A `pkgaudit_segment` object.

## See also

[`extract_segments()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_segments.md),
whose methods return these.

## Examples

``` r
seg <- new_segment(language = "R", lines = c("", "system('id')"),
                   file_context = "R/f.R")
class(seg)
#> [1] "R"                "pkgaudit_segment"
```
