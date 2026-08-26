
<!-- index.md is generated from index.Rmd. Please edit index.Rmd. -->

# pkgaudit

[![Project Status:
Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![R-CMD-check](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/tylerjssmith/pkgaudit/badges/coverage.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/test-coverage.yaml)
[![osv-scanner](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml)

pkgaudit is a static analysis security testing (SAST) tool for R
packages. It flags security-relevant files and code in R source packages
for human review without executing anything it scans. pkgaudit reports
not just what code does, but when it runs, so code that executes on
install or load is distinguishable from code that runs only when called.

A general-purpose scanner like Semgrep can read R – but it reads files,
not packages. It does not look for R inside a help file’s `\examples{}`
block or an `\Sexpr{}` macro, or inside a vignette. It does not know
that `.onLoad()` runs on `library()`, that `\Sexpr{}` evaluates while a
help page is built, or that `configure` runs under `R CMD check`.
pkgaudit extracts R from wherever a package carries it, parses it for
security-relevant patterns, and reports the lifecycle phases in which
each finding runs.

For why this matters, see [R Package Security](articles/security.html).
For the rule set, see [Rule Coverage](articles/rules.html).

## Installation

``` r
remotes::install_github("tylerjssmith/pkgaudit")
```

## Usage

A source package tarball can be scanned before it is installed. The
example below scans `untrustedpkg`, a small package shipped with
pkgaudit for demonstration. Phases overlap – building a package with
vignettes also installs and loads it – and one occurrence is counted
under every phase it runs in.

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
#> Scanned:   2026-08-26 12:41 UTC with pkgaudit v0.4.0, rules v0.4.0
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

The summary shows five findings, some counted under multiple phases,
four of which run automatically:

- `.onLoad()` in `R/zzz.R` calls `system()`, which runs when users call
  `library()`, and at build, check, and source installation, each of
  which loads the package. While `system()` calls are common in R
  packages, they are less common in lifecycle hooks like `.onLoad()`,
  and reviewers should inspect what commands the package would run
  automatically on their systems.

- An `\Sexpr{}` macro in `man/fetch_data.Rd` calls `httr::POST()` when
  the help page is rendered at build, check, and source installation. An
  HTTP POST request in a help file is unusual, and reviewers should
  consider why it exists and what data it may send to an external host.

- The `\examples{}` block in the same help file calls `download.file()`
  at check. A reviewer should verify what is downloaded. Since what is
  downloaded may change over time, a reviewer should also consider how
  the download is used – for example, could another function execute
  code if the file ever contained it?

- The `configure` script may invoke `curl` at build, check, and source
  installation. Some R packages use `curl` to fetch external
  dependencies that cannot be vendored with the package (see [CRAN
  Repository
  Policy](https://cran.r-project.org/web/packages/policies.html)), but
  like with `download.file()`, what is fetched may change over time.

- A regular function in `R/fetch.R` would call `download.file()`, but a
  regular function is not known to run automatically, and this pattern
  is reported under `none`. A reviewer may still want to inspect if and
  when the function is called, and what would be downloaded.

pkgaudit also provides functions to integrate its scan with other tools.
`emit_sarif()` renders its results as SARIF 2.1.0, which editors and
code-scanning platforms read directly. `export_unscanned()` writes out
package code in languages pkgaudit cannot read, into a directory for a
scanner that can. See [Getting Started with
pkgaudit](articles/pkgaudit.html) for details.

## Security

pkgaudit’s own security model, and how to report a vulnerability, are in
[SECURITY.md](https://github.com/tylerjssmith/pkgaudit/blob/main/.github/SECURITY.md).
To propose or revise a rule, see
[CONTRIBUTING.md](https://github.com/tylerjssmith/pkgaudit/blob/main/.github/CONTRIBUTING.md).
How pkgaudit works internally, for a reader auditing the source, is in
[Internals](articles/internals.html).
