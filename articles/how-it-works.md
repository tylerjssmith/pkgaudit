# How pkgaudit Works

pkgaudit is a static analysis security testing (SAST) tool for R source
packages. It flags security-relevant files and R source code for manual
review, and organizes what it finds by the point in the R package
lifecycle at which the code runs (e.g., build, check, install, load).

This vignette explains how pkgaudit works. It is intended for anyone
considering whether to incorporate pkgaudit into their workflow and for
potential contributors. For information on how to contribute, see
[CONTRIBUTING.md](https://github.com/tylerjssmith/pkgaudit/blob/master/.github/CONTRIBUTING.md).

``` r

library(pkgaudit)
rules <- load_rules()
```

## Entry Points

pkgaudit has two entry points.
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
is used for source package directories.
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
is used for source package tarballs; it wraps
[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
and handles tarball validation and extraction, and the removal of
extracted files.

[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
orchestrates the following internal functions:

1.  [`find_file_contexts()`](https://tylerjssmith.github.io/pkgaudit/reference/find_file_contexts.md)
    determines what file contexts are present in the source package.

2.  [`find_scripts()`](https://tylerjssmith.github.io/pkgaudit/reference/find_scripts.md)
    finds all scripts in `R/`, `R/unix/`, and `R/windows/` with file
    extensions recognized by R’s build process (`.R`, `.r`, `.S`, `.s`,
    `.q`), as well as `src/install.libs.R`, if present.

3.  For each script:
    [`parse_script()`](https://tylerjssmith.github.io/pkgaudit/reference/parse_script.md)
    uses R’s [`parse()`](https://rdrr.io/r/base/parse.html) and the
    `xmlparsedata` and `xml2` packages to return an XML parse tree for
    the script.

    1.  For each code-context rule,
        [`find_code_contexts()`](https://tylerjssmith.github.io/pkgaudit/reference/find_code_contexts.md)
        finds XML nodes matching XPath-based definitions of code
        contexts.

    2.  For each pattern rule,
        [`find_patterns()`](https://tylerjssmith.github.io/pkgaudit/reference/find_patterns.md)
        finds XML nodes matching XPath-based definitions of patterns.

    3.  If any patterns were found,
        [`determine_code_contexts()`](https://tylerjssmith.github.io/pkgaudit/reference/determine_code_contexts.md)
        determines whether each pattern occurrence is located in a named
        code context, top-level code (`Top-level`), or a regular
        function (`Other`).

4.  Finally, the lifecycle phases in which each finding’s code runs are
    attached to the findings. A file or code context takes its phases
    from the rule that matched it; a pattern inherits them from the code
    context assigned in step 3c.

[`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md)
returns a `pkgaudit` object: a named list of `file_contexts`,
`code_contexts`, `patterns`, and `errors` data frames, plus a `metadata`
list recording what was scanned and with what. Each of the three
findings data frames carries one logical column per lifecycle phase.

Failures are contained rather than fatal. Listing files, parsing a
script, and evaluating an XPath are each wrapped in
[`tryCatch()`](https://rdrr.io/r/base/conditions.html), so an unreadable
file, a malformed script, or an invalid XPath is recorded as a row in
`errors` – giving the stage, file, rule, and message – and the scan
continues with the next script or rule.

## Rules

The remainder of this document explains each category of rule and how
the functions above are used to find the context or pattern it targets.

Rules are defined by YAML files that live under `inst/rules/`. For all
three categories, the YAML files have the following fields:

- `name` is the rule identifier and the value reported in a finding.
- `version` is the rule version, independent of the package version.
- `message` is the explanation shown with a finding.
- `positive_examples` and `negative_examples` are file paths or code
  syntax that should and should not be found by the rule, respectively.

File and code context rules carry nine further fields, one per lifecycle
phase – `at_autoconf`, `at_build`, `at_check`, `at_install_src`,
`at_install_bin`, `at_load`, `at_attach`, `at_unload`, and `at_detach` –
each `TRUE` or `FALSE`. Pattern rules do not declare them: a pattern
runs when the code around it runs, so it takes its phases from the code
context that contains it.

Each rule contains additional fields used by pkgaudit functions to find
file contexts, code contexts, or patterns. These are explained below.

The helper below prints a rule’s YAML, stopping before its examples,
which are discussed at the end.

``` r

show_rule <- function(category, file) {
  lines <- readLines(system.file("rules", category, file, package = "pkgaudit"))
  end   <- grep("^positive_examples:", lines)
  cat(lines[seq_len(if (length(end)) end[1] - 1L else length(lines))], sep = "\n")
}
```

### File Context Rules

A file context is a file that R executes at build-, check-, or
install-time, such as `configure` and `src/Makevars`. These files have
many legitimate uses but can execute arbitrary shell commands on a
system. The goal of a file context rule is to alert a user to the
existence of a file context before it is executed so that the file can
be reviewed.

In addition to the common fields and the nine phase fields, a file
context rule has four additional fields:

- `type` is the language or format of the file (e.g., `make`, `shell`,
  `R`).
- `path` is the directory to search (relative to the package root).
- `recursive` indicates whether to descend into subdirectories.
- `pattern` is a regular expression matched against the names of the
  files found at the file path (recursively, if `recursive: TRUE`).

[`find_file_contexts()`](https://tylerjssmith.github.io/pkgaudit/reference/find_file_contexts.md)
passes the `path`, `recursive`, and `pattern` values to
[`base::list.files()`](https://rdrr.io/r/base/list.files.html). For
example, the following rule is used to find `configure` in the package
root.

``` r
show_rule("file_contexts", "file_configure.yaml")
name: configure
version: "0.3.0"
type: shell
message: >-
  configure is a shell script used for system-dependent configuration when
  packages are installed from source, including the installs performed by
  R CMD check and by R CMD build when a package has vignettes. It can execute
  arbitrary shell commands.
at_autoconf: FALSE
at_build: TRUE
at_check: TRUE
at_install_src: TRUE
at_install_bin: FALSE
at_load: FALSE
at_attach: FALSE
at_unload: FALSE
at_detach: FALSE
path: "."
recursive: FALSE
pattern: '^configure$'
```

`"."` is the package root. `recursive: FALSE` means search only in the
package root, not subdirectories. `pattern` is anchored at both ends, so
`^configure$` matches `configure` exactly.

``` r

grepl("^configure$", c("configure", "configure.win", "reconfigure"))
#> [1]  TRUE FALSE FALSE
```

For this rule, these values are passed to
[`list.files()`](https://rdrr.io/r/base/list.files.html) as follows,
with `path` resolved against the root of the package being audited:

``` r

list.files(
  file.path(pkg, "."),
  pattern    = "^configure$",
  recursive  = FALSE,
  full.names = TRUE,
  all.files  = TRUE
)
```

All matches are findings. Here at most one file can match, since the
pattern is anchored and the search does not descend into subdirectories.
Related files such as `configure.win` and `configure.ucrt` have separate
rules rather than a shared pattern. Additionally, pkgaudit ignores
directories whose names happen to match; only regular files are found.

The YAML files are compiled into a SQLite database.
[`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md)
returns a list of four data frames: one per rule category, plus
`phases`. The `file_contexts` data frame contains the `path`,
`recursive`, and `pattern` values:

``` r

rules$file_contexts[
  rules$file_contexts$name == "configure",
  c("name", "path", "recursive", "pattern")
]
#>        name path recursive     pattern
#> 4 configure    .     FALSE ^configure$
```

The rule’s phase fields are hoisted into `phases`, keyed by rule name.
Here they say that `configure` runs during `R CMD build` and
`R CMD check` as well as at installation from source, and never once the
package is loaded:

``` r

rules$phases[
  rules$phases$context == "configure",
  c("context", "at_build", "at_check", "at_install_src", "at_load")
]
#>     context at_build at_check at_install_src at_load
#> 7 configure     TRUE     TRUE           TRUE   FALSE
```

### Code Context Rules

A code context is a lifecycle hook whose body can run automatically when
a namespace is loaded, attached, unloaded, or detached, such as
`.onLoad()` and `.onAttach()`. These contexts have many legitimate uses
but can execute arbitrary code on a system when a user installs or loads
a package, before the user has called any package functions. The goal of
a code context rule is to alert a user to the existence of a code
context before its contents are executed so that its body can be
reviewed.

For each script found by
[`find_scripts()`](https://tylerjssmith.github.io/pkgaudit/reference/find_scripts.md),
[`parse_script()`](https://tylerjssmith.github.io/pkgaudit/reference/parse_script.md)
returns an XML parse tree. As a simplified example, the helpers below
are used to parse a minimal example of `.onLoad()` and print its tree,
dropping the line and column attributes to keep the output readable.

``` r

as_xml <- function(code) {
  xml2::read_xml(
    xmlparsedata::xml_parse_data(
      parse(text = code, keep.source = TRUE)
    )
  )
}

show_tree <- function(code) {
  doc <- as_xml(code)
  for (node in xml2::xml_find_all(doc, "//*")) {
    for (attr in names(xml2::xml_attrs(node))) xml2::xml_attr(node, attr) <- NULL
  }
  cat(sub("^<\\?xml[^>]*\\?>\n", "", as.character(doc)))
}
```

``` r
show_tree(".onLoad <- function(libname, pkgname) NULL")
<exprlist>
  <expr>
    <expr>
      <SYMBOL>.onLoad</SYMBOL>
    </expr>
    <LEFT_ASSIGN>&lt;-</LEFT_ASSIGN>
    <expr>
      <FUNCTION>function</FUNCTION>
      <OP-LEFT-PAREN>(</OP-LEFT-PAREN>
      <SYMBOL_FORMALS>libname</SYMBOL_FORMALS>
      <OP-COMMA>,</OP-COMMA>
      <SYMBOL_FORMALS>pkgname</SYMBOL_FORMALS>
      <OP-RIGHT-PAREN>)</OP-RIGHT-PAREN>
      <expr>
        <NULL_CONST>NULL</NULL_CONST>
      </expr>
    </expr>
  </expr>
</exprlist>
```

In addition to the common fields and the nine phase fields, a code
context rule has two additional fields:

- `type` is the language of the code the context is written in (`R`).
- `xpath` is the XPath expression that defines the context.

``` r
show_rule("code_contexts", "code_onload.yaml")
name: onLoad_base
version: "0.3.0"
type: R
message: >-
  .onLoad() executes arbitrary code when a package namespace is loaded, e.g.,
  by calling library(), require(), or loadNamespace(), or by accessing the
  namespace with ::. R CMD INSTALL, R CMD build, and R CMD check all load the
  package, so .onLoad() runs during those phases without any call from a user.
at_autoconf: FALSE
at_build: TRUE
at_check: TRUE
at_install_src: TRUE
at_install_bin: FALSE
at_load: TRUE
at_attach: FALSE
at_unload: FALSE
at_detach: FALSE
xpath: >-
  (//expr | //expr_or_assign_or_help)[
    (
      (LEFT_ASSIGN or EQ_ASSIGN)
      and expr[1]/SYMBOL[text() = '.onLoad']
      and expr[FUNCTION]
    )
    or
    (
      RIGHT_ASSIGN
      and expr[2]/SYMBOL[text() = '.onLoad']
      and expr[1]//FUNCTION
    )
  ]
```

The XPath definition selects an expression node subject to two
alternative conditions. The first covers assignment with `<-` or `=`:
the left side must be the symbol `.onLoad`, and the right side must be a
function definition, which is what `expr[FUNCTION]` tests. The second
covers the same definition written backwards with `->`, where the symbol
and the function swap sides. Expressions are matched under two node
names because R wraps a top-level assignment made with `=` in an
`expr_or_assign_or_help` node rather than an `expr` node.

[`find_code_contexts()`](https://tylerjssmith.github.io/pkgaudit/reference/find_code_contexts.md)
takes the XML parse tree and XPath definition, and calls
`.xml_find_all_safe()`, which wraps
[`xml2::xml_find_all()`](http://xml2.r-lib.org/reference/xml_find_all.md),
to find XML nodes in the parse tree matching the definition. Every
matching node becomes a code-context finding recording the rule’s name
and the line and column where the hook begins.

Importantly, for the definition to match, a *function* must be assigned
to the name of the hook. The name of the hook merely appearing somewhere
is not a match. Below are some simple examples:

``` r

xpath   <- rules$code_contexts$xpath[rules$code_contexts$name == "onLoad_base"]
matches <- function(code) length(xml2::xml_find_all(as_xml(code), xpath)) > 0

matches(".onLoad <- function(libname, pkgname) NULL")    # assignment
#> [1] TRUE
matches(".onLoad = function(libname, pkgname) NULL")     # assignment with `=`
#> [1] TRUE
matches("(function(libname, pkgname) NULL) -> .onLoad")  # right assignment
#> [1] TRUE
matches(".onAttach <- function(libname, pkgname) NULL")  # a different hook
#> [1] FALSE
matches("message('.onLoad')")                            # only a mention
#> [1] FALSE
```

### Pattern Rules

A pattern is a security-relevant function call, such as
[`system()`](https://rdrr.io/r/base/system.html), which can execute
arbitrary shell commands. These functions have many legitimate uses. The
goal of a pattern rule is to alert a user to the existence of a function
call that should be reviewed.

In addition to the common fields, a pattern rule has three additional
fields:

- `type` is the language of the code the pattern matches (`R`).
- `xpath` is the XPath expression that defines the pattern.
- `attck` is a set of MITRE ATT&CK technique identifiers, carried into
  each finding and tallied by
  [`summary()`](https://rdrr.io/r/base/summary.html).

A pattern rule carries no severity. How much a finding deserves your
attention depends on the pattern together with the context it was found
in – the same [`system()`](https://rdrr.io/r/base/system.html) call is
weightier in `.onLoad()` than in a function nothing calls – and a rule
is evaluated without knowing which context it will land in.

As with code contexts,
[`find_patterns()`](https://tylerjssmith.github.io/pkgaudit/reference/find_patterns.md)
takes the XML parse tree and XPath definition, and calls
`.xml_find_all_safe()`, which wraps
[`xml2::xml_find_all()`](http://xml2.r-lib.org/reference/xml_find_all.md),
to find XML nodes in the parse tree matching the definition. Every
matching node becomes a pattern finding recording the rule’s name and
the line and column where the call begins.

As a simplified example, the XML parse tree for
[`system()`](https://rdrr.io/r/base/system.html) is:

``` r
show_tree("system()")
<exprlist>
  <expr>
    <expr>
      <SYMBOL_FUNCTION_CALL>system</SYMBOL_FUNCTION_CALL>
    </expr>
    <OP-LEFT-PAREN>(</OP-LEFT-PAREN>
    <OP-RIGHT-PAREN>)</OP-RIGHT-PAREN>
  </expr>
</exprlist>
```

The XPath definition of the pattern rule matching
[`system()`](https://rdrr.io/r/base/system.html) and similar function
calls is:

``` r
show_rule("patterns", "pattern_system.yaml")
name: system
version: "0.3.0"
type: R
attck:
  - T1059.003
  - T1059.004
message: >-
  system(), system2(), shell() (on Windows), and pipe() execute arbitrary shell
  commands.
xpath: >-
  //SYMBOL_FUNCTION_CALL[
    (text() = 'system' or text() = 'system2' or text() = 'shell'
      or text() = 'pipe')
    and not(preceding-sibling::OP-DOLLAR)
    and not(preceding-sibling::OP-AT)
  ]
```

There are two details in this XPath worth noting. The first is
`SYMBOL_FUNCTION_CALL`. R’s parser uses that label only where a name is
actually a function call; a mention of the same name anywhere else is a
plain `SYMBOL`, which will not match.

``` r
show_tree("foo <- system")
<exprlist>
  <expr>
    <expr>
      <SYMBOL>foo</SYMBOL>
    </expr>
    <LEFT_ASSIGN>&lt;-</LEFT_ASSIGN>
    <expr>
      <SYMBOL>system</SYMBOL>
    </expr>
  </expr>
</exprlist>
```

The second is the pair of `not(...)` conditions. In `foo$system("x")`,
the name is in call position, so the parser labels it
`SYMBOL_FUNCTION_CALL` – but it is a list element or an object’s method,
not base R’s [`system()`](https://rdrr.io/r/base/system.html). The rule
excludes it by refusing any call whose name is immediately preceded by
`$`:

``` r
show_tree('foo$system("x")')
<exprlist>
  <expr>
    <expr>
      <expr>
        <SYMBOL>foo</SYMBOL>
      </expr>
      <OP-DOLLAR>$</OP-DOLLAR>
      <SYMBOL_FUNCTION_CALL>system</SYMBOL_FUNCTION_CALL>
    </expr>
    <OP-LEFT-PAREN>(</OP-LEFT-PAREN>
    <expr>
      <STR_CONST>"x"</STR_CONST>
    </expr>
    <OP-RIGHT-PAREN>)</OP-RIGHT-PAREN>
  </expr>
</exprlist>
```

The `@` half of that pair is belt and braces. R’s parser labels the name
after `@` as a `SLOT` rather than a call, so `foo@system("x")` will not
match, but the condition is included as future-proofing.

``` r
show_tree('foo@system("x")')
<exprlist>
  <expr>
    <expr>
      <expr>
        <SYMBOL>foo</SYMBOL>
      </expr>
      <OP-AT>@</OP-AT>
      <SLOT>system</SLOT>
    </expr>
    <OP-LEFT-PAREN>(</OP-LEFT-PAREN>
    <expr>
      <STR_CONST>"x"</STR_CONST>
    </expr>
    <OP-RIGHT-PAREN>)</OP-RIGHT-PAREN>
  </expr>
</exprlist>
```

The following shows examples of what does and does not match:

``` r

xpath_sys <- rules$patterns$xpath[rules$patterns$name == "system"]
hits <- function(code) length(xml2::xml_find_all(as_xml(code), xpath_sys)) > 0

hits('system("id")')
#> [1] TRUE
hits('base::system("id")')   # a qualified call still matches
#> [1] TRUE
hits('pipe("id")')           # one of the four names the rule covers
#> [1] TRUE
hits("foo <- system")        # a reference, not a call
#> [1] FALSE
hits('foo$system("id")')     # a different function
#> [1] FALSE
```

`base::system("id")` still matches because the name is preceded by the
package qualifier (`::`), not by `$` or `@`. Detecting both call forms
is why the rule tests for the exclusions rather than requiring the call
to stand alone.

## Putting Them Together

[`determine_code_contexts()`](https://tylerjssmith.github.io/pkgaudit/reference/determine_code_contexts.md)
re-evaluates the code context XPath definitions against the XML parse
tree and compares the resulting nodes with the pattern nodes already
found, assigning each pattern the most specific code context that
contains it. A pattern at the top level of a script is assigned
`Top-level`, and a pattern inside a regular function is assigned
`Other`.

That assignment is also what gives a pattern its phases. `Top-level` and
`Other` are computed rather than matched by a rule, so they have no rule
to take phases from; theirs are authored separately, under
`inst/rules/phases/`. Top-level code is evaluated once, when the
lazy-load database is built during installation from source, so
`Top-level` carries the build, check, and source-install phases. `Other`
carries none at all, which is the reading intended: code inside an
ordinary function runs only if something calls it, never as a
consequence of building, installing, checking, or loading the package.

## Examples Are Tests

Every rule YAML ends with `positive_examples` and `negative_examples`.

``` r

lines <- readLines(
  system.file("rules", "file_contexts", "file_configure.yaml",
    package = "pkgaudit")
)
cat(lines[grep("^positive_examples:", lines):length(lines)], sep = "\n")
positive_examples:
  - configure
negative_examples:
  - configure.win
  - tools/configure
  - reconfigure
```

Every example is written out as a test fixture, and the pkgaudit test
suite requires that every positive example is flagged by its rule and
that no negative example is. A rule whose examples do not behave as
written fails the suite, so the examples stay accurate as rules change.

The full rule set is documented in [pkgaudit Rule
Coverage](https://tylerjssmith.github.io/pkgaudit/articles/rules.md),
and the rules themselves live under
[inst/rules/](https://github.com/tylerjssmith/pkgaudit/tree/master/inst/rules).
