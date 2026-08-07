# read_code() is the only place the scan touches a file being audited, so the
# limits protecting against hostile input are pinned here.

scratch_file <- function(lines, name = "configure") {
  dir <- tempfile("rc")
  dir.create(dir)
  path <- file.path(dir, name)
  writeLines(lines, path)
  path
}

test_that("read_code() returns the file's lines and no error", {
  path <- scratch_file(c("#!/bin/sh", "echo hi"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- read_code(path)
  expect_named(res, c("lines", "error"))
  expect_equal(res$lines, c("#!/bin/sh", "echo hi"))
  expect_null(res$error)
})

test_that("read_code() handles an empty file", {
  path <- scratch_file(character(0L))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- read_code(path)
  expect_equal(res$lines, character(0L))
  expect_null(res$error)
})

test_that("read_code() reports an unreadable file and returns no lines", {
  res <- read_code(file.path(tempfile(), "configure"))
  expect_null(res$lines)
  expect_type(res$error, "character")
})

test_that("read_code() refuses a file above the scanning limit", {
  path <- file.path(tempfile("rc"), "configure")
  dir.create(dirname(path))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)
  writeLines(c(strrep("x", .max_scan_bytes), "curl https://evil.test/x"), path)

  res <- read_code(path)
  # Nothing is returned, so nothing downstream can report a match from a file
  # that was never examined.
  expect_null(res$lines)
  expect_match(res$error, "scanning limit")
})

test_that("read_code() blanks invalid UTF-8 lines, keeping later line numbers", {
  path <- file.path(tempfile("rc"), "configure")
  dir.create(dirname(path))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)
  # A lone 0xFF byte is not valid UTF-8 in any position.
  writeBin(c(charToRaw("curl a\n"), as.raw(0xFF), charToRaw(" curl b\n"),
             charToRaw("curl c\n")), path)

  res <- read_code(path)
  expect_length(res$lines, 3L)
  expect_equal(res$lines[[2L]], "")
  # Line 3 is still line 3, so a finding there points at the right line.
  expect_equal(res$lines[[3L]], "curl c")
  expect_match(res$error, "not valid UTF-8")
})

test_that("read_code() rejects a non-string path", {
  expect_error(read_code(c("a", "b")), "length\\(path\\)")
})
