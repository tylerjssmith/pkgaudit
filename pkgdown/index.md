
<!-- index.md is generated from index.Rmd. Please edit index.Rmd. -->

# pkgaudit

pkgaudit is a static analysis security testing (SAST) tool for R
packages. It reports which parts of a package can execute, when they
execute, and what they do, so that an untrusted package can be reviewed
before it is installed and loaded. pkgaudit never executes the code it
scans.

A general-purpose scanner can read R – Semgrep supports it
experimentally – but it reads files, not packages. Nothing tells it to
look for R inside a help file’s `\examples{}` block or an `\Sexpr{}`
macro, or inside a Sweave or R.rsp vignette; and nothing tells it that
`.onLoad()` runs on `library()`, that `\Sexpr{}` evaluates while a help
page is built, or that `configure` runs under `R CMD check`. pkgaudit
does both: it extracts R from wherever a package carries it, and reports
the lifecycle phases in which each finding runs.

A finding is not an accusation. `configure` scripts and calls to system
tools, for example, are often legitimate. pkgaudit helps to identify
what deserves reviewer attention, not what is malicious.

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
#> Scanned:   2026-08-12 16:06 UTC with pkgaudit v0.4.0, rules v0.4.0
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

Two functions carry a scan into other tools. `emit_sarif()` renders the
result as SARIF 2.1.0, which editors and code-scanning platforms read
directly. `export_unscanned()` writes the code pkgaudit cannot read into
a directory for a scanner that can. See [Getting Started with
pkgaudit](articles/pkgaudit.html) for details.

## Security

pkgaudit’s own security model, and how to report a vulnerability in it,
are in
[SECURITY.md](https://github.com/tylerjssmith/pkgaudit/blob/main/.github/SECURITY.md).
To propose or revise a rule, see
[CONTRIBUTING.md](https://github.com/tylerjssmith/pkgaudit/blob/main/.github/CONTRIBUTING.md).
How pkgaudit works internally, for a reader auditing the source, is in
[Internals](articles/internals.html).
