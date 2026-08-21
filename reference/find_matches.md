# Find security-relevant matches in a shell script or Make-like file

Finds matches – regular-expression matches in a file R executes through
a shell or through make (e.g., `configure`, `src/Makevars`).

## Usage

``` r
find_matches(lines, match_rules, file_context)
```

## Arguments

- lines:

  Character vector of the file's lines, as returned by
  [`read_code()`](https://tylerjssmith.github.io/pkgaudit/reference/read_code.md).

- match_rules:

  Data frame of match rules (`rules$matches` from
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)),
  with columns `name`, `regex`, `message`, and `attck`.

- file_context:

  Package-root-relative path of the file, carried through for joining to
  the file-contexts table.

## Value

A list with two data frames:

- matches:

  Data frame with columns `rule` (the matching rule's name),
  `file_context`, `line_number`, `column_number`, `message`, `attck`.
  The phase columns are not set here;
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
  attaches them from the file context the file belongs to.

- errors:

  Data frame with columns `step`, `file_context`, `rule`, `message`.

## Details

Each rule's regular expression is evaluated against every line with
`base::gregexpr(perl = TRUE)`, case-sensitively; a line matched more
than once yields one row per match. A failing expression is recorded in
`errors` and the scan moves on.

Matching text is less precise than matching a parse tree: a match has no
syntax behind it, so one inside a comment, a quoted string, or a branch
that never runs is reported the same as a live command. Findings are
candidates for review, not confirmed behavior.

Reading the file, and the limits protecting against hostile input, are
[`read_code()`](https://tylerjssmith.github.io/pkgaudit/reference/read_code.md)'s
responsibility.
