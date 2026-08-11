# Extraction from plain R source: R/, and every other place a package carries R
# that something evaluates.

test_that("an R file yields one segment holding its lines verbatim", {
  pkg <- make_pkg(files = list("R/f.R" = c("x <- 1", "system('id')")))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  out <- extract_segments(new_source(file.path(pkg, "R/f.R"), "R/f.R", "R"))
  expect_length(out$segments, 1L)
  expect_equal(out$segments[[1L]]$lines, c("x <- 1", "system('id')"))
  expect_equal(class(out$segments[[1L]])[[1L]], "R")
  expect_equal(nrow(out$errors), 0L)
})

test_that("a file that cannot be read yields no segment and an error", {
  out <- extract_segments(new_source(tempfile(), "R/gone.R", "R"))

  expect_length(out$segments, 0L)
  expect_equal(out$errors$step, "read_code")
  expect_equal(out$errors$file_context, "R/gone.R")
})

test_that("the hook rules apply only where the code becomes the namespace", {
  pkg <- make_pkg(files = list("R/f.R" = "x <- 1"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  src <- function(ns) new_source(file.path(pkg, "R/f.R"), "R/f.R", "R",
                                 namespace_source = ns)

  expect_true(extract_segments(src(TRUE))$segments[[1L]]$named_contexts)
  # A .onLoad defined outside R/ ships as an ordinary object and never fires.
  expect_false(extract_segments(src(FALSE))$segments[[1L]]$named_contexts)
})

test_that("a file-context rule's own context replaces Top-level", {
  pkg <- make_pkg(files = list("R/f.R" = "x <- 1"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  seg <- function(ctx) extract_segments(
    new_source(file.path(pkg, "R/f.R"), "R/f.R", "R",
               code_context = ctx))$segments[[1L]]

  # NA leaves determine_code_contexts() to place patterns as usual.
  expect_true(is.na(seg(.context_top_level)$context))
  expect_equal(seg("data")$context, "data")
})
