# Tar header inspection and fail-closed validation for untrusted source package
# tarballs.

# The caps and refusals below come from a survey of every CRAN source package as
# of 7 July 2026 (n = 24,216); see dev/cran_survey/. Not one archive
# carried a link entry, a non-standard typeflag, a traversal, absolute,
# backslash, control-character or empty path, an unparseable size, or more than
# one top-level directory, so refusing all of them rejects no legitimate
# package. The maxima observed were 13,624 entries, ~140 MB uncompressed and an
# ~85:1 expansion ratio. Bioconductor was not surveyed and may differ.

#' Validate a source package tarball before extraction
#'
#' Fail closed: refuse the whole archive rather than extracting a filtered
#' subset, so a partially-validated archive is never written to disk. This is
#' the check [audit_tarball()] runs before extracting an untrusted tarball.
#'
#' Rejects link entries (symlink, hard link), non-standard typeflags (GNU
#' long-name, PAX), path traversal, absolute and drive-qualified paths, paths
#' containing backslashes or control characters, empty paths, unparseable size
#' fields, and archives that do not extract to exactly one top-level directory.
#' It also enforces the entry-count, uncompressed-size, and expansion-ratio caps
#' applied while reading (`max_entries`, `max_bytes`, `max_ratio`). No CRAN
#' source tarball trips any of these. Reads gzip and uncompressed tar only,
#' judged by the file's magic bytes rather than its name: a bzip2, xz, zstd or
#' compress stream is refused whatever it is called.
#'
#' A refusal is signaled as a `pkgaudit_invalid_tarball` condition (a subclass
#' of `error`), so it stops by default but can be caught by class.
#'
#' @inheritParams tar_entries
#' @return Invisibly, a data frame of the archive's entries with columns
#'   `name`, `type`, `linkname`, and `size`.
#'
#' @examples
#' # Returns the archive's entries, or stops with a "Refusing archive" error if
#' # the tarball is malicious or malformed.
#' tarball <- system.file(
#'   "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
#'   package = "pkgaudit"
#' )
#'
#' entries <- validate_tar(tarball)
#' entries
#'
#' @export
validate_tar <- function(tarfile,
                         max_entries = 100000L,
                         max_bytes   = 2 * 1024^3,
                         max_ratio   = 256) {

  e <- tar_entries(tarfile,
                   max_entries = max_entries,
                   max_bytes   = max_bytes,
                   max_ratio   = max_ratio)

  parts <- strsplit(e$name, "/", fixed = TRUE)

  bad_type  <- e$type %in% c("symlink", "hardlink", "other")
  traversal <- vapply(parts, function(p) any(p == ".."), logical(1))
  absolute  <- grepl("^/", e$name) | grepl("^[A-Za-z]:", e$name)
  # Backslashes are not path separators in tar, so a name containing one would
  # be a literal character here but a separator on Windows.
  backslash <- grepl("\\\\", e$name)
  # Control characters and newlines in a path are never legitimate and can
  # corrupt logs or terminal output.
  control   <- grepl("[[:cntrl:]]", e$name)
  empty     <- !nzchar(e$name)

  toplevel  <- unique(vapply(parts, function(p) {
    p <- p[nzchar(p)]
    if (length(p) == 0L) NA_character_ else p[1L]
  }, character(1)))
  toplevel  <- toplevel[!is.na(toplevel)]

  problems <- c(
    if (any(bad_type))  paste0(sum(bad_type),  " link or non-standard entries"),
    if (any(traversal)) paste0(sum(traversal), " traversal paths"),
    if (any(absolute))  paste0(sum(absolute),  " absolute paths"),
    if (any(backslash)) paste0(sum(backslash), " paths containing backslashes"),
    if (any(control))   paste0(sum(control),   " paths containing control characters"),
    if (any(empty))     paste0(sum(empty),     " empty paths"),
    if (length(toplevel) != 1L)
      paste0(length(toplevel), " top-level directories (expected 1)")
  )

  if (length(problems) > 0L) {
    .refuse_tar("Refusing archive '", basename(tarfile), "': ",
                paste(problems, collapse = "; "), ".")
  }

  invisible(e)
}


#' List tar entries with type and link target
#'
#' @param tarfile Path to a `.tar` or `.tar.gz` archive.
#' @param max_entries Maximum number of entries to read before failing closed.
#'   Default 100,000 (about 7x the largest CRAN package).
#' @param max_bytes Maximum uncompressed bytes to read before failing closed.
#'   Default 2 GB (about 15x the largest CRAN package). Raise for ecosystems
#'   with larger artifacts, e.g. Bioconductor annotation and experiment-data
#'   packages.
#' @param max_ratio Maximum uncompressed:compressed ratio before failing closed,
#'   or `Inf` to disable. Targets decompression bombs, which are characterised
#'   by extreme ratios rather than absolute size. Default 256: about 3x the
#'   largest ratio (85) observed across CRAN, and well under the ~1032:1 ceiling
#'   of a single gzip layer.
#' @param chunk Bytes read per call when skipping entry data. Bounds peak
#'   allocation so a huge declared size cannot force one huge read.
#'
#' @return A data frame with `name`, `type`, `linkname`, and `size`. `type` is
#'   one of `"file"`, `"hardlink"`, `"symlink"`, `"dir"`, `"other"`.
#'
#' @details
#' `utils::untar(list = TRUE)` returns names only, so it cannot distinguish a
#' symlink entry from a regular file. This reads the tar headers directly to
#' recover each entry's typeflag and linkname, which are used to refuse link
#' entries before extracting an untrusted archive.
#'
#' Reads headers only: entry data is skipped, never written to disk. Note that
#' reaching entry N's header still requires decompressing everything before it.
#' Reads gzip and uncompressed tar via [base::gzfile()], which would silently
#' decompress bzip2, xz and zstd as well, so those streams -- and compress --
#' are refused first, by magic bytes rather than filename. Only gzip's ~1032:1
#' per-layer ceiling keeps `max_ratio` a meaningful decompression-bomb bound;
#' xz can compress far past it.
#'
#' @keywords internal
tar_entries <- function(tarfile,
                        max_entries = 100000L,
                        max_bytes   = 2 * 1024^3,
                        max_ratio   = 256,
                        chunk       = 1048576L) {

  stopifnot(is.character(tarfile), length(tarfile) == 1L, file.exists(tarfile))
  stopifnot(is.numeric(max_entries), length(max_entries) == 1L, max_entries > 0)
  stopifnot(is.numeric(max_bytes), length(max_bytes) == 1L, max_bytes > 0)
  stopifnot(is.numeric(max_ratio), length(max_ratio) == 1L, max_ratio > 0)
  stopifnot(is.numeric(chunk), length(chunk) == 1L, chunk > 0)

  .check_tar_magic(tarfile)

  compressed <- file.size(tarfile)

  con <- gzfile(tarfile, open = "rb")
  on.exit(close(con), add = TRUE)

  out   <- list()
  bytes <- 0

  repeat {
    hdr <- readBin(con, "raw", 512L)
    # A well-formed archive ends with zero blocks. Running out of data instead
    # means the archive is truncated relative to its own headers; treat that as
    # untrusted rather than returning a partial listing.
    if (length(hdr) < 512L) {
      .refuse_tar("Refusing archive: truncated (incomplete header block).")
    }
    bytes <- bytes + 512
    if (all(hdr == as.raw(0))) break            # end-of-archive

    fld <- function(off, len) {
      raw <- hdr[(off + 1L):(off + len)]
      raw <- raw[raw != as.raw(0)]              # strips NULs before conversion
      trimws(rawToChar(raw))
    }

    name     <- fld(0L,   100L)
    size_oct <- fld(124L,  12L)
    linkname <- fld(157L, 100L)
    prefix   <- fld(345L, 155L)                 # ustar long-path prefix
    # Join with "/" rather than file.path(): the tar format is always
    # "/"-separated regardless of the host platform.
    if (nzchar(prefix)) name <- paste0(prefix, "/", name)

    size <- suppressWarnings(strtoi(size_oct, base = 8L))
    # A non-empty size field that fails octal parse (base-256, garbage, or above
    # strtoi()'s 2^31 limit) would desync this parser from the extractor: refuse.
    if (nzchar(size_oct) && (is.na(size) || size < 0)) {
      .refuse_tar("Refusing archive: unparseable entry size field.")
    }
    if (is.na(size)) size <- 0

    # Compare the typeflag as a BYTE. Never rawToChar() it: the byte is NUL for
    # regular files written by older tar implementations, and R strings cannot
    # contain a nul.
    tf <- as.integer(hdr[157L])
    type <- if (tf %in% c(48L, 0L)) "file"
            else if (tf == 49L)     "hardlink"
            else if (tf == 50L)     "symlink"
            else if (tf == 53L)     "dir"
            else                    "other"     # incl. 'L','K','x','g'

    # GNU long-name ('L'/'K') and PAX ('x'/'g') entries carry the real path in
    # the FOLLOWING entry's data block, so a parser that ignores them can be
    # made to misattribute names -- a benign-looking header overridden by a
    # long-name record. In the survey mentioned at the top of this script, no
    # CRAN package used them, so they are refused rather than parsed.
    # validate_tar() enforces this; the "other" type is retained here so callers
    # can see what was found.

    out[[length(out) + 1L]] <- data.frame(
      name = name, type = type, linkname = linkname, size = size,
      stringsAsFactors = FALSE
    )

    if (length(out) > max_entries) {
      .refuse_tar("Refusing archive: more than ",
                  format(max_entries, scientific = FALSE), " entries.")
    }

    # Skip data blocks in bounded chunks. A short read means the archive is
    # truncated relative to its declared sizes.
    skip <- ceiling(size / 512) * 512
    while (skip > 0) {
      want <- min(skip, chunk)
      got  <- length(readBin(con, "raw", want))
      bytes <- bytes + got
      if (bytes > max_bytes) {
        .refuse_tar("Refusing archive: uncompressed size exceeds ",
                    format(max_bytes, scientific = FALSE), " bytes.")
      }
      if (is.finite(max_ratio) && !is.na(compressed) && compressed > 0 &&
          bytes / compressed > max_ratio) {
        .refuse_tar("Refusing archive: uncompressed:compressed ratio exceeds ",
                    max_ratio, " (possible decompression bomb).")
      }
      if (got < want) {
        .refuse_tar("Refusing archive: truncated (entry data shorter than ",
                    "declared).")
      }
      skip <- skip - want
    }
  }

  if (length(out) == 0L) {
    .refuse_tar("Refusing archive: no entries found.")
  }

  do.call(rbind, out)
}


# gzfile() decompresses whatever it recognizes -- gzip, bzip2, xz, zstd --
# regardless of the file's name, so accepting its output would silently widen
# the documented gzip-or-plain contract and void the max_ratio bound. The
# known non-gzip magics are refused before the stream is opened.
.compression_magics <- list(
  bzip2    = as.raw(c(0x42, 0x5A, 0x68)),
  xz       = as.raw(c(0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00)),
  zstd     = as.raw(c(0x28, 0xB5, 0x2F, 0xFD)),
  compress = as.raw(c(0x1F, 0x9D))
)

.check_tar_magic <- function(tarfile) {
  con <- file(tarfile, open = "rb")
  on.exit(close(con), add = TRUE)
  lead <- readBin(con, "raw", 6L)
  for (format in names(.compression_magics)) {
    magic <- .compression_magics[[format]]
    if (length(lead) >= length(magic) &&
        identical(lead[seq_along(magic)], magic)) {
      .refuse_tar("Refusing archive '", basename(tarfile), "': ", format,
                  "-compressed; only gzip and uncompressed tar are read.")
    }
  }
  invisible(NULL)
}


# Refuse an untrusted archive with a classed condition. Subclassing `error`
# keeps the fail-closed behavior, while the `pkgaudit_invalid_tarball` class
# lets batch callers (e.g., survey_cran()) record a refusal.
.refuse_tar <- function(...) {
  stop(structure(
    class = c("pkgaudit_invalid_tarball", "error", "condition"),
    list(message = paste0(...), call = NULL)
  ))
}
