# dev/survey_tarballs.R
#
# Reconstructs the empirical basis for the default caps in tar_entries() /
# validate_tar(). Two surveys over a directory of source package tarballs:
#
#   survey_structure()  -- header-only pass: entry counts, declared sizes,
#                          typeflags, path shapes, top-level directory counts.
#                          No entry data is written; data blocks are skipped.
#   survey_expansion()  -- decompression pass: measures the actual uncompressed
#                          size and the uncompressed:compressed ratio, which is
#                          the basis for a decompression-bomb (max_ratio) cap.
#
# Neither extracts to the filesystem. survey_structure() still decompresses
# incrementally to reach each header, but skips entry data; survey_expansion()
# decompresses fully to measure expansion. Run on a full CRAN src/contrib
# snapshot to reproduce the distributions behind the chosen defaults.

# ---------------------------------------------------------------------------
# Structure survey (header-only)
# ---------------------------------------------------------------------------

#' Survey the tar structure of one source package tarball
#'
#' Reads tar headers directly -- unlike `utils::untar(list = TRUE)`, this
#' recovers each entry's typeflag, so link entries and non-standard header
#' types are visible. Entry data blocks are skipped, so nothing is written to
#' disk. Reaching entry N's header still requires decompressing everything
#' before it, so cost is O(uncompressed size).
#'
#' @param path Path to a `.tar.gz` (or `.tgz`, or uncompressed `.tar`) archive.
#' @param max_entries Guard against a hostile entry count while surveying.
#'   Recorded via `cap_hit` if reached.
#' @param chunk Bytes read per call when skipping entry data, bounding peak
#'   allocation.
#'
#' @return A one-row data frame: file, compressed_size, n_entries, bytes_read
#'   (uncompressed header+padded data), max_entry_size, n_bad_size,
#'   max_path_nchar, max_path_depth, n_symlink, n_hardlink, n_other_type,
#'   n_nul_typeflag, n_traversal, n_absolute, n_backslash, n_control, n_empty,
#'   n_toplevel, truncated, cap_hit, error.
survey_structure <- function(path,
                             max_entries = 1e6,
                             chunk       = 1048576L) {

  out <- data.frame(
    file            = basename(path),
    compressed_size = tryCatch(file.size(path), error = function(e) NA_real_),
    n_entries       = NA_integer_,
    bytes_read      = NA_real_,
    max_entry_size  = NA_real_,
    n_bad_size      = NA_integer_,
    max_path_nchar  = NA_integer_,
    max_path_depth  = NA_integer_,
    n_symlink       = NA_integer_,
    n_hardlink      = NA_integer_,
    n_other_type    = NA_integer_,
    n_nul_typeflag  = NA_integer_,
    n_traversal     = NA_integer_,
    n_absolute      = NA_integer_,
    n_backslash     = NA_integer_,
    n_control       = NA_integer_,
    n_empty         = NA_integer_,
    n_toplevel      = NA_integer_,
    truncated       = NA,
    cap_hit         = NA,
    error           = NA_character_,
    stringsAsFactors = FALSE
  )

  con <- tryCatch(gzfile(path, open = "rb"), error = function(e) NULL)
  if (is.null(con)) { out$error <- "could not open"; return(out) }
  on.exit(close(con), add = TRUE)

  n <- 0L; bytes <- 0; maxsize <- 0
  maxnchar <- 0L; maxdepth <- 0L
  n_sym <- 0L; n_hard <- 0L; n_other <- 0L; n_nul <- 0L
  n_trav <- 0L; n_abs <- 0L
  n_bs <- 0L; n_ctrl <- 0L; n_empty <- 0L; n_badsize <- 0L
  toplevel <- character(0)
  truncated <- FALSE; cap_hit <- FALSE

  err <- tryCatch({
    repeat {
      hdr <- readBin(con, "raw", 512L)
      if (length(hdr) < 512L) { truncated <- TRUE; break }
      bytes <- bytes + 512
      if (all(hdr == as.raw(0))) break                 # end-of-archive

      fld <- function(off, len) {
        r <- hdr[(off + 1L):(off + len)]
        r <- r[r != as.raw(0)]
        trimws(rawToChar(r))
      }

      name   <- fld(0L, 100L)
      prefix <- fld(345L, 155L)
      if (nzchar(prefix)) name <- paste0(prefix, "/", name)
      size_str <- fld(124L, 12L)
      size <- suppressWarnings(strtoi(size_str, base = 8L))
      # A non-empty size field that fails octal parse (base-256, garbage, or
      # above strtoi()'s 2^31 limit) would desync a parser that reads it as 0.
      if (nzchar(size_str) && is.na(size)) n_badsize <- n_badsize + 1L
      if (is.na(size) || size < 0) size <- 0

      # Typeflag as a BYTE. Never rawToChar() it: NUL for legacy regular files,
      # and R strings cannot contain a nul.
      tf <- as.integer(hdr[157L])

      n <- n + 1L
      maxsize  <- max(maxsize, size)
      maxnchar <- max(maxnchar, nchar(name))

      parts    <- strsplit(name, "/", fixed = TRUE)[[1]]
      parts    <- parts[nzchar(parts)]
      maxdepth <- max(maxdepth, length(parts))
      if (any(parts == "..")) n_trav <- n_trav + 1L
      if (grepl("^/", name) || grepl("^[A-Za-z]:", name)) n_abs <- n_abs + 1L
      if (grepl("\\\\", name))        n_bs    <- n_bs    + 1L
      if (grepl("[[:cntrl:]]", name)) n_ctrl  <- n_ctrl  + 1L
      if (!nzchar(name))              n_empty <- n_empty + 1L
      if (length(parts) > 0L) toplevel <- c(toplevel, parts[1L])

      if      (tf == 50L) n_sym  <- n_sym  + 1L                   # '2' symlink
      else if (tf == 49L) n_hard <- n_hard + 1L                   # '1' hard link
      else if (!tf %in% c(48L, 0L, 53L)) n_other <- n_other + 1L  # not '0',NUL,'5'
      if (tf == 0L) n_nul <- n_nul + 1L                           # legacy NUL regular file

      skip <- ceiling(size / 512) * 512
      while (skip > 0) {
        want <- min(skip, chunk)
        got  <- length(readBin(con, "raw", want))
        bytes <- bytes + got
        if (got < want) { truncated <- TRUE; break }
        skip <- skip - want
      }
      if (truncated) break

      if (n >= max_entries) { cap_hit <- TRUE; break }
    }
    NA_character_
  }, error = function(e) conditionMessage(e))

  out$n_entries      <- n
  out$bytes_read     <- bytes
  out$max_entry_size <- maxsize
  out$n_bad_size     <- n_badsize
  out$max_path_nchar <- maxnchar
  out$max_path_depth <- maxdepth
  out$n_symlink      <- n_sym
  out$n_hardlink     <- n_hard
  out$n_other_type   <- n_other
  out$n_nul_typeflag <- n_nul
  out$n_traversal    <- n_trav
  out$n_absolute     <- n_abs
  out$n_backslash    <- n_bs
  out$n_control      <- n_ctrl
  out$n_empty        <- n_empty
  out$n_toplevel     <- length(unique(toplevel))
  out$truncated      <- truncated
  out$cap_hit        <- cap_hit
  out$error          <- err
  out
}


# ---------------------------------------------------------------------------
# Expansion survey (full decompression)
# ---------------------------------------------------------------------------

#' Measure the decompression expansion of one source package tarball
#'
#' Fully decompresses the archive (in bounded chunks, without writing to disk)
#' to measure its true uncompressed size and the uncompressed:compressed ratio.
#' This is the empirical basis for a `max_ratio` decompression-bomb cap:
#' bombs are characterised by extreme ratios rather than absolute size.
#'
#' @param path Path to a `.tar.gz` (or `.tgz`, or uncompressed `.tar`) archive.
#' @param chunk Bytes read per decompression call.
#' @param max_uncompressed Safety ceiling for the survey itself, so a bomb in
#'   the snapshot cannot exhaust memory or disk while measuring. Recorded via
#'   `cap_hit` if reached; the reported ratio is then a lower bound.
#'
#' @return A one-row data frame: file, compressed_size, uncompressed_size,
#'   ratio, cap_hit, error.
survey_expansion <- function(path,
                             chunk            = 1048576L,
                             max_uncompressed = 8 * 1024^3) {

  out <- data.frame(
    file              = basename(path),
    compressed_size   = tryCatch(file.size(path), error = function(e) NA_real_),
    uncompressed_size = NA_real_,
    ratio             = NA_real_,
    cap_hit           = NA,
    error             = NA_character_,
    stringsAsFactors  = FALSE
  )

  con <- tryCatch(gzfile(path, open = "rb"), error = function(e) NULL)
  if (is.null(con)) { out$error <- "could not open"; return(out) }
  on.exit(close(con), add = TRUE)

  total <- 0; cap_hit <- FALSE
  err <- tryCatch({
    repeat {
      raw <- readBin(con, "raw", chunk)
      got <- length(raw)
      if (got == 0L) break
      total <- total + got
      if (total > max_uncompressed) { cap_hit <- TRUE; break }
    }
    NA_character_
  }, error = function(e) conditionMessage(e))

  out$uncompressed_size <- total
  out$ratio <- if (!is.na(out$compressed_size) && out$compressed_size > 0)
                 total / out$compressed_size else NA_real_
  out$cap_hit <- cap_hit
  out$error   <- err
  out
}


# ---------------------------------------------------------------------------
# Directory drivers
# ---------------------------------------------------------------------------

#' Run a per-tarball survey over a directory of source packages
#'
#' @param dir Directory containing source package tarballs.
#' @param fun Survey function to apply, e.g. [survey_structure()] or
#'   [survey_expansion()].
#' @param pattern File-name pattern selecting tarballs.
#' @param verbose Emit progress every 500 files.
#' @param ... Passed to `fun`.
#'
#' @return A data frame, one row per tarball, from `do.call(rbind, ...)`.
survey_dir <- function(dir, fun,
                       pattern = "\\.(tar\\.gz|tgz|tar)$",
                       verbose = TRUE, ...) {
  files <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(files) == 0L) stop("No tarballs found in ", dir)

  rows <- vector("list", length(files))
  for (i in seq_along(files)) {
    if (verbose && i %% 500L == 0L)
      message(sprintf("[%d/%d] %s", i, length(files), basename(files[i])))
    rows[[i]] <- tryCatch(
      fun(files[i], ...),
      error = function(e) {
        # survey_structure/expansion catch internally and always return a row,
        # so this is rare. Re-run with the same args to recover the full-schema
        # row (needed for the final rbind), then record the outer error.
        r <- fun(files[i], ...)
        r$error <- conditionMessage(e)
        r
      }
    )
  }
  do.call(rbind, rows)
}

# ---------------------------------------------------------------------------
# Reproduction notes
# ---------------------------------------------------------------------------
# structure <- survey_dir(cran_contrib, survey_structure)
# expansion <- survey_dir(cran_contrib, survey_expansion)
#
# Caps in tar_entries()/validate_tar() are chosen with generous headroom above
# the observed CRAN maxima, not at a percentile: the caps exist to reject absurd
# archives. Rejecting a legitimate package is worse than admitting a large one.
#   quantile(structure$n_entries,  c(.5, .9, .99, .999, 1))   # -> max_entries
#   quantile(structure$bytes_read, c(.5, .9, .99, .999, 1))   # -> max_bytes
#   # max_ratio: exclude capped/errored rows, whose ratios are lower bounds.
#   ok <- subset(expansion, !cap_hit & is.na(error))
#   quantile(ok$ratio,             c(.5, .9, .99, .999, 1))   # -> max_ratio
#   sum(structure$n_symlink > 0); sum(structure$n_hardlink > 0)
#   sum(structure$n_other_type > 0); sum(structure$n_traversal > 0)
#   sum(structure$n_absolute > 0);  table(structure$n_toplevel)
#   sum(structure$n_backslash > 0); sum(structure$n_control > 0)
#   sum(structure$n_empty > 0);     sum(structure$n_bad_size > 0)
#   subset(structure, truncated | !is.na(error))
#   subset(expansion, cap_hit | !is.na(error))
#
# Bioconductor (esp. annotation/experiment-data packages) far exceeds CRAN's
# size maxima, so max_bytes must be raised for that ecosystem.
