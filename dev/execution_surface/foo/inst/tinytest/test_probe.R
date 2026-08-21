# Instrumented probe sites: inst/tinytest/test_*.R
#
# Unlike tests/, inst/ is copied into the installed package, so this code also
# ships to the user.

.foo_mark_tinytest <- function(site) {
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                site, Sys.getpid()),
        file = p, append = TRUE)
  }
  invisible(NULL)
}

.foo_mark_tinytest("tinytest_test")

tinytest_fn_called <- function() .foo_mark_tinytest("tinytest_fn_called")
tinytest_fn_called()

tinytest_fn_uncalled <- function() .foo_mark_tinytest("tinytest_fn_uncalled")

tinytest::expect_true(TRUE)
