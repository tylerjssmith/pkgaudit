# Parse an R script into an XML parse tree

Parses a single R script with `parse(keep.source = TRUE)`, converts the
parse data to XML with
[`xmlparsedata::xml_parse_data()`](https://rdrr.io/pkg/xmlparsedata/man/xml_parse_data.html),
and reads it into an `xml_document` with
[`xml2::read_xml()`](http://xml2.r-lib.org/reference/read_xml.md). The
parse and the XML conversion-and-read are each wrapped in
[`tryCatch()`](https://rdrr.io/r/base/conditions.html) so a malformed or
unreadable script yields a recoverable error rather than aborting the
audit.

## Usage

``` r
parse_script(script)
```

## Arguments

- script:

  Path to a single R script.

## Value

A list with two elements:

- tree:

  The `xml_document` parse tree, or `NULL` on failure.

- error:

  `NULL` on success, or a character error message on failure.
