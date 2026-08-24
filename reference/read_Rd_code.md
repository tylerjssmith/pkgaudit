# Read the R code out of an .Rd help file

Recovers the R code an `.Rd` file carries – the body of `\examples{}`
and the code inside `\Sexpr{}` macros – as text suitable for
`base::parse(text = )`.

## Usage

``` r
read_Rd_code(path, macros = NULL)
```

## Arguments

- path:

  Path to a single `.Rd` file.

- macros:

  Rd macros to expand while parsing, as returned by
  [`tools::loadPkgRdMacros()`](https://rdrr.io/r/tools/loadRdMacros.html).
  Defaults to `NULL`, which parses the file alone and leaves code
  reaching the page through a user-defined macro invisible.

## Value

A named list:

- examples:

  Length-one character string: the code from `\examples{}`.

- guarded:

  Integer vector: the lines of `examples` sitting inside `\dontrun{}`,
  which no example run reaches.

- sexpr:

  Named list of three length-one strings – `build`, `install` and
  `render` – holding each `\Sexpr{}` macro's code by the stage it runs
  at. An unlabeled macro counts as `install`.

- error:

  `NULL` when the file parsed cleanly, otherwise a message. The code
  strings are `""` when nothing was read, and may be incomplete when the
  file parsed with a warning, so a non-`NULL` `error` means the
  extraction is not a full account of the file's code.

## Details

Examples and `\Sexpr` are returned separately, and `\Sexpr` by stage,
because they run at different times: examples under `R CMD check`, a
macro while the page is built, installed or rendered. Merging them would
lose that.

Every string is *line-aligned*: line N of the returned text is line N of
the `.Rd` file, and the rest is blank padding. Parsing with
`keep.source = TRUE` therefore yields source references pointing
straight into the original file, with no offset to apply.

Code is recovered from
[`tools::parse_Rd()`](https://rdrr.io/r/tools/parse_Rd.html)'s parse
tree rather than by matching text, so brace nesting, `%` comments and
the `\%` / `\\` / `\{` escapes are handled by R's own parser; an example
written `cat("a\\nb")` comes back as `cat("a\nb")`. Inside
`\examples{}`, `\dontrun{}` and its siblings are unwrapped and their
contents included – all four are code that ships – while Rd comments are
dropped and an inline `\Sexpr{}` moves to the `sexpr` string.

## Security considerations

Nothing here evaluates the code it extracts. R's Rd machinery separates
parsing from rendering:
[`tools::parse_Rd()`](https://rdrr.io/r/tools/parse_Rd.html) and
[`tools::loadPkgRdMacros()`](https://rdrr.io/r/tools/loadRdMacros.html)
only read, while the `tools::prepare_Rd()` and `tools::Rd2*()` family
evaluate `\Sexpr{}` as a matter of course. pkgaudit must never call the
latter, and a regression test asserts that scanning a package whose Rd
code would write a marker file leaves no marker behind.

A help file is untrusted input like any other, so one above the scanning
limit is refused unread and reported through `error`.

## Known limits

`\Sexpr[results=rd]` produces Rd that is itself parsed and may carry
further code; that second-order surface is not followed.

[`tools::parse_Rd()`](https://rdrr.io/r/tools/parse_Rd.html) recovers
from some malformed input with a warning and a truncated tree. Whatever
was recovered is still returned, since dropping it would lose real code,
and the warning is reported in `error`.

The `examples` string is not guaranteed to parse. R never syntax-checks
`\dontrun{}`, so including that code exposes blocks that are not valid
R. The string is assembled whole, so one broken `\dontrun{}` costs the
valid example code in the same file.
