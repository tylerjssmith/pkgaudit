
<!-- index.md is generated from index.Rmd. Please edit index.Rmd. -->

# pkgaudit

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

For why this matters, see [R Package Security](articles/security.html).
For the rule set, see [Rule Coverage](articles/rules.html).

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
#> Scanned:   2026-08-21 21:00 UTC with pkgaudit v0.4.0, rules v0.4.0
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
