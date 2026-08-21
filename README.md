
<!-- README.md is generated from README.Rmd. Please edit README.Rmd. -->

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
`.onLoad()` runs on `library()`, that `\Sexpr{}` evaluates while a help
page is built, or that `configure` runs under `R CMD check`. pkgaudit
does this: it extracts R from wherever a package carries it, parses the
code for security-relevant patterns, and reports the lifecycle phases in
which each finding runs.

## Overview

pkgaudit identifies every file in a package that can contain code –
complete source files (e.g., `R/*.R`, `src/*.c`), and code carried
inside documentation (`man/*.Rd`) and vignettes (e.g.,
`vignettes/*.Rmd`) – and says what it made of each one:

- **parsed**: R is parsed for security-relevant patterns like `system()`
  and `httr::POST()` calls. This includes `.R` scripts in `R/`, `data/`,
  `demo/`, `exec/`, `tests/`, and `tools/`; examples and `\Sexpr{}`
  macros in `.Rd` files; R chunks in R Markdown, Quarto, Sweave, and
  R.rsp vignettes; and `inst/CITATION`, `.Rprofile`, and
  `src/install.libs.R`.
- **matched**: Shell scripts and Make-like files, if present, are
  matched against regular expressions for security-relevant commands
  like `curl`. This includes `configure`, `cleanup`, `src/Makevars`, and
  more. Matching is textual, so a `curl` in a comment reads the same as
  one in command position.
- **exportable**: C, C++, Fortran, Rust, Python, and JavaScript source
  files, and vignette chunks written in those languages, are not read,
  but `export_unscanned()` can write them out for tools like Semgrep,
  blank-padded so that a finding’s line number still points into the
  original file.
- **unexamined**: Files that may contain code but were not scanned, such
  as serialized `.rda` and `.rds` files, are reported as unexamined.
- **error**: If pkgaudit attempted to parse or grep a file but
  encountered an error, the file is reported as an error.

Coverage may not be complete. What pkgaudit offers is not completeness
but legibility: a clean result can be checked rather than trusted,
because the scan says what it did not cover.

Every finding carries the R package lifecycle phases in which it runs –
`at_autoconf`, `at_build`, `at_check`, `at_install_src`,
`at_install_bin`, `at_load`, `at_attach`, `at_unload`, `at_detach`, or
`none` – so code that executes on `library()` is distinguishable from
code that runs only when someone calls it.

A finding is not an accusation. `configure` scripts and calls to system
tools, for example, are often legitimate. pkgaudit helps to identify
what deserves reviewer attention, not what is malicious.

For why this matters, see [R Package
Security](https://tylerjssmith.github.io/pkgaudit/articles/security.html).
For the rule set, see [Rule
Coverage](https://tylerjssmith.github.io/pkgaudit/articles/rules.html).

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
#> Scanned:   2026-08-21 21:44 UTC with pkgaudit v0.4.0, rules v0.4.0
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

Four of `untrustedpkg`’s five findings run without anyone asking for
them. `.onLoad()` in `R/zzz.R` calls `system()`, so it runs on
`library()` – and at build, check, and source installation, each of
which loads the package. An `\Sexpr{}` macro in `man/fetch_data.Rd`
calls `httr::POST()` when the help page is rendered, at those same three
phases, and the `\examples{}` block in the same file calls
`download.file()`, which `R CMD check` runs. The `configure` script may
invoke `curl` at build, check, and source installation. The fifth
finding is the contrast that makes the rest legible: `download.file()`
in `R/fetch.R` sits in an ordinary function body, so it runs at no phase
at all, reported under `none`, because it executes only if someone calls
it.

Phases overlap – building a package with vignettes also installs and
loads it – so one occurrence is counted under every phase it runs in.
`path = FALSE` omits the local filesystem path from output that will be
shared.

Two functions carry a scan into other tools. `emit_sarif()` renders the
result as SARIF 2.1.0, which editors and code-scanning platforms read
directly. `export_unscanned()` writes the code pkgaudit cannot read into
a directory for a scanner that can. Both are covered in [Getting Started
with
pkgaudit](https://tylerjssmith.github.io/pkgaudit/articles/pkgaudit.html).

## Rule Database Integrity

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
`5fc1ec8e93232517679fb03df0f08020d844912e701615de7827666be2f6a7cd`

## Security

pkgaudit’s own security model, and how to report a vulnerability in it,
are in [SECURITY.md](.github/SECURITY.md). To propose or revise a rule,
see [CONTRIBUTING.md](.github/CONTRIBUTING.md).

## Citation

``` r
citation("pkgaudit")
```
