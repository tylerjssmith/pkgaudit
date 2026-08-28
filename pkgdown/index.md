
<!-- index.md is generated from index.Rmd. Please edit index.Rmd. -->

# pkgaudit

[![Project Status:
Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![R-CMD-check](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/tylerjssmith/pkgaudit/badges/coverage.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/test-coverage.yaml)
[![osv-scanner](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml)

pkgaudit scans R packages for security-relevant files and code without
executing anything it scans. It reports what code does and when it runs,
so code that runs automatically on install or load is distinguishable
from code that runs only when called.

A general-purpose scanner like Semgrep can read R – but it reads
scripts, not packages. It does not look for R inside an `\examples{}`
block, an `\Sexpr{}` macro, or a vignette. It does not know that
`.onLoad()` runs when a user calls `library()` or that a `configure`
script runs on `R CMD check`. pkgaudit extracts code wherever it exists,
scans it for functions and commands that need human review, and reports
the lifecycle phases in which each finding runs.

For why this matters, see [R Package Security](articles/security.html).
For the rule set, see [Rule Coverage](articles/rules.html).

## Installation

``` r
remotes::install_github("tylerjssmith/pkgaudit")
```

## Usage

A source package tarball can be scanned before it is installed. The
example below scans `untrustedpkg`, a small package shipped with
pkgaudit for demonstration. We see that, when `untrustedpkg` is
installed from source, its R code will make an HTTP request (`httr`) and
invoke a shell command (`system`). Meanwhile, a shell script may invoke
the `curl` command.

``` r
library(pkgaudit)

tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)

result <- audit_tarball(tarball)

summary(result, phase = "at_install_src", path = FALSE)
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-28 02:25 UTC with pkgaudit v0.4.0, rules v0.4.0
#> Phases:    at_install_src
#> 
#> --- R Patterns --------------------------------------------------------------
#> phase            rule     n   attck
#> at_install_src   httr     1   T1041
#> at_install_src   system   1   T1059.003 T1059.004
#> 
#> --- Shell / Make Matches ----------------------------------------------------
#> phase            rule     n   attck
#> at_install_src   curl     1   T1041 T1105
#> 
#> --- Coverage ----------------------------------------------------------------
#> status    top_level   type    files   lines
#> parsed    R/          R           2       6
#> parsed    man/        Rd          1      12
#> matched   .           shell       1       3
#> 
#> --- Errors ------------------------------------------------------------------
#> No exceptions were raised.
```

The supported phases are: `at_autoconf`, `at_build`, `at_check`,
`at_install_src`, `at_install_bin`, `at_load`, `at_attach`, `at_unload`,
and `at_detach`. A finding with no phase, such as a pattern inside a
regular function in `R/`, is reported as `none`.

pkgaudit can integrate its scan with other tools. `emit_sarif()` renders
its results as SARIF 2.1.0, which editors and code-scanning platforms
read directly. `export_unscanned()` exports code written in languages
pkgaudit cannot read to a directory for a scanner that can.

See [Getting Started with pkgaudit](articles/pkgaudit.html) for details.

## Security

pkgaudit’s own security model, and how to report a vulnerability, are in
[SECURITY.md](https://github.com/tylerjssmith/pkgaudit/blob/main/.github/SECURITY.md).
To propose or revise a rule, see
[CONTRIBUTING.md](https://github.com/tylerjssmith/pkgaudit/blob/main/.github/CONTRIBUTING.md).
How pkgaudit works internally, for a reader auditing the source, is in
[Internals](articles/internals.html).
