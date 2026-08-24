# List tar entries with type and link target

List tar entries with type and link target

## Usage

``` r
tar_entries(
  tarfile,
  max_entries = 100000L,
  max_bytes = 2 * 1024^3,
  max_ratio = 256,
  chunk = 1048576L
)
```

## Arguments

- tarfile:

  Path to a `.tar` or `.tar.gz` archive.

- max_entries:

  Maximum number of entries to read before failing closed. Default
  100,000.

- max_bytes:

  Maximum uncompressed bytes to read before failing closed. Default 2
  GB. Raise for ecosystems with larger artifacts, e.g. Bioconductor
  annotation and experiment-data packages.

- max_ratio:

  Maximum uncompressed:compressed ratio before failing closed, or `Inf`
  to disable. Targets decompression bombs, which are characterised by
  extreme ratios rather than absolute size. Default 256, well under the
  ~1032:1 ceiling of a single gzip layer.

- chunk:

  Bytes read per call when skipping entry data. Bounds peak allocation
  so a huge declared size cannot force one huge read.

## Value

A data frame with `name`, `type`, `linkname`, and `size`. `type` is one
of `"file"`, `"hardlink"`, `"symlink"`, `"dir"`, `"other"`.

## Details

`utils::untar(list = TRUE)` returns names only, so it cannot distinguish
a symlink entry from a regular file. This reads the tar headers directly
to recover each entry's typeflag and linkname, which are used to refuse
link entries before extracting an untrusted archive.

Reads headers only: entry data is skipped, never written to disk. Note
that reaching entry N's header still requires decompressing everything
before it. Reads gzip and uncompressed tar via
[`base::gzfile()`](https://rdrr.io/r/base/connections.html), which would
silently decompress bzip2, xz and zstd as well, so those streams – and
compress – are refused first, by magic bytes rather than filename. Only
gzip's ~1032:1 per-layer ceiling keeps `max_ratio` a meaningful
decompression-bomb bound; xz can compress far past it.
