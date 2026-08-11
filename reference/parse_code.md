# Parse R code into an XML parse tree

Parses R code with `parse(keep.source = TRUE)`, converts the parse data
to XML with
[`xmlparsedata::xml_parse_data()`](https://rdrr.io/pkg/xmlparsedata/man/xml_parse_data.html),
and reads it into an `xml_document` with
[`xml2::read_xml()`](http://xml2.r-lib.org/reference/read_xml.md). The
parse and the XML conversion-and-read are each wrapped in
[`tryCatch()`](https://rdrr.io/r/base/conditions.html) so malformed code
yields a recoverable error rather than aborting the audit.

## Usage

``` r
parse_code(lines)
```

## Arguments

- lines:

  Character vector of R source, one element per line, as returned by
  [`read_code()`](https://tylerjssmith.github.io/pkgaudit/reference/read_code.md).

## Value

A list with two elements:

- tree:

  The `xml_document` parse tree, or `NULL` on failure.

- error:

  `NULL` on success, or a character error message on failure.

## Details

Code is taken as text rather than read from a path so that one parser
serves both an R script, whose lines are the file itself, and a help
file, whose R code is extracted from `\examples{}` and `\Sexpr{}` by
[`extract_Rd_code()`](https://tylerjssmith.github.io/pkgaudit/reference/extract_Rd_code.md).

[`parse()`](https://rdrr.io/r/base/parse.html) numbers lines from the
start of what it is given, so a caller that keeps its lines aligned to
the file they came from gets source references pointing into the
original file with no further adjustment. Both readers do.
