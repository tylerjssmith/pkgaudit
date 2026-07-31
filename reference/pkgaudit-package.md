# pkgaudit: Static Analysis Security Testing (SAST) for R Packages

A static analysis security testing (SAST) tool for R packages. Flags
security-relevant files and code in R source packages for manual review.
Organizes results by R package lifecycle (build, check, install, load,
attach, unload, detach), using file-context, code-context, and pattern
rules stored in a versioned and hash-verified SQLite database.

## Details

The main entry points are
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
and
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md),
which scan a package source directory and tarball, respectively, and
return a
[`new_pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/new_pkgaudit.md)
object holding four result data frames (file_contexts, code_contexts,
patterns, errors) plus scan metadata. Its
[format()](https://tylerjssmith.github.io/pkgaudit/reference/format.pkgaudit.md)
and
[print()](https://tylerjssmith.github.io/pkgaudit/reference/format.pkgaudit.md)
methods render the metadata and finding counts.

## See also

[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
and
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
for the scan entry points;
[`print.pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/format.pkgaudit.md)
for the rendered summary.

## Author

**Maintainer**: Tyler Smith <tylerjssmith@gmail.com>

Authors:

- Tyler Smith <tylerjssmith@gmail.com>
