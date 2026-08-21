# Instrumented probe sites: tests/testthat/test-*.R
#
# Three positions in one test file: top-level code outside any test_that()
# block, code inside one, and the two function bounds. A test_that() block is a
# braced argument rather than a function definition, so code in it is top-level
# as far as a parse tree is concerned; the marker distinguishes the two anyway.

.foo_mark_testthat <- function(site) {
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                site, Sys.getpid()),
        file = p, append = TRUE)
  }
  invisible(NULL)
}

.foo_mark_testthat("testthat_test")

testthat_fn_called <- function() .foo_mark_testthat("testthat_fn_called")
testthat_fn_called()

testthat_fn_uncalled <- function() .foo_mark_testthat("testthat_fn_uncalled")

testthat::test_that("the probe records its site", {
  .foo_mark_testthat("testthat_in_test_that")
  testthat::expect_true(TRUE)
})
