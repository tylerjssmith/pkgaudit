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
  [`parse_script()`](https://tylerjssmith.github.io/pkgaudit/reference/parse_script.md)).

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

  Data frame with columns `stage`, `file_context`, `rule`, `message`.

## Details

For each code-context rule, this function evaluates the rule's XPath
against the parse tree with `.xml_find_all_safe()`. Every matching node
is a code context found. A failing or invalid XPath (including one that
libxml2 reports only as a warning) comes back as a condition, which is
recorded in the errors data frame before the loop moves on to the next
rule.
