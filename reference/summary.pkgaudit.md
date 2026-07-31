# Summarize a pkgaudit result

`summary.pkgaudit()` rolls a scan up into the findings counted by the
lifecycle phase they execute in, the distinct file and code contexts
found, the frequency of each pattern with its MITRE ATT&CK techniques,
and the errors, if any. `print.summary.pkgaudit()` writes that summary
as a sectioned report and returns the object invisibly.

## Usage

``` r
# S3 method for class 'pkgaudit'
summary(object, path = TRUE, ...)

# S3 method for class 'summary.pkgaudit'
print(x, path = x$path, ...)
```

## Arguments

- object:

  A `pkgaudit` object.

- path:

  Logical; if `TRUE` (default) include the `Path:` line showing the
  local filesystem location scanned. Set `FALSE` to omit local paths.
  `summary.pkgaudit()` records the choice in the object it returns;
  `print.summary.pkgaudit()` uses that recorded value unless given its
  own.

- ...:

  Ignored, for S3 compatibility.

- x:

  A `summary.pkgaudit` object.

## Value

`summary.pkgaudit()` returns a `summary.pkgaudit` object: a named list
of four summary data frames, the errors, the scan `metadata`, and the
recorded `path`.

- phases:

  `phase`, `file_contexts`, `code_contexts`, `patterns`: how many
  findings of each kind execute during each lifecycle phase, with a
  trailing `none` row for findings that execute in no phase.

- file_contexts:

  `file_context`: each file context found, once.

- code_contexts:

  `rule`: each code-context rule matched, once.

- patterns:

  `rule`, `occurrences`, `attck`: how often each pattern rule was
  matched and the ATT&CK techniques it carries.

- errors:

  `stage`, `script`, `rule`, `error`: the rows of the object's `errors`
  data frame, renamed for display.

`print.summary.pkgaudit()` returns `x` invisibly.

## Details

The report opens with the same metadata block as
[`print.pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/format.pkgaudit.md),
then gives one section per result. A section with nothing to report says
so.

The `Errors` section lists every error, whatever stage produced it, and
is followed by one note per stage stating what scan coverage was lost.
An error recorded against a file-context rule is not tied to a script,
and one recorded against a script that would not parse is not tied to a
rule, so both columns are shown and the inapplicable one is left blank.

## See also

[`print.pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/format.pkgaudit.md)
for the finding counts alone.

## Examples

``` r
if (FALSE) { # \dontrun{
result <- audit_package("/path/to/package")
summary(result)
summary(result, path = FALSE)   # omit the local Path: line for sharing

s <- summary(result)
s$patterns                      # pattern frequencies as a data frame
} # }
```
