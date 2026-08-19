# Read one source file into the code segments it contains

Dispatches on the file-context rule's `type`, which is the only place a
new variety of file is named.

## Usage

``` r
extract_segments(source)
```

## Arguments

- source:

  A `pkgaudit_source`: a list with the file's `path`, its
  package-root-relative `file_context`, the claiming rule in
  `file_rule`, the applicable `code_contexts`, and `macros`. Sources are
  built inside
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md),
  one per claimed file; a method receives them and never constructs one.

## Value

A list of two elements:

- segments:

  List of segments from
  [`new_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/new_segment.md),
  each holding `lines` aligned to the lines of the source file.

- errors:

  Data frame with columns `step`, `file_context`, `rule`, `message`.

## Security considerations

The scanning size limit is enforced here, before dispatch, so no method
can skip it. A method must not re-implement it.

A method reads untrusted bytes and must never evaluate them. Return the
code as text in a segment; deciding what it means is
[`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md)'s
job.

## See also

[`analyze_segment()`](https://tylerjssmith.github.io/pkgaudit/reference/analyze_segment.md),
the other axis of dispatch, and
[`vignette("internals")`](https://tylerjssmith.github.io/pkgaudit/articles/internals.md).

## Examples

``` r
# Adding a file format outside pkgaudit: a method for a new rule `type`,
# here one that treats a .txt file as if it held R code.
extract_segments.txt <- function(source) {
  list(segments = list(new_segment(language = "R",
                                   lines = readLines(source$path),
                                   file_context = source$file_context)),
       errors = NULL)
}
registerS3method("extract_segments", "txt", extract_segments.txt)
```
