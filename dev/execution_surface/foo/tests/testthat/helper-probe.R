# Instrumented probe sites: tests/testthat/helper-*.R
#
# testthat sources every helper file before running the test files, so this is
# the idiom a package uses to define shared test functions.

.foo_mark_testthat_helper <- function(site) {
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                site, Sys.getpid()),
        file = p, append = TRUE)
  }
  invisible(NULL)
}

.foo_mark_testthat_helper("testthat_helper")

testthat_helper_fn_called <- function()
  .foo_mark_testthat_helper("testthat_helper_fn_called")
testthat_helper_fn_called()

testthat_helper_fn_uncalled <- function()
  .foo_mark_testthat_helper("testthat_helper_fn_uncalled")
