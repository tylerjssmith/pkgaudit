# Summarize a pkgaudit result

`summary.pkgaudit()` rolls a scan up into the frequency of each R
pattern and each shell or make match by the lifecycle phase it executes
in, with their MITRE ATT&CK techniques; how much of the package was
read; and the errors, if any. It also collects the distinct file
contexts found, which the report does not show.
`print.summary.pkgaudit()` writes that summary as a sectioned report and
returns the object invisibly.

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
  local filesystem location scanned. Set `FALSE` to omit local paths.
  `summary.pkgaudit()` records the choice in the object it returns;
  `print.summary.pkgaudit()` uses that recorded value unless given its
  own.

- phase:

  Character vector of lifecycle phases to report, e.g. `"at_load"`, or
  `"none"` for occurrences that execute in no phase. `NULL` (default)
  reports every phase. An unrecognised name is an error.

- ...:

  Ignored, for S3 compatibility.

- x:

  A `summary.pkgaudit` object.

## Value

`summary.pkgaudit()` returns a `summary.pkgaudit` object: a named list
of four summary data frames, the errors, the scan `metadata`, and the
recorded `path`.

- file_contexts:

  `file_context`: each file context found, once.

- patterns:

  `phase`, `rule`, `n`, `attck`: how often each pattern rule was
  matched, split by the lifecycle phase its code executes in, with the
  ATT&CK techniques the rule carries. The code context a finding sits in
  is how its phases were derived rather than a finding of its own, so it
  stays on the object's `patterns` frame and out of the report.

- matches:

  `phase`, `rule`, `n`, `attck`: how often each match rule was matched
  across the shell scripts and Make-like files, split by the lifecycle
  phase those files execute in. Shaped as `patterns` is; which file each
  match sits in is on the object's `matches` frame.

- coverage:

  `status`, `top_level`, `type`, `files`, `lines`: how much of the
  package pkgaudit read, grouped by where the files sit and what kind
  they are. `type` is what a file was read as where a rule read it, and
  its extension otherwise.

- errors:

  `step`, `file_context`, `rule`, `error`: the rows of the object's
  `errors` data frame, renamed for display. The report shows only `step`
  and `file_context`; the notes are built from the other two.

`print.summary.pkgaudit()` returns `x` invisibly.

## Details

The report opens with the same metadata block as
[`print.pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/format.pkgaudit.md),
then gives the `R Patterns`, `Shell / Make Matches`, `Coverage`, and
`Errors` sections. A section with nothing to report says so. The
`file_contexts` summary is returned for programmatic use but is not part
of the report.

`Coverage` is counts with reasons, and deliberately no percentage.
Nothing in a package is assumed inert, so coverage never reaches 100%
and a ratio would only ever flatter; what a reader needs is which files
went unexamined and whether they execute. Which files those are is in
the object's own `coverage` frame; the report gives the shape of the
package, not the list.

A pattern occurrence executes in every phase its code context does, and
a match in every phase its file context does, so each contributes one
row per phase and the `n` column sums to more than the number of
occurrences. Occurrences that execute in no phase at all are gathered
under `none`.

Both findings tables are grouped by phase and rule alone. Where a
finding sits – the code context of a pattern, the file of a match – is
on the object's own frames; the report answers what runs, and when.

`phase` restricts the report to the phases named. It is the only way to
narrow it: the summary has already been expanded by phase, so it cannot
be subset afterwards. The default reports every phase, and a filtered
report names its phases in the header, so it cannot be mistaken for a
full scan.

The `Errors` section lists every error by step and file context, and is
followed by one note per step stating what scan coverage was lost. The
rule and the message are left out of the table – a message is often long
enough to wrap the report on its own – and are in `s$errors` for a
caller who wants them.

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
#> Path:      /home/runner/work/_temp/Library/pkgaudit/extdata/untrustedpkg/untrustedpkg_0.1.0.tar.gz
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-11 21:38 UTC with pkgaudit v0.4.0, rules v0.4.0
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
#> Scanned:   2026-08-11 21:38 UTC with pkgaudit v0.4.0, rules v0.4.0
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
#> Path:      /home/runner/work/_temp/Library/pkgaudit/extdata/untrustedpkg/untrustedpkg_0.1.0.tar.gz
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-11 21:38 UTC with pkgaudit v0.4.0, rules v0.4.0
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
#> Path:      /home/runner/work/_temp/Library/pkgaudit/extdata/untrustedpkg/untrustedpkg_0.1.0.tar.gz
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-11 21:38 UTC with pkgaudit v0.4.0, rules v0.4.0
#> Phases:    none
#> 
#> --- R Patterns --------------------------------------------------------------
#> phase   rule            n   attck
#> none    download_file   1   T1105
#> 
#> --- Shell / Make Matches ----------------------------------------------------
#> No matches were found.
#> 
#> --- Coverage ----------------------------------------------------------------
#> No files were found.
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
