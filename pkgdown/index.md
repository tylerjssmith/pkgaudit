
<!-- index.md is generated from index.Rmd. Please edit this file -->

# pkgaudit

[![R-CMD-check](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml)
[![test
coverage](https://raw.githubusercontent.com/tylerjssmith/pkgaudit/badges/coverage.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/coverage.yaml)
[![osv-scanner](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml)

pkgaudit is a static analysis security testing (SAST) tool for R
packages. It scans R source packages for files that can execute
arbitrary commands during autoconf, builds, checks, and installations,
and for hooks whose bodies run automatically when a namespace is loaded,
attached, unloaded, or detached. It scans R source code for
security-relevant patterns like `system()` calls, and shell scripts and
Make-like files for expressions like `curl`.

R packages are the primary mechanism for sharing R code. They are also
[potential attack vectors](articles/r-package-security.html). pkgaudit
helps you identify which parts of an untrusted package deserve your
attention before you install and load it.

## Installation

You can install pkgaudit as follows:

``` r
remotes::install_github("tylerjssmith/pkgaudit")
```

pkgaudit detects security-relevant files and code using a SQLite
database of rules shipped with the package at `inst/db/rules.db`. To
verify that the installed copy of the database has not been modified
since publication, check its SHA-256 hash.

``` r
digest::digest(
  system.file("db", "rules.db", package = "pkgaudit"),
  algo = "sha256",
  file = TRUE
)
```

Expected SHA-256:
`ed20dfecfffc642d3cb3731cfb5d8d5efe574badefdfc3bfef42d00de93d7609`

## Usage

The [Getting Started with pkgaudit](articles/pkgaudit.html) and [How
pkgaudit Works](articles/how-it-works.html) vignettes document usage.
The [Rule Coverage](articles/rules.html) vignette documents the full
rule set. The example below scans `untrustedpkg`, a small package
shipped with pkgaudit for demonstration:

``` r
library(pkgaudit)

tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)

rules  <- load_rules()
result <- audit_tarball(tarball, rules = rules)
```

`summary()` reports how often each R pattern and shell or Make-like
expression occurs by phase and code or file context, and the MITRE
ATT&CK techniques involved. Phases can overlap (e.g., building a package
with vignettes installs and loads it), so a finding may be counted under
more than one phase.

Below, untrustedpkg has an `.onLoad()` hook with a `system()` call that
runs during builds, checks, installations from source, and loads; an
ordinary function with a `download.file()` call that runs only if a user
calls the enclosing function and so belongs to no phase; and a
`configure` script with a `curl` expression that could run during
builds, checks, and installations from source. Code that runs without
being asked deserves closer attention.

``` r
summary(result, path = FALSE)
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> SHA-256:   ff3f1d20618ff4be01e852dacb6b93047d46bf435f4e4fcf2685294c858a8bf7
#> Scanned:   2026-08-03 19:13 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> --- R Patterns --------------------------------------------------------------
#> phase            code_context   rule            n   attck
#> at_build         onLoad_base    system          1   T1059.003 T1059.004
#> at_check         onLoad_base    system          1   T1059.003 T1059.004
#> at_install_src   onLoad_base    system          1   T1059.003 T1059.004
#> at_load          onLoad_base    system          1   T1059.003 T1059.004
#> none             Other          download_file   1   T1105
#> 
#> --- Shell / Make Expressions ------------------------------------------------
#> phase            file_context   rule   n   attck
#> at_build         configure      curl   1   T1041 T1105
#> at_check         configure      curl   1   T1041 T1105
#> at_install_src   configure      curl   1   T1041 T1105
#> 
#> --- Errors ------------------------------------------------------------------
#> No exceptions were raised.
```
