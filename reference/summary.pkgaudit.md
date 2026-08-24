# Summarize a pkgaudit result

Takes a `pkgaudit` object produced by
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
or
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
and returns summaries of it: how often each rule fired and in which
lifecycle phase, how much of the package was read, and the errors, if
any. `print.summary.pkgaudit()` writes them as a sectioned report.

## Usage

``` r
# S3 method for class 'pkgaudit'
summary(object, path = TRUE, phase = NULL, ...)

# S3 method for class 'summary.pkgaudit'
print(x, path = x$path, ...)
```

## Arguments

- object:

  A `pkgaudit` object.

- path:

  Logical; if `TRUE` (default) include the `Path:` line showing the
  local filesystem location scanned, with the home directory written as
  `~`. Set `FALSE` to omit the line. `summary.pkgaudit()` records the
  choice in the object it returns; `print.summary.pkgaudit()` uses that
  recorded value unless given its own.

- phase:

  Character vector of lifecycle phases to report, e.g. `"at_load"`, or
  `"none"` for occurrences that execute in no phase. `NULL` (default)
  reports every phase. An unrecognized name is an error.

- ...:

  Ignored, for S3 compatibility.

- x:

  A `summary.pkgaudit` object.

## Value

`summary.pkgaudit()` returns a `summary.pkgaudit` object: a named list
of five summary data frames, the scan `metadata`, the recorded `path`,
and the recorded `phase` – the phases the frames were filtered to, or
`NULL` for an unfiltered summary.
[`print()`](https://rdrr.io/r/base/print.html) reads it to head the
report with the phases asked for, so an empty section is not mistaken
for a clean scan.

- file_contexts:

  `file_context`: each file context found, once.

- patterns:

  `phase`, `rule`, `n`, `attck`: how often each pattern rule matched,
  split by the phase its code executes in.

- matches:

  `phase`, `rule`, `n`, `attck`: as `patterns`, across the shell and
  Make-like files.

- coverage:

  `status`, `top_level`, `type`, `files`, `lines`: how much of the
  package was read, grouped by where the files sit and what kind they
  are. `type` is what a file was read as, or its extension.

- errors:

  `step`, `file_context`, `rule`, `error`: the object's `errors` rows,
  renamed for display.

`print.summary.pkgaudit()` returns `x` invisibly.

## Details

The report opens with the same metadata block as
[`print.pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/format.pkgaudit.md),
then gives the `R Patterns`, `Shell / Make Matches`, `Coverage` and
`Errors` sections; a section with nothing to report says so. The
`file_contexts` summary is returned for programmatic use but is not part
of the report.

Both findings tables are grouped by phase and rule alone. Where a
finding sits is on the object's own frames; the report answers what
runs, and when. An occurrence executes in every phase its context does,
so it contributes one row per phase and `n` can sum to more than the
number of occurrences. Those executing in no phase are gathered under
`none`.

`Coverage` is counts by status and location, and deliberately no
percentage: coverage never reaches 100%. Which files went unexamined is
in the object's `coverage` frame.

## Filtering by phase

`phase` restricts the report to the phases named, and is the only way to
narrow it: the summary has already been expanded by phase, so it cannot
be subset afterwards. A filtered report names its phases in the header,
so it cannot be mistaken for a full scan.

## See also

[`print.pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/format.pkgaudit.md)
for the finding counts alone.

## Examples

``` r
# untrustedpkg is a small package shipped with pkgaudit to be scanned.
tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)
result <- audit_tarball(tarball)

summary(result)
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> Path:      ~/work/_temp/Library/pkgaudit/extdata/untrustedpkg/untrustedpkg_0.1.0.tar.gz
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-24 16:24 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> --- R Patterns --------------------------------------------------------------
#> phase            rule            n   attck
#> at_build         httr            1   T1041
#> at_build         system          1   T1059.003 T1059.004
#> at_check         download_file   1   T1105
#> at_check         httr            1   T1041
#> at_check         system          1   T1059.003 T1059.004
#> at_install_src   httr            1   T1041
#> at_install_src   system          1   T1059.003 T1059.004
#> at_load          system          1   T1059.003 T1059.004
#> none             download_file   1   T1105
#> 
#> none: reported at no phase because nothing in the package was seen to call
#> it. Code under R/ is read this way by rule; a caller elsewhere, or a user,
#> can still reach it. See vignette("rules").
#> 
#> --- Shell / Make Matches ----------------------------------------------------
#> phase            rule            n   attck
#> at_build         curl            1   T1041 T1105
#> at_check         curl            1   T1041 T1105
#> at_install_src   curl            1   T1041 T1105
#> 
#> --- Coverage ----------------------------------------------------------------
#> status       top_level   type          files   lines
#> parsed       R/          R                 2       6
#> parsed       man/        Rd                1      12
#> matched      .           shell             1       3
#> unexamined   .           DESCRIPTION       1
#> 
#> --- Errors ------------------------------------------------------------------
#> No exceptions were raised.
summary(result, path = FALSE)       # omit the local Path: line for sharing
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-24 16:24 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> --- R Patterns --------------------------------------------------------------
#> phase            rule            n   attck
#> at_build         httr            1   T1041
#> at_build         system          1   T1059.003 T1059.004
#> at_check         download_file   1   T1105
#> at_check         httr            1   T1041
#> at_check         system          1   T1059.003 T1059.004
#> at_install_src   httr            1   T1041
#> at_install_src   system          1   T1059.003 T1059.004
#> at_load          system          1   T1059.003 T1059.004
#> none             download_file   1   T1105
#> 
#> none: reported at no phase because nothing in the package was seen to call
#> it. Code under R/ is read this way by rule; a caller elsewhere, or a user,
#> can still reach it. See vignette("rules").
#> 
#> --- Shell / Make Matches ----------------------------------------------------
#> phase            rule            n   attck
#> at_build         curl            1   T1041 T1105
#> at_check         curl            1   T1041 T1105
#> at_install_src   curl            1   T1041 T1105
#> 
#> --- Coverage ----------------------------------------------------------------
#> status       top_level   type          files   lines
#> parsed       R/          R                 2       6
#> parsed       man/        Rd                1      12
#> matched      .           shell             1       3
#> unexamined   .           DESCRIPTION       1
#> 
#> --- Errors ------------------------------------------------------------------
#> No exceptions were raised.
summary(result, phase = "at_load")  # only what runs when the package loads
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> Path:      ~/work/_temp/Library/pkgaudit/extdata/untrustedpkg/untrustedpkg_0.1.0.tar.gz
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-24 16:24 UTC with pkgaudit v0.4.0, rules v0.4.0
#> Phases:    at_load
#> 
#> --- R Patterns --------------------------------------------------------------
#> phase     rule     n   attck
#> at_load   system   1   T1059.003 T1059.004
#> 
#> --- Shell / Make Matches ----------------------------------------------------
#> No matches were found.
#> 
#> --- Coverage ----------------------------------------------------------------
#> No files were found.
#> 
#> --- Errors ------------------------------------------------------------------
#> No exceptions were raised.
summary(result, phase = "none")     # ships, but runs at no phase
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> Path:      ~/work/_temp/Library/pkgaudit/extdata/untrustedpkg/untrustedpkg_0.1.0.tar.gz
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-24 16:24 UTC with pkgaudit v0.4.0, rules v0.4.0
#> Phases:    none
#> 
#> --- R Patterns --------------------------------------------------------------
#> phase   rule            n   attck
#> none    download_file   1   T1105
#> 
#> none: reported at no phase because nothing in the package was seen to call
#> it. Code under R/ is read this way by rule; a caller elsewhere, or a user,
#> can still reach it. See vignette("rules").
#> 
#> --- Shell / Make Matches ----------------------------------------------------
#> No matches were found.
#> 
#> --- Coverage ----------------------------------------------------------------
#> status       top_level   type          files   lines
#> unexamined   .           DESCRIPTION       1
#> 
#> --- Errors ------------------------------------------------------------------
#> No exceptions were raised.

s <- summary(result)
s$patterns                          # pattern frequencies as a data frame
#>            phase          rule n               attck
#> 1       at_build          httr 1               T1041
#> 2       at_build        system 1 T1059.003 T1059.004
#> 3       at_check download_file 1               T1105
#> 4       at_check          httr 1               T1041
#> 5       at_check        system 1 T1059.003 T1059.004
#> 6 at_install_src          httr 1               T1041
#> 7 at_install_src        system 1 T1059.003 T1059.004
#> 8        at_load        system 1 T1059.003 T1059.004
#> 9           none download_file 1               T1105
s$matches                           # match frequencies as a data frame
#>            phase rule n       attck
#> 1       at_build curl 1 T1041 T1105
#> 2       at_check curl 1 T1041 T1105
#> 3 at_install_src curl 1 T1041 T1105
```
