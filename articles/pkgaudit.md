# Getting Started with pkgaudit

pkgaudit scans R source packages for files that can execute arbitrary
commands during autoconf, builds, checks, and installations, and for
lifecycle hooks whose bodies run automatically when a namespace is
loaded, attached, unloaded, or detached. It also scans R source code for
security-relevant patterns like
[`system()`](https://rdrr.io/r/base/system.html) calls.

A finding is not an accusation. In many cases, flagged files and code
will be legitimate: files that can execute shell commands are needed for
system-dependent configuration, and many call system tools or download
files for good reason. pkgaudit helps you identify which parts of an
untrusted package should be reviewed before you install and load it.

``` r

library(pkgaudit)
```

## pkgaudit Rules

pkgaudit separates *when* code executes from *what* code does using
three rule categories:

- **File contexts** are files that can execute arbitrary commands during
  autoconf, builds, checks, and installations. These are primarily files
  involved in compiling non-R source code, such as `configure`,
  `src/Makevars`, and `src/Makefile`.
- **Code contexts** are lifecycle hooks whose bodies run automatically
  when a namespace is loaded, attached, unloaded, or detached, such as
  `.onLoad()` and `.onAttach()`.
- **Patterns** are security-relevant function calls.
  [`system()`](https://rdrr.io/r/base/system.html), for example, can
  execute arbitrary shell commands.
  [`source()`](https://rdrr.io/r/base/source.html) can fetch and execute
  a remote payload.

Every pattern finding is attributed to the code context that contains
it. A [`system()`](https://rdrr.io/r/base/system.html) call inside an
ordinary function only runs if you call that function; the same call
inside `.onLoad()` runs automatically when a namespace is loaded.

The full rule set is documented in [pkgaudit Rule
Coverage](https://tylerjssmith.github.io/pkgaudit/articles/rules.md).

## Rules and Database Integrity

The rules live in a versioned SQLite database shipped with the package.
[`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
reads it, and
[`rules_version()`](https://tylerjssmith.github.io/pkgaudit/reference/rules_version.md)
reports the version:

``` r

rules_version()
#> [1] "0.3.0"

rules <- load_rules()
nrow(rules$file_contexts)
#> [1] 16
nrow(rules$code_contexts)
#> [1] 6
nrow(rules$patterns)
#> [1] 18
nrow(rules$phases)
#> [1] 24
```

`phases` holds one row per context code can execute in: every file- and
code-context rule, plus `Top-level` and `Other`.

A modified database is one way to evade a scanner.
[`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
verifies the database against its bundled SHA-256 sidecar on every call
and refuses to load a modified one. You can also check the hash of your
installed copy against the value published in the
[README](https://github.com/tylerjssmith/pkgaudit#database-integrity):

``` r

digest::digest(
  system.file("db", "rules.db", package = "pkgaudit"),
  algo = "sha256",
  file = TRUE
)
#> [1] "2139a0ff1cffcd922c6e290efd329909e277c2bd28a2ca325143da3f1b7f4aa7"
```

## An Example Package

As a demonstration, we will scan `untrustedpkg`, a small source package
shipped with pkgaudit that does several things a reviewer would want to
know about. It is never built, checked, installed, or loaded; it exists
only to be scanned.

``` r

tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)

exdir <- file.path(tempdir(), "untrustedpkg-example")
utils::untar(tarball, exdir = exdir)

pkg <- file.path(exdir, "untrustedpkg")
list.files(pkg, recursive = TRUE)
#> [1] "configure"   "DESCRIPTION" "R/fetch.R"   "R/zzz.R"
```

Three of those files are worth reading before we scan them. A
`configure` script runs during installations from source, before any R
source code is loaded:

    #!/bin/sh
    echo configuring

`.onLoad()` runs automatically when the namespace is loaded, so its body
executes on
[`library(untrustedpkg)`](https://rdrr.io/r/base/library.html):

    .onLoad <- function(libname, pkgname) {
      system("uname -a")
    }

An ordinary function only runs if the user calls it:

    fetch_data <- function(url) {
      download.file(url, tempfile())
    }

The script that generates this package is in
[data-raw/create_untrustedpkg.R](https://github.com/tylerjssmith/pkgaudit/blob/master/data-raw/create_untrustedpkg.R).

## Auditing a Package Directory

[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
scans an unpacked source package:

``` r

result <- audit_package(pkg)
```

Printing the result gives the scan metadata and the number of findings
by category:

``` r

print(result)
#> --- pkgaudit ----------------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source directory)
#> Path:      /tmp/RtmpX24Vwz/untrustedpkg-example/untrustedpkg
#> SHA-256:   a78cd9f1541a5de58ad69ef084233609c324853b900efd7039e74d4cfe6152f5
#> Scanned:   2026-08-02 21:29 UTC with pkgaudit v0.3.0, rules v0.3.0
#> 
#> File contexts:  1
#> Code contexts:  1
#> Patterns:       2
#> Errors:         0
```

[`summary()`](https://rdrr.io/r/base/summary.html) reports the findings
themselves: which contexts were found, how often each pattern matched in
each context and lifecycle phase, and the MITRE ATT&CK techniques
involved.

``` r

summary(result)
#> --- pkgaudit Summary --------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source directory)
#> Path:      /tmp/RtmpX24Vwz/untrustedpkg-example/untrustedpkg
#> SHA-256:   a78cd9f1541a5de58ad69ef084233609c324853b900efd7039e74d4cfe6152f5
#> Scanned:   2026-08-02 21:29 UTC with pkgaudit v0.3.0, rules v0.3.0
#> 
#> --- Contexts ----------------------------------------------------------------
#> file_context
#> configure
#> 
#> code_context
#> onLoad_base
#> 
#> --- Patterns ----------------------------------------------------------------
#> phase            code_context   rule            n   attck
#> at_build         onLoad_base    system          1   T1059.003 T1059.004
#> at_check         onLoad_base    system          1   T1059.003 T1059.004
#> at_install_src   onLoad_base    system          1   T1059.003 T1059.004
#> at_load          onLoad_base    system          1   T1059.003 T1059.004
#> none             Other          download_file   1   T1105
#> 
#> --- Errors ------------------------------------------------------------------
#> No exceptions were raised.
```

Both methods accept `path = FALSE`, which omits the local filesystem
path from the output. This is useful when sharing results, since the
path may reveal a username or directory layout.

A `pkgaudit` object is a named list of ordinary data frames, so you can
filter, join, and report on the findings however you like. The columns
below are a subset: each frame also carries the rule’s `message`, too
long to print legibly and documented in [pkgaudit Rule
Coverage](https://tylerjssmith.github.io/pkgaudit/articles/rules.md),
the MITRE ATT&CK techniques in `attck`, and one logical column per
lifecycle phase.

``` r

result$patterns[, c("rule", "file_context", "code_context", "line_number",
                    "column_number")]
#>            rule file_context code_context line_number column_number
#> 1 download_file    R/fetch.R        Other           2             3
#> 2        system      R/zzz.R  onLoad_base           2             3
```

Each finding also records when its code runs, as one logical column per
phase: `at_autoconf`, `at_build`, `at_check`, `at_install_src`,
`at_install_bin`, `at_load`, `at_attach`, `at_unload`, and `at_detach`.
A pattern inside an ordinary function is `FALSE` for every one of them –
it runs only if something calls it – and is gathered under `none` by
[`summary()`](https://rdrr.io/r/base/summary.html).

``` r

result$patterns[result$patterns$at_load,
                c("rule", "file_context", "code_context")]
#>     rule file_context code_context
#> 2 system      R/zzz.R  onLoad_base
```

## Auditing a Tarball

The more common workflow is to scan a package you have not yet
installed.
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
takes a `.tar.gz` source package, validates it, extracts it to a
temporary directory, and scans the result.

This is the `untrustedpkg` tarball we extracted above, scanned directly:

``` r

audit_tarball(tarball)
#> --- pkgaudit ----------------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> Path:      /home/runner/.cache/R/renv/library/profiles/dev/renv/pkgaudit-f1939151/linux-ubuntu-noble/R-4.6/x86_64-pc-linux-gnu/pkgaudit/extdata/untrustedpkg/untrustedpkg_0.1.0.tar.gz
#> SHA-256:   e15feb660e38860df47907e63a355406bf0a1d99355f92b354f5e8018ae6b386
#> Scanned:   2026-08-02 21:29 UTC with pkgaudit v0.3.0, rules v0.3.0
#> 
#> File contexts:  1
#> Code contexts:  1
#> Patterns:       2
#> Errors:         0
```

Because an untrusted archive is itself an attack surface,
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
calls
[`validate_tar()`](https://tylerjssmith.github.io/pkgaudit/reference/validate_tar.md)
to check the tarball before its contents are extracted. This check fails
closed, refusing the whole archive, if it detects any link entry, path
traversal, absolute path, or malformed path or if the archive does not
extract to exactly one top-level directory. It also enforces limits on
entry count, uncompressed size, and compression ratio, guarding against
archives that expand to exhaust the disk.

``` r

str(validate_tar(tarball))
#> 'data.frame':    5 obs. of  4 variables:
#>  $ name    : chr  "untrustedpkg/configure" "untrustedpkg/DESCRIPTION" "untrustedpkg/R/" "untrustedpkg/R/fetch.R" ...
#>  $ type    : chr  "file" "file" "dir" "file" ...
#>  $ linkname: chr  "" "" "" "" ...
#>  $ size    : int  27 150 0 65 63
```

## Interpreting a Scan

A clean scan is weak evidence of safety: pkgaudit reasons about syntax,
so sufficiently indirect code can evade any pattern rule. A scan with
findings is better understood as a reading list than a verdict. In
review, the questions worth asking are roughly:

- Does the package need this capability at all, given what it claims to
  do?
- Does it run without being asked, at install or load time, rather than
  when a user calls a function?
- Does it reach the network, and if so, is the destination fixed and
  identifiable in the source?
- Is the code being run visible in the source, or is it assembled,
  decoded, or fetched at runtime?

Findings that answer badly on several of these at once are the ones to
read closely.
