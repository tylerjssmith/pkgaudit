# Audit an R source package tarball

Finds security-relevant file and code contexts, code patterns, and shell
and make matches for review before an R source package tarball is
trusted.

## Usage

``` r
audit_tarball(
  path,
  rules = load_rules(),
  temp_dir = tempdir(),
  max_entries = 100000L,
  max_bytes = 2 * 1024^3,
  max_ratio = 256
)
```

## Arguments

- path:

  Path to a gzip-compressed or uncompressed R source package tarball
  (`.tar.gz`, `.tgz`, or `.tar`). A bzip2-, xz-, zstd- or
  compress-compressed archive is refused by its magic bytes, whatever
  its filename says.

- rules:

  Named list of rules. Defaults to the rules bundled with the package as
  returned by
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md).

- temp_dir:

  Directory used for extraction. A unique subdirectory is created here
  and removed after auditing regardless of success or failure. Defaults
  to [`base::tempdir()`](https://rdrr.io/r/base/tempfile.html).

- max_entries:

  Maximum number of entries to read before failing closed. Default
  100,000.

- max_bytes:

  Maximum uncompressed bytes to read before failing closed. Default 2
  GB. Raise for ecosystems with larger artifacts, e.g. Bioconductor
  annotation and experiment-data packages.

- max_ratio:

  Maximum uncompressed:compressed ratio before failing closed, or `Inf`
  to disable. Targets decompression bombs, which are characterised by
  extreme ratios rather than absolute size. Default 256, well under the
  ~1032:1 ceiling of a single gzip layer.

## Value

The same `pkgaudit` object as
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md):
a named list with class `pkgaudit` containing five data frames and a
`metadata` list.

## Details

Extracts a source package tarball to a temporary directory, applies
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md),
removes the temporary directory, and returns the result.

Before extracting anything, the tarball is validated with
[`validate_tar()`](https://tylerjssmith.github.io/pkgaudit/reference/validate_tar.md),
which fails closed. After extraction, the extracted directory is
re-checked and rejected if it contains any symlink, as defense in depth
against a validate_tar()/untar() disagreement.

After extraction, the tarball filename must be consistent with the
top-level directory it produced (e.g. `foo_0.1.0.tar.gz` must extract to
`foo/`); otherwise the tarball is rejected.

The audited `DESCRIPTION` is then checked against the tarball filename:
if the `Package` name or `Version` disagrees with the name and version
implied by the filename (`foo` and `0.1.0` for `foo_0.1.0.tar.gz`), a
`pkgaudit_provenance_mismatch` warning is issued, which a caller can
catch by class. The `DESCRIPTION` values are authoritative and are what
the returned object reports.

## Examples

``` r
# untrustedpkg is a small package shipped with pkgaudit to be scanned.
tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)

result <- audit_tarball(tarball)
print(result)
#> --- pkgaudit ----------------------------------------------------------------
#> Package:   untrustedpkg v0.1.0 (source tarball)
#> Path:      ~/work/_temp/Library/pkgaudit/extdata/untrustedpkg/untrustedpkg_0.1.0.tar.gz
#> SHA-256:   0c58ddcb365787ab7401c5eedaa4be7eb4ce6bea0a5ca290b6b7b1d8eb621d44
#> Scanned:   2026-08-26 12:49 UTC with pkgaudit v0.4.0, rules v0.4.0
#> 
#> File contexts:  1
#> Patterns:       4
#> Matches:        1
#> Errors:         0
```
