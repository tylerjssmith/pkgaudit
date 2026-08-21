# pkgaudit: Static Analysis Security Testing (SAST) for R Packages

A static analysis tool that flags security-relevant files and code in R
source packages for human review without executing anything it scans.
Models package lifecycle execution semantics – it reports not just what
a package does, but when it runs, so code that executes on install or
load is distinguishable from code that runs only when called. Reads
every surface a package can execute, including 'configure' scripts,
help-file macros, and vignettes, and states what it could not read, so a
clean result can be checked rather than trusted. Detection rules are
data, shipped in a versioned and hash-verified 'SQLite' database.

## Details

The main entry points are
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
and
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md),
which scan a package source directory and tarball, respectively, and
return a
[`new_pkgaudit()`](https://tylerjssmith.github.io/pkgaudit/reference/new_pkgaudit.md)
object holding five result data frames (file_contexts, patterns,
matches, coverage, errors) plus scan metadata. Its
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
([ORCID](https://orcid.org/0000-0003-4692-2206))

Authors:

- Tyler Smith <tylerjssmith@gmail.com>
  ([ORCID](https://orcid.org/0000-0003-4692-2206))
