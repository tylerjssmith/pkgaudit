
<!-- index.md is generated from index.Rmd. Please edit this file -->

# pkgaudit

[![R-CMD-check](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml)
[![test
coverage](https://raw.githubusercontent.com/tylerjssmith/pkgaudit/badges/coverage.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/coverage.yaml)
[![osv-scanner](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml)

pkgaudit is a static analysis security testing (SAST) tool for R
packages. It reports which parts of a package can execute, when they
execute, and what they do, so that an untrusted package can be reviewed
before it is installed and loaded. It never executes the code it scans.

## How a package is covered

pkgaudit accounts for every file it can identify as code, and says what
it made of each one:

- **parsed** – R, wherever a package carries it: `R/`, help-file
  examples and `\Sexpr{}` macros, vignettes in R Markdown, Quarto,
  Sweave and R.rsp, `data/`, `demo/`, `tests/`, `tools/`,
  `inst/CITATION`, `.Rprofile`. Matched against R’s parse tree.
- **matched** – shell scripts and Make-like files: `configure`,
  `cleanup`, `src/Makevars`. Matched as text, which is less precise – a
  match in a comment reads the same as one in a live command.
- **exportable** – C, C++, Fortran, Rust, Python, JavaScript, and
  vignette chunks in those languages. Not read, but `export_unscanned()`
  writes them out for a scanner that reads them, blank-padded so that a
  finding’s line number still points into the original file.
- **unexamined** – present and accounted for, but not read: serialized
  `.rda` and `.rds` objects, binaries, and files no rule claims.

Coverage is never complete, and is not meant to be. What the `coverage`
frame offers is not completeness but legibility: a clean result can be
checked rather than trusted, because the scan says what it did not look
at.

Every finding carries the R package lifecycle phases in which it runs –
`at_autoconf`, `at_build`, `at_check`, `at_install_src`,
`at_install_bin`, `at_load`, `at_attach`, `at_unload`, `at_detach` – so
code that executes on `library()` is distinguishable from code that runs
only when someone calls it.

A finding is not an accusation. Flagged files and code are often
legitimate: `configure` scripts exist for system-dependent
configuration, and many packages call system tools or download files for
good reason. pkgaudit identifies what deserves a reader’s attention, not
what is malicious.

For why this matters, see [R Package
Security](articles/r-package-security.html). For the rule set, see [Rule
Coverage](articles/rules.html).

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
#> Scanned:   2026-08-11 13:05 UTC with pkgaudit v0.4.0, rules v0.4.0
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
```

`untrustedpkg` has an `.onLoad()` hook containing a `system()` call,
which runs whenever the package is loaded; an ordinary function
containing `download.file()`, which runs at no phase because it runs
only when someone calls it; and a `configure` script containing `curl`,
which runs when the package is built, checked, or installed from source.
Code that runs without being asked deserves closer attention.

Phases overlap – building a package with vignettes also installs and
loads it – so one occurrence is counted under every phase it runs in.

`path = FALSE` omits the local filesystem path from output that will be
shared.

Two functions carry a scan into other tools. `emit_sarif()` renders the
result as SARIF 2.1.0, which editors and code-scanning platforms read
directly. `export_unscanned()` writes the code pkgaudit cannot read into
a directory for a scanner that can. Both are covered in [Getting Started
with pkgaudit](articles/pkgaudit.html).

## Database integrity

pkgaudit detects security-relevant files and code using a SQLite
database of rules shipped at `inst/db/rules.db`. `load_rules()` verifies
the database against its bundled `.sha256` sidecar on every call and
refuses to load a modified one. To check an installed copy against the
value published here:

``` r
digest::digest(
  system.file("db", "rules.db", package = "pkgaudit"),
  algo = "sha256",
  file = TRUE
)
```

Expected SHA-256:
`d4eb060421019e24d34e3aa9a375fa9ccbe838cc1c9410551528418a2f88a5c9`

## Security

pkgaudit’s own security model, and how to report a vulnerability in it,
are in
[SECURITY.md](https://github.com/tylerjssmith/pkgaudit/blob/master/.github/SECURITY.md).
To propose or revise a rule, see
[CONTRIBUTING.md](https://github.com/tylerjssmith/pkgaudit/blob/master/.github/CONTRIBUTING.md).
How pkgaudit works internally, for a reader auditing the source, is in
[Internals](articles/internals.html).
