# Read a file context as lines

Reads a file being audited into the character vector its analyzers work
on.

## Usage

``` r
read_code(path)
```

## Arguments

- path:

  Absolute path to the file to read.

## Value

A list with two elements:

- lines:

  Character vector of lines, or `NULL` when the file could not be read.

- error:

  `NULL` when the whole file was read, otherwise a character message. A
  message with `lines` present means the file was read but part of it
  could not be scanned.

## Security considerations

A file being audited is untrusted input, so two limits are enforced. A
file larger than 10 MB is not read at all: reading an arbitrarily large
file into memory would let a malformed or hostile package exhaust the
auditing machine. Lines that are not valid UTF-8 are replaced with an
empty line rather than dropped, since dropping them would shift the line
numbers of everything after them, and matching against them would fail
for the whole file.

Both cases are reported through `error`, so the scan records the
coverage it lost instead of reporting a clean read of a file it never
fully examined.
