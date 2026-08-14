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

test_that("the hook rules reach a segment only when its file context names them", {
  pkg <- make_pkg(files = list("R/f.R" = "x <- 1"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  src <- function(ctx) new_source(file.path(pkg, "R/f.R"), "R/f.R", "R",
                                  code_contexts = ctx)

  expect_equal(extract_segments(src(.hook_rules))$segments[[1L]]$code_contexts,
               .hook_rules)
  # A .onLoad defined outside R/ ships as an ordinary object and never fires,
  # which the execution_surface probe measures directly.
  expect_null(extract_segments(src(NULL))$segments[[1L]]$code_contexts)
})

test_that("an R segment carries no label of its own, and knows its file rule", {
  pkg <- make_pkg(files = list("R/f.R" = "x <- 1"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  seg <- extract_segments(
    new_source(file.path(pkg, "R/f.R"), "R/f.R", "R",
               file_rule = "R_scripts"))$segments[[1L]]

  # No label: what top-level code in an R script belongs to is decided by the
  # file context when phases are resolved, not by the segment.
  expect_true(is.na(seg$context))
  expect_equal(seg$file_rule, "R_scripts")
})
