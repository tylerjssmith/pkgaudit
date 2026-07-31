
<!-- index.md is generated from index.Rmd. Please edit this file -->

# pkgaudit

[![R-CMD-check](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml)
[![osv-scanner](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml)

pkgaudit is a static analysis security testing (SAST) tool for R
packages. It scans R source packages for files that can execute
arbitrary commands during autoconf, builds, checks, and installations,
and for lifecycle hooks whose bodies run automatically when a namespace
is loaded, attached, unloaded, or detached. It also scans R source code
for security-relevant patterns like `system()` calls.

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
database of rules shipped with the package at `inst/db/rules.db`. The
[Rule Coverage](articles/rules.html) vignette documents the full rule
set. To verify that your installed copy of the database has not been
modified since publication, check its SHA-256 hash against the value
published here.

``` r
digest::digest(
  system.file("db", "rules.db", package = "pkgaudit"),
  algo = "sha256",
  file = TRUE
)
```

Expected SHA-256:
`f37e40d5d1b248c44ab071ca19914f4e45be101eb66353af1b2bec9fb0350850`

## Usage

The [Getting Started with pkgaudit](articles/pkgaudit.html) and [How
pkgaudit Works](articles/how-it-works.html) vignettes document usage.
The example below scans `untrustedpkg`, a small package shipped with
pkgaudit for demonstration:

``` r
library(pkgaudit)

tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)

rules  <- load_rules()
result <- audit_tarball(tarball, rules = rules)
```

`summary()` reports the file contexts, code contexts, and patterns
found, and counts them by the R package lifecycle phase in which the
file or code may execute (e.g., build, check, source installation,
binary installation, load). These phases can overlap (for example,
builds and checks test that a package can be installed and loaded), so
the same findings may be associated with more than one phase below.

Below, we see that untrustedpkg includes a `configure` script, which is
used for system-dependent configuration but can execute arbitrary shell
commands. It also calls `system()` inside `.onLoad()`, which runs on
`library(untrustedpkg)`, and `download.file()` inside an ordinary
function, which runs only if a user calls it and so belongs to no phase.
Code that runs without being asked is the stronger claim on a reviewer’s
attention.

``` r
summary(result, path = FALSE)
#> --- pkgaudit Summary -----------------------------------------------------------
#> Package:        untrustedpkg v0.1.0 (source tarball)
#> SHA-256:        e15feb660e38860df47907e63a355406bf0a1d99355f92b354f5e8018ae6b386
#> Scanned:        2026-07-31 23:03 UTC with pkgaudit 0.3.0, rules v0.3.0
#> 
#> --- Findings by Phase ----------------------------------------------------------
#> phase          file_contexts code_contexts patterns
#> at_autoconf                0             0        0
#> at_build                   1             1        1
#> at_check                   1             1        1
#> at_install_src             1             1        1
#> at_install_bin             0             0        0
#> on_load                    0             1        1
#> on_attach                  0             0        0
#> on_unload                  0             0        0
#> on_detach                  0             0        0
#> none                       0             0        1
#> 
#> --- File Contexts --------------------------------------------------------------
#> file_context
#> configure
#> 
#> --- Code Contexts --------------------------------------------------------------
#> rule
#> onload_code
#> 
#> --- Patterns -------------------------------------------------------------------
#> rule                  occurrences attck
#> download_file_pattern           1 T1105 T1195.002
#> system_pattern                  1 T1059.003 T1059.004 T1195.002
#> 
#> --- Errors ---------------------------------------------------------------------
#> All R scripts were successfully parsed.
#> 
#> --- Notes ----------------------------------------------------------------------
#> pkgaudit is intended to assist with manual review, not replace it.
```
