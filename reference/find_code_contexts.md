# Find security-relevant code contexts in a parsed script

Finds code contexts – top-level code or lifecycle hooks (e.g.,
`.onLoad`, `.onAttach`, `.onUnload`, `.onDetach`, `.Last.lib`,
[`rlang::on_load`](https://rlang.r-lib.org/reference/on_load.html))
whose bodies execute when a package namespace is loaded, attached,
unloaded, or detached.

## Usage

``` r
find_code_contexts(tree, code_context_rules, file_context)
```

## Arguments

- tree:

  The `xml_document` parse tree for one script (from
  [`parse_code()`](https://tylerjssmith.github.io/pkgaudit/reference/parse_code.md)).

- code_context_rules:

  Data frame of code-context rules (`rules$code_contexts` from
  [`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)),
  with columns `name`, `xpath`, and `message`.

- file_context:

  Package-root-relative path of the script, carried through for joining
  to the file-contexts table.

## Value

A list with two data frames:

- code_contexts:

  Data frame with columns `rule` (the matching rule's name),
  `file_context`, `line_number`, `column_number`, `message`. The phase
  columns are not set here;
  [`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
  attaches them from the rules database.

- errors:

  Data frame with columns `step`, `file_context`, `rule`, `message`.

## Details

Each rule's XPath is evaluated with `.xml_find_all_safe()`, so an
invalid one – including one libxml2 reports only as a warning – is
recorded in `errors` and the scan moves on.
