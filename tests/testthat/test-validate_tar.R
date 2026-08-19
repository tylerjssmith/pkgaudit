# Build a .tar.gz from a set of top-level directories under a fresh base, each
# given as name = list(relpath = contents). Returns the tarball path.
build_archive <- function(dirs) {
  base <- tempfile()
  for (top in names(dirs)) {
    files <- dirs[[top]]
    for (rel in names(files)) {
      target <- file.path(base, top, rel)
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      writeLines(files[[rel]], target)
    }
  }
  tb  <- tempfile(fileext = ".tar.gz")
  owd <- setwd(base); on.exit(setwd(owd), add = TRUE)
  utils::tar(tb, files = names(dirs), compression = "gzip", tar = "internal")
  tb
}

# happy path -------------------------------------------------------------------
test_that("validate_tar() accepts a well-formed single-directory archive", {
  tb <- build_archive(list(foo = list("DESCRIPTION" = "Package: foo",
                                      "R/zzz.R" = "invisible(NULL)")))
  on.exit(unlink(tb), add = TRUE)

  e <- validate_tar(tb)
  expect_s3_class(e, "data.frame")
  expect_named(e, c("name", "type", "linkname", "size"))
  expect_true(all(e$type %in% c("file", "dir")))
  # Exactly one top-level directory.
  expect_equal(length(unique(sub("/.*$", "", e$name))), 1L)
})

# refusals (classed condition) -------------------------------------------------
test_that("validate_tar() refuses more than one top-level directory", {
  tb <- build_archive(list(foo = list("DESCRIPTION" = "Package: foo"),
                           bar = list("x.R" = "1")))
  on.exit(unlink(tb), add = TRUE)

  err <- tryCatch(validate_tar(tb), error = function(e) e)
  expect_s3_class(err, "pkgaudit_invalid_tarball")
  expect_match(conditionMessage(err), "top-level directories")
})

test_that("validate_tar() refuses an archive exceeding max_entries", {
  tb <- build_archive(list(foo = stats::setNames(
    as.list(rep("x", 6L)), sprintf("f%d.R", seq_len(6L)))))
  on.exit(unlink(tb), add = TRUE)

  err <- tryCatch(validate_tar(tb, max_entries = 3L), error = function(e) e)
  expect_s3_class(err, "pkgaudit_invalid_tarball")
  expect_match(conditionMessage(err), "more than 3 entries")
})

test_that("validate_tar() refuses an archive exceeding max_bytes", {
  tb <- build_archive(list(foo = list("big.txt" = strrep("A", 5000L))))
  on.exit(unlink(tb), add = TRUE)

  err <- tryCatch(validate_tar(tb, max_bytes = 1024), error = function(e) e)
  expect_s3_class(err, "pkgaudit_invalid_tarball")
  expect_match(conditionMessage(err), "uncompressed size exceeds")
})

test_that("validate_tar() refuses an archive whose expansion ratio exceeds max_ratio", {
  # A highly compressible payload: large uncompressed, tiny compressed.
  tb <- build_archive(list(foo = list("big.txt" = strrep("A", 200000L))))
  on.exit(unlink(tb), add = TRUE)

  err <- tryCatch(validate_tar(tb, max_ratio = 5), error = function(e) e)
  expect_s3_class(err, "pkgaudit_invalid_tarball")
  expect_match(conditionMessage(err), "ratio exceeds")
})

test_that("a non-gzip compressed archive is refused by magic bytes, not name", {
  # gzfile() transparently decompresses bzip2 and xz too, so without this
  # check a stream named .tar.gz would be read anyway -- and xz compresses
  # far past the gzip ceiling that makes max_ratio a meaningful bomb bound.
  tb <- build_archive(list(foo = list("DESCRIPTION" = "Package: foo")))
  on.exit(unlink(tb), add = TRUE)
  plain <- gzfile(tb, open = "rb")
  bytes <- readBin(plain, "raw", 10L * file.size(tb) + 10240L)
  close(plain)

  for (compressor in list(bzip2 = bzfile, xz = xzfile)) {
    lying <- tempfile(fileext = ".tar.gz")
    con   <- compressor(lying, open = "wb")
    writeBin(bytes, con)
    close(con)

    err <- tryCatch(validate_tar(lying), error = function(e) e)
    expect_s3_class(err, "pkgaudit_invalid_tarball")
    expect_match(conditionMessage(err), "only gzip and uncompressed tar")
    unlink(lying)
  }
})

test_that("validate_tar() refuses an entry with an unparseable size field", {
  # A raw tar header whose size field is not valid octal. A base-256 or garbage
  # size read as 0 would desync this parser from the extractor.
  put <- function(h, off, s) {
    b <- charToRaw(s); h[(off + 1L):(off + length(b))] <- b; h
  }
  hdr <- raw(512L)
  hdr <- put(hdr, 0L,   "foo/file.txt")
  hdr <- put(hdr, 124L, "88888888")     # '8' is not an octal digit
  hdr[157L] <- charToRaw("0")           # typeflag '0' = regular file
  tb <- tempfile(fileext = ".tar")
  writeBin(c(hdr, raw(512L)), tb)        # bad header + end-of-archive block
  on.exit(unlink(tb), add = TRUE)

  err <- tryCatch(validate_tar(tb), error = function(e) e)
  expect_s3_class(err, "pkgaudit_invalid_tarball")
  expect_match(conditionMessage(err), "unparseable entry size")
})

test_that("validate_tar() refuses a truncated archive", {
  tb <- build_archive(list(foo = list("DESCRIPTION" = "Package: foo")))
  # Truncate the gzip stream partway through.
  raw <- readBin(tb, "raw", n = file.size(tb))
  writeBin(raw[seq_len(as.integer(length(raw) / 2))], tb)
  on.exit(unlink(tb), add = TRUE)

  err <- tryCatch(validate_tar(tb), error = function(e) e)
  expect_s3_class(err, "pkgaudit_invalid_tarball")
})

# tar_entries() (internal) -----------------------------------------------------
test_that("tar_entries() reports type and size without extracting", {
  tb <- build_archive(list(foo = list("DESCRIPTION" = "Package: foo",
                                      "R/zzz.R" = "invisible(NULL)")))
  on.exit(unlink(tb), add = TRUE)

  e <- tar_entries(tb)
  expect_true("dir" %in% e$type)
  expect_true("file" %in% e$type)
  expect_true(all(e$size >= 0))
})

test_that("tar_entries() validates its arguments", {
  tb <- build_archive(list(foo = list("DESCRIPTION" = "Package: foo")))
  on.exit(unlink(tb), add = TRUE)

  expect_error(tar_entries("/no/such/file.tar.gz"), "file.exists")
  expect_error(tar_entries(tb, max_entries = 0),    "max_entries")
  expect_error(tar_entries(tb, max_bytes   = -1),   "max_bytes")
  expect_error(tar_entries(tb, max_ratio   = 0),    "max_ratio")
  expect_error(tar_entries(tb, chunk       = 0),    "chunk")
})

# Raw-header cases -------------------------------------------------------------
# These build tar headers directly, because the shapes under test are ones no
# archiver on hand will produce.
put <- function(h, off, s) {
  b <- charToRaw(s); h[(off + 1L):(off + length(b))] <- b; h
}

file_header <- function(name = "foo/file.txt", size_oct = "00000000000",
                        prefix = "") {
  hdr <- raw(512L)
  hdr <- put(hdr, 0L, name)
  if (nzchar(size_oct)) hdr <- put(hdr, 124L, size_oct)
  if (nzchar(prefix))   hdr <- put(hdr, 345L, prefix)
  hdr[157L] <- charToRaw("0")            # typeflag '0' = regular file
  hdr
}

write_tar <- function(...) {
  tb <- tempfile(fileext = ".tar")
  writeBin(c(...), tb)
  tb
}

test_that("tar_entries() joins a ustar long-path prefix onto the name", {
  tb <- write_tar(file_header(name = "file.txt", prefix = "foo/deep"),
                  raw(512L))
  on.exit(unlink(tb), add = TRUE)

  e <- tar_entries(tb)
  expect_equal(e$name, "foo/deep/file.txt")
})

test_that("tar_entries() reads an empty size field as zero", {
  # Some writers leave the field NUL-filled for an entry carrying no data.
  tb <- write_tar(file_header(size_oct = ""), raw(512L))
  on.exit(unlink(tb), add = TRUE)

  e <- tar_entries(tb)
  expect_equal(e$size, 0)
})

test_that("validate_tar() refuses an archive whose entry data is short", {
  # The header declares 1024 bytes; only one 512-byte block follows.
  tb <- write_tar(file_header(size_oct = "00000002000"), raw(512L))
  on.exit(unlink(tb), add = TRUE)

  err <- tryCatch(validate_tar(tb), error = function(e) e)
  expect_s3_class(err, "pkgaudit_invalid_tarball")
  expect_match(conditionMessage(err), "entry data shorter than")
})

test_that("validate_tar() refuses an archive holding no entries", {
  tb <- write_tar(raw(1024L))            # end-of-archive blocks and nothing else
  on.exit(unlink(tb), add = TRUE)

  err <- tryCatch(validate_tar(tb), error = function(e) e)
  expect_s3_class(err, "pkgaudit_invalid_tarball")
  expect_match(conditionMessage(err), "no entries found")
})
