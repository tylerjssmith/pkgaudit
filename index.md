# pkgaudit

[![Project Status:
Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![R-CMD-check](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/tylerjssmith/pkgaudit/badges/coverage.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/test-coverage.yaml)
[![osv-scanner](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml)

pkgaudit is a static analysis security testing (SAST) tool for R
packages. It flags security-relevant files and code in R source packages
for human review without executing anything it scans. pkgaudit also
models package lifecycle execution semantics – it reports not just what
a package does, but when it runs, so code that executes on install or
load is distinguishable from code that runs only when called.

A general-purpose scanner can read R – Semgrep supports it
experimentally – but it reads files, not packages. Nothing tells it to
look for R inside a help file’s `\examples{}` block or an `\Sexpr{}`
macro, or inside a Sweave or R.rsp vignette; and nothing tells it that
`.onLoad()` runs on [`library()`](https://rdrr.io/r/base/library.html),
that `\Sexpr{}` evaluates while a help page is built, or that
`configure` runs under `R CMD check`. pkgaudit extracts R from wherever
a package carries it, parses the code for security-relevant patterns,
and reports the lifecycle phases in which each finding runs.

For why this matters, see [R Package
Security](https://tylerjssmith.github.io/pkgaudit/articles/security.md).
For the rule set, see [Rule
Coverage](https://tylerjssmith.github.io/pkgaudit/articles/rules.md).

## Installation

``` r

remotes::install_github("tylerjssmith/pkgaudit")
```

## Usage

A source package tarball can be scanned before it is installed. The
example below scans `untrustedpkg`, a small package shipped with
pkgaudit for demonstration.

``` r

library(pkgaudit)

tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)

result <- audit_tarball(tarball)

summary(result, path = FALSE)
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-24 17:44 UTC with pkgaudit v0.4.0, rules v0.4.0
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
```

Four of `untrustedpkg`’s five findings run automatically:

- `.onLoad()` in `R/zzz.R` calls
  [`system()`](https://rdrr.io/r/base/system.html), which runs when
  users call [`library()`](https://rdrr.io/r/base/library.html), and at
  build, check, and source installation, each of which loads the
  package.

- An `\Sexpr{}` macro in `man/fetch_data.Rd` calls
  [`httr::POST()`](https://httr.r-lib.org/reference/POST.html) when the
  help page is rendered at build, check, and source installation.

- The `\examples{}` block in the same help file calls
  [`download.file()`](https://rdrr.io/r/utils/download.file.html) at
  check.

- The `configure` script may invoke `curl` at build, check, and source
  installation.

By contrast,
[`download.file()`](https://rdrr.io/r/utils/download.file.html) in
`R/fetch.R` sits in a regular function body, so it is not known to run
automatically and is reported under `none`.

Phases overlap – building a package with vignettes also installs and
loads it – so one occurrence is counted under every phase it runs in.

pkgaudit provides functions to integrate its scan with other tools.
[`emit_sarif()`](https://tylerjssmith.github.io/pkgaudit/reference/emit_sarif.md)
renders its results as SARIF 2.1.0, which editors and code-scanning
platforms read directly.
[`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
writes out package code in languages pkgaudit cannot read, into a
directory for a scanner that can. See [Getting Started with
pkgaudit](https://tylerjssmith.github.io/pkgaudit/articles/pkgaudit.md)
for details.

## Security

pkgaudit’s own security model, and how to report a vulnerability, are in
[SECURITY.md](https://github.com/tylerjssmith/pkgaudit/blob/main/.github/SECURITY.md).
To propose or revise a rule, see
[CONTRIBUTING.md](https://github.com/tylerjssmith/pkgaudit/blob/main/.github/CONTRIBUTING.md).
How pkgaudit works internally, for a reader auditing the source, is in
[Internals](https://tylerjssmith.github.io/pkgaudit/articles/internals.md).
