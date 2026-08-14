# Extraction from the files R hands to a shell or to make. `make` inherits
# `shell`: the two are separate rule types because a Makefile is not a shell
# script, but reading them is identical.

test_that("a shell file yields one shell segment", {
  pkg <- make_pkg(files = list("configure" = c("#!/bin/sh", "curl x")))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  out <- extract_segments(
    new_source(file.path(pkg, "configure"), "configure", "shell"))
  expect_length(out$segments, 1L)
  expect_equal(class(out$segments[[1L]])[[1L]], "shell")
  expect_equal(out$segments[[1L]]$lines, c("#!/bin/sh", "curl x"))
})

test_that("a Makefile is read by the shell extractor it inherits from", {
  pkg <- make_pkg(files = list("src/Makevars" = "PKG_LIBS = -lcurl"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  src <- new_source(file.path(pkg, "src/Makevars"), "src/Makevars", "make")
  expect_true(inherits(src, "shell"))
  out <- extract_segments(src)
  expect_length(out$segments, 1L)
  # It still yields a shell segment, so the shell match rules apply to it.
  expect_equal(class(out$segments[[1L]])[[1L]], "shell")
})

test_that("shell code never brings named contexts with it", {
  pkg <- make_pkg(files = list("configure" = "curl x"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  seg <- extract_segments(
    new_source(file.path(pkg, "configure"), "configure", "shell"))$segments[[1L]]
  expect_null(seg$code_contexts)
})

test_that("a file that cannot be read yields no segment and an error", {
  out <- extract_segments(new_source(tempfile(), "configure", "shell"))
  expect_length(out$segments, 0L)
  expect_equal(out$errors$step, "read_code")
})
