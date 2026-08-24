# Validate a source package tarball before extraction

Fail closed: refuse the whole archive rather than extracting a filtered
subset, so a partially-validated archive is never written to disk. This
is the check
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
runs before extracting an untrusted tarball.

## Usage

``` r
validate_tar(
  tarfile,
  max_entries = 100000L,
  max_bytes = 2 * 1024^3,
  max_ratio = 256
)
```

## Arguments

- tarfile:

  Path to a `.tar` or `.tar.gz` archive.

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

Invisibly, a data frame of the archive's entries with columns `name`,
`type`, `linkname`, and `size`.

## Details

Rejects link entries (symlink, hard link), non-standard typeflags (GNU
long-name, PAX), path traversal, absolute and drive-qualified paths,
paths containing backslashes or control characters, empty paths,
unparseable size fields, and archives that do not extract to exactly one
top-level directory. It also enforces the entry-count,
uncompressed-size, and expansion-ratio caps applied while reading
(`max_entries`, `max_bytes`, `max_ratio`). Reads gzip and uncompressed
tar only, judged by the file's magic bytes rather than its name: a
bzip2, xz, zstd or compress stream is refused whatever it is called.

A refusal is signaled as a `pkgaudit_invalid_tarball` condition (a
subclass of `error`), so it stops by default but can be caught by class.

## Examples

``` r
# Returns the archive's entries, or stops with a "Refusing archive" error if
# the tarball is malicious or malformed.
tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)

entries <- validate_tar(tarball)
entries
#>                             name type linkname size
#> 1         untrustedpkg/configure file            69
#> 2       untrustedpkg/DESCRIPTION file           150
#> 3              untrustedpkg/man/  dir             0
#> 4 untrustedpkg/man/fetch_data.Rd file           381
#> 5                untrustedpkg/R/  dir             0
#> 6         untrustedpkg/R/fetch.R file            65
#> 7           untrustedpkg/R/zzz.R file            63
```
