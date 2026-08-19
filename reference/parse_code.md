# Parse R code into an XML parse tree

Parses R code with `parse(keep.source = TRUE)`, converts it to XML with
[`xmlparsedata::xml_parse_data()`](https://rdrr.io/pkg/xmlparsedata/man/xml_parse_data.html)
and reads it with
[`xml2::read_xml()`](http://xml2.r-lib.org/reference/read_xml.md). Each
step is wrapped so malformed code yields a recoverable error rather than
aborting the scan.

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

Code is taken as text, not a path, so one parser serves both an R script
and the code
[`read_Rd_code()`](https://tylerjssmith.github.io/pkgaudit/reference/read_Rd_code.md)
recovers from a help file.
[`parse()`](https://rdrr.io/r/base/parse.html) numbers lines from the
start of what it is given, so a caller whose lines stay aligned to the
source file gets source references pointing into it directly. Both
readers keep that alignment.
