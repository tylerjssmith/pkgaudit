# pkgaudit

[![R-CMD-check](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml)
[![osv-scanner](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml)

pkgaudit is a static analysis security testing (SAST) tool for R
packages. It scans R source packages for files that can execute
arbitrary commands during autoconf, builds, checks, and installations,
and for lifecycle hooks whose bodies run automatically when a namespace
is loaded, attached, unloaded, or detached. It also scans R source code
for security-relevant patterns like
[`system()`](https://rdrr.io/r/base/system.html) calls.

R packages are the primary mechanism for sharing R code. They are also
[potential attack
vectors](https://tylerjssmith.github.io/pkgaudit/articles/r-package-security.md).
pkgaudit helps you identify which parts of an untrusted package deserve
your attention before you install and load it.

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
`2139a0ff1cffcd922c6e290efd329909e277c2bd28a2ca325143da3f1b7f4aa7`

## Usage

The [Getting Started with
pkgaudit](https://tylerjssmith.github.io/pkgaudit/articles/pkgaudit.md)
and [How pkgaudit
Works](https://tylerjssmith.github.io/pkgaudit/articles/how-it-works.md)
vignettes document usage. The [Rule
Coverage](https://tylerjssmith.github.io/pkgaudit/articles/rules.md)
vignette documents the full rule set. The example below scans
`untrustedpkg`, a small package shipped with pkgaudit for demonstration:

``` r

library(pkgaudit)

tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)

rules  <- load_rules()
result <- audit_tarball(tarball, rules = rules)
```

[`summary.pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/summary.pkgaudit.md)
reports the file and code contexts found in untrustedpkg, and counts the
patterns found in each of them by the R package lifecycle phase in which
the code may execute (e.g., build, installation from source,
installation from binary, load). These phases can overlap (e.g., builds
test that a package can be installed from source and loaded), so a
pattern may be counted under more than one phase.

Below, we see that untrustedpkg includes a `configure` script, which is
used for system-dependent configuration but can execute arbitrary shell
commands. It also calls [`system()`](https://rdrr.io/r/base/system.html)
inside `.onLoad()`, which runs on
[`library(untrustedpkg)`](https://rdrr.io/r/base/library.html), and
[`download.file()`](https://rdrr.io/r/utils/download.file.html) inside
an ordinary function, which runs only if a user calls the parent
function and so belongs to no phase. Code that runs without being asked
deserves closer attention.

``` r

summary(result, path = FALSE)
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> SHA-256:   e15feb660e38860df47907e63a355406bf0a1d99355f92b354f5e8018ae6b386
#> Scanned:   2026-08-01 18:14 UTC with pkgaudit v0.3.0, rules v0.3.0
#> 
#> --- Contexts ----------------------------------------------------------------
#> file_context
#> configure
#> 
#> code_context
#> onLoad_base
#> 
#> --- Patterns ----------------------------------------------------------------
#> phase            code_context   rule            n   attck
#> at_build         onLoad_base    system          1   T1059.003 T1059.004
#> at_check         onLoad_base    system          1   T1059.003 T1059.004
#> at_install_src   onLoad_base    system          1   T1059.003 T1059.004
#> at_load          onLoad_base    system          1   T1059.003 T1059.004
#> none             Other          download_file   1   T1105
#> 
#> --- Errors ------------------------------------------------------------------
#> No exceptions were raised.
```
