# Find security-relevant patterns in a parsed script

Finds patterns – syntactic constructs of interest (e.g.,
[`system()`](https://rdrr.io/r/base/system.html), `eval(parse())`, an
outbound HTTP call).

## Usage

``` r
find_patterns(tree, pattern_rules, file_context)
```

## Arguments

- tree:

  The `xml_document` parse tree for one script (from
  [`parse_code()`](https://tylerjssmith.github.io/pkgaudit/reference/parse_code.md)).

- pattern_rules:

  Data frame of pattern rules (`rules$patterns` from
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)),
  with columns `name`, `xpath`, `message`, and `attck`.

- file_context:

  Package-root-relative path of the script, carried through for joining
  to the file-contexts table.

## Value

A list with two data frames:

- patterns:

  Data frame with columns `rule` (the matching rule's name),
  `file_context`, `line_number`, `column_number`, `message`, `attck`.
  Carries a `"nodes"` attribute holding the matched nodes aligned to the
  rows. The phase columns are not set here;
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
  attaches them from the code context each pattern is assigned.

- errors:

  Data frame with columns `step`, `file_context`, `rule`, `message`.

## Details

For each pattern rule, this function evaluates the rule's XPath against
the parse tree with `.xml_find_all_safe()`. Every matching node is a
pattern found. A failing or invalid XPath (including one that libxml2
reports only as a warning) comes back as a condition, which is recorded
in the errors data frame before the loop moves on to the next rule.

The returned data frame carries the matched XML nodes as a `"nodes"`
attribute, aligned row-for-row, so
[`determine_code_contexts()`](https://tylerjssmith.github.io/pkgaudit/reference/determine_code_contexts.md)
can test containment by node identity without re-running the pattern
XPaths.
