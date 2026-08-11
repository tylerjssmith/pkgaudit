# Extract the R code from an .Rd help file

Recovers the two kinds of R code an `.Rd` file can carry – the body of
`\examples{}` and the code inside `\Sexpr{}` macros – as text suitable
for `base::parse(text = )`.

## Usage

``` r
extract_Rd_code(path, macros = NULL)
```

## Arguments

- path:

  Path to a single `.Rd` file.

- macros:

  Rd macros to expand while parsing, as returned by
  [`tools::loadPkgRdMacros()`](https://rdrr.io/r/tools/loadRdMacros.html).
  Defaults to `NULL`, which parses the file alone.

## Value

A named list of three elements:

- examples:

  Length-one character string: the code from `\examples{}`.

- sexpr:

  Length-one character string: the code from every `\Sexpr{}` macro in
  the file, wherever it appears.

- error:

  `NULL` when the file parsed cleanly, otherwise a character message.
  Both code strings are `""` when the file was not read or could not be
  parsed at all, and may be *incomplete* when it parsed with a warning,
  so a non-`NULL` `error` means the extraction is not to be trusted as a
  full account of the file's code.

## Details

The two are returned separately because they run at different times.
`\examples{}` runs under `R CMD check` and when a user calls
[`example()`](https://rdrr.io/r/utils/example.html); `\Sexpr{}` runs
while the help page is built or installed, which is the earlier and less
visible of the two. Merging them would make that distinction
unrecoverable.

Both strings are *line-aligned*: line N of the returned text is line N
of the `.Rd` file, and everything else is blank padding. Parsing with
`parse(text = , keep.source = TRUE)` therefore yields source references
whose line and column numbers point straight into the original file,
with no offset table to carry around. Columns are preserved the same way
where the fragments allow it.

Code is recovered from
[`tools::parse_Rd()`](https://rdrr.io/r/tools/parse_Rd.html)'s parse
tree rather than by matching text, so brace nesting, `%` comments, and
the `\%` / `\\` / `\{` escapes are handled by R's own Rd parser. The
extracted text is real R code: an example written `cat("a\\nb")` in the
`.Rd` comes back as `cat("a\nb")`.

Inside `\examples{}`:

- `\dontrun{}`, `\donttest{}`, `\dontshow{}`, and `\testonly{}` are
  unwrapped and their contents included. Whether the code is reached is
  a question for the caller; all four are R code shipped in the package.

- `\dots` becomes `...`, so a call does not silently lose an argument.

- Rd comments (`%` to end of line) are dropped, as they are not R code
  and would not parse.

- An inline `\Sexpr{}` goes to the `sexpr` string and leaves a gap in
  the `examples` one, so `h(\Sexpr{2+2})` yields `h()` there.

User-defined Rd macros are expanded when `macros` is supplied, so a
`\Sexpr{}` reaching a page through a macro is recovered at the point of
use, with a source reference pointing at the page that used it. Without
`macros`, that code is invisible and each use records an `unknown macro`
warning. Scanning `man/macros/` directly would not help:
[`tools::parse_Rd()`](https://rdrr.io/r/tools/parse_Rd.html) returns a
`\newcommand` body as an opaque token, so the code inside it is not
reachable until the macro is expanded somewhere.

## Security considerations

Nothing here evaluates the code it extracts. R's Rd machinery separates
parsing from rendering:
[`tools::parse_Rd()`](https://rdrr.io/r/tools/parse_Rd.html) and
[`tools::loadPkgRdMacros()`](https://rdrr.io/r/tools/loadRdMacros.html)
only read, while the `tools::prepare_Rd()` and `tools::Rd2*()` family
evaluate `\Sexpr{}` as a matter of course. pkgaudit must never call the
latter, and a regression test asserts that a scan of a package whose Rd
code would write a marker file leaves no marker behind.

A help file is untrusted input like any other file under audit, so one
above the scanning limit is refused unread and reported through `error`,
rather than handed to
[`tools::parse_Rd()`](https://rdrr.io/r/tools/parse_Rd.html).

## Known limits

`\Sexpr[results=rd]` produces Rd that is itself parsed and may contain
further code; that second-order surface is not followed. No `stage`
option is consulted, so the `sexpr` string mixes build-, install-, and
render-time code together.

[`tools::parse_Rd()`](https://rdrr.io/r/tools/parse_Rd.html) recovers
from some malformed input with a warning rather than an error, returning
a truncated tree. Whatever was recovered is still returned, since
dropping it would lose real code, but the warning is reported in `error`
so that a partial extraction is never mistaken for a complete one.

The `examples` string is not guaranteed to parse. R never syntax-checks
`\dontrun{}`: [`tools::Rd2ex()`](https://rdrr.io/r/tools/Rd2HTML.html)
comments those lines out with `##D`, and `R CMD check` therefore never
sees them. Including that code, as this function does, exposes
`\dontrun{}` blocks that are not valid R – a stray bracket, a sentence
of prose, a mis-escaped backslash. Over a sample of 3081 `.Rd` files
from CRAN, 5 (0.16%) produced an `examples` string that would not parse,
every one of them for that reason; no `sexpr` string failed. Since the
two are each assembled whole, one broken `\dontrun{}` costs the valid
example code in the same file, which is worth weighing before this is
wired into a scan.
