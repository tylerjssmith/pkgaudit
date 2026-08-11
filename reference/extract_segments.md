# Read one source file into the code segments it contains

Dispatches on the file-context rule's `type`, which is the only place a
new variety of file is named.

## Usage

``` r
extract_segments(source)
```

## Arguments

- source:

  A `pkgaudit_source` from `new_source()`.

## Value

A list of two elements:

- segments:

  List of segments from `new_segment()`, each holding `lines` aligned to
  the lines of the source file.

- errors:

  Data frame with columns `step`, `file_context`, `rule`, `message`.

## Security considerations

The scanning size limit is enforced here, before dispatch, so no method
can skip it. A method must not re-implement it.
