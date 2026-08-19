# Render a scan as SARIF

Renders a `pkgaudit` object as a SARIF 2.1.0 document, the format code
scanning tools publish results in, so a scan can be read in an editor or
loaded by any SARIF consumer.

## Usage

``` r
emit_sarif(object, pretty = TRUE)
```

## Arguments

- object:

  A `pkgaudit` object.

- pretty:

  Logical; if `TRUE` (default) indent the JSON for reading.

## Value

A length-one character vector holding the SARIF document. Nothing is
written; [`writeLines()`](https://rdrr.io/r/base/writeLines.html) it
where you want it.

## Details

Every finding in `file_contexts`, `patterns` and `matches` becomes a
result, located by the path and, where there is one, the line and
column. Rule ids are namespaced by the kind of rule – `pattern/curl`,
`match/curl`, `file/configure` – because a rule name is unique only
within its kind.

`level` is `warning` for a pattern or match whose code executes during
at least one lifecycle phase, and `note` for everything else. That is a
mapping of pkgaudit's phase model onto SARIF's severity field, not a
severity judgement: pkgaudit does not rank findings, and the line it can
draw honestly is between code that runs on its own and code that runs
only when called.

A file context is always a `note`: it says a file exists and will
execute rather than making a claim about its code. Read it as pkgaudit
pointing at something it could only grep, not as a minor finding.

`partialFingerprints` identifies a finding by its rule, its file, the
code context it sits in, and the text of the line – not by line number,
which shifts whenever anything above it is edited. Two occurrences a
consumer could not otherwise tell apart are numbered, since a
fingerprint repeated within a run makes several findings read as one.
The `coverage` frame becomes the `artifacts` array, so a consumer can
see which files were never read, and `errors` become execution
notifications on the invocation.

Requires jsonlite, a suggested dependency, since only this function
needs a JSON writer.

## Examples

``` r
# untrustedpkg is a small package shipped with pkgaudit to be scanned.
tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)
result <- audit_tarball(tarball)

writeLines(emit_sarif(result), file.path(tempdir(), "pkgaudit.sarif"))
```
