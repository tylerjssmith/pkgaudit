# Export the code pkgaudit could not read

Writes the parts of a package that pkgaudit does not analyse – C, C++,
Fortran, Rust, Python, JavaScript, and the vignette chunks written in
them – into a directory another static analyser can be pointed at.

## Usage

``` r
export_unscanned(
  object,
  dir,
  source = NULL,
  overwrite = FALSE,
  max_bytes = .max_export_bytes
)
```

## Arguments

- object:

  A `pkgaudit` object.

- dir:

  Directory to write into. Required, and created if absent. Naming it is
  how the caller consents to being written to, so there is no default.

- source:

  The package to read from. Defaults to `object$metadata$pkg_path`,
  which is right for a directory scan. A tarball scan must supply this:
  the directory it was extracted into is gone by the time the scan
  returns.

- overwrite:

  Logical; if `FALSE` (default), `dir` must be absent or empty and an
  existing file is left alone. `TRUE` allows writing into a directory
  that already holds something and replaces a previous export of the
  same file. Nothing is ever deleted either way.

- max_bytes:

  Largest file to copy, in bytes; defaults to 64 MB. A larger one is
  recorded in the manifest and left behind. This is a separate limit
  from the 10 MB one
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
  scans under: copying a file costs far less than parsing it.

## Value

Invisibly, a manifest data frame with one row per exportable span:
`path` (relative to `dir`, `NA` if not written), `file_context`,
`language`, `first_line`, `last_line`, `written`, and `note`.

## Details

A whole file is copied verbatim. A span – a vignette chunk in a language
with no analyser – is written into a file of its own, blank-padded so
its code sits at the same line numbers it occupies in the source. A
finding another tool reports at line 40 of `intro.python.py` is
therefore at line 40 of `intro.Rmd`, with no offset to apply. All spans
of one language in one source share a file, since that is how they run.

What gets exported is read from the `coverage` frame, so the scan's own
account of what it could not read is the single source of truth.

## Security considerations

This is the only function in pkgaudit that writes, and both the content
and the file names come from an untrusted package. Therefore:

- every target path is resolved and must lie under `dir`;

- a path component that is `.`, `..`, or that contains a separator or a
  NUL byte is refused;

- symlinks are never followed, and content is read and rewritten rather
  than copied, so a link pointing out of the package cannot pull a file
  in;

- nothing is written executable, and nothing is removed.

A refused span is recorded in the manifest rather than dropped, since a
file that cannot be exported safely is one worth knowing about.
Exporting still executes nothing.

## Examples

``` r
# untrustedpkg is a small package shipped with pkgaudit to be scanned. It is
# R and shell throughout, so there is nothing to hand on and the manifest
# comes back empty; a package carrying compiled code yields one row per
# exported file.
tarball <- system.file(
  "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
  package = "pkgaudit"
)
exdir <- file.path(tempdir(), "untrustedpkg-example")
utils::untar(tarball, exdir = exdir)

result   <- audit_package(file.path(exdir, "untrustedpkg"))
manifest <- export_unscanned(result, file.path(tempdir(), "for-semgrep"))
nrow(manifest)
#> [1] 0
```
