# Describe how well every file in a package was read

Builds the `coverage` data frame: one row per file the package carries
that is, or could be, code, and one per code span where a file yields
several, recording whether pkgaudit parsed it, matched it as text, could
hand it to another tool, or did not examine it at all.

## Usage

``` r
build_coverage(
  path,
  found,
  file_context_rules,
  scanned = character(0L),
  errors = .empty_errors()
)
```

## Arguments

- path:

  Path to the package root.

- found:

  The `file_contexts` frame from
  [`find_file_contexts()`](https://tylerjssmith.github.io/pkgaudit/reference/find_file_contexts.md),
  carrying every rule match, reporting or not.

- file_context_rules:

  `rules$file_contexts` from
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md).

- scanned:

  Named character vector of the rule `type` each scanned file was read
  as, named by package-root-relative path. The type, not the extension,
  is what a scanned file's language comes from: `configure` has no
  extension but is read as shell.

- errors:

  The scan's `errors` frame, which is what identifies the files pkgaudit
  tried to read and could not.

## Value

A data frame with the columns
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
documents for `coverage`, without the phase columns;
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
attaches those.

## Security considerations

The frame is built by walking the tree rather than by asking the rules
what they matched, so a file in a location no rule anticipates still
gets a row. That is the point: an unknown-unknown becomes a
known-unknown, and a clean scan becomes falsifiable. What a name has to
say to earn a row is `.in_scope()`.

A symlink is recorded and never read.
[`list.files()`](https://rdrr.io/r/base/list.files.html) descends into
symlinked directories and a read would follow the link out of the
package, so every ancestor component is tested, as
[`hash_manifest()`](https://tylerjssmith.github.io/pkgaudit/reference/hash_manifest.md)
does.
