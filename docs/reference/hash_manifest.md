# Compute a manifest hash for a directory

Hashes a package manifest, a canonically ordered list of every included
file's relative path and SHA-256 content hash.

## Usage

``` r
hash_manifest(path, exclude = c("^\\.git/", "^\\.Rproj\\.user/"))
```

## Arguments

- path:

  Path to the directory to hash.

- exclude:

  Character vector of regular expressions matched against paths relative
  to `path`. Defaults exclude version-control and IDE scratch state,
  which are not part of the package and (for `.git/`) are large and
  volatile. Pass `character(0)` to hash everything present.

## Value

A list with:

- hash:

  SHA-256 of the manifest text (character scalar).

- manifest:

  The manifest text (character scalar), one line per file, formatted as
  `"<hash> <relative path>"`.

- n_files:

  Number of files included (integer).

- exclude:

  The exclusion patterns applied, for recording in metadata.

- symlinks:

  Relative paths of symlinks and files under symlinked directories,
  excluded from the manifest (character).

- unreadable:

  Relative paths that could not be hashed, excluded from the manifest
  (character).

## Details

Directories, unlike tarballs, have no single canonical byte stream to
hash. This function instead hashes a manifest: a canonically ordered
list of every included file's relative path and SHA-256 content hash.
The manifest is returned alongside the hash so that two disagreeing
scans can be diffed to identify which file differs.

A directory hash is a weaker provenance claim than a tarball hash,
because its scope depends on `exclude`: two directories that differ only
in excluded paths hash identically. The exclusion patterns are returned
so the caller can record them. Empty directories and symlinks are
likewise not represented in the manifest, so two trees differing only in
those also hash identically. For vetting untrusted code, prefer hashing
the tarball.

## Examples

``` r
if (FALSE) { # \dontrun{
hash_manifest("/path/to/package")$hash
} # }
```
