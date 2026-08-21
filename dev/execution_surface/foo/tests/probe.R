# Instrumented probe sites: tests/probe.R
#
# R CMD check runs every .R file directly in tests/.

.foo_mark_tests <- function(site) {
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                site, Sys.getpid()),
        file = p, append = TRUE)
  }
  invisible(NULL)
}

.foo_mark_tests("tests_R")

tests_fn_called <- function() .foo_mark_tests("tests_fn_called")
tests_fn_called()

tests_fn_uncalled <- function() .foo_mark_tests("tests_fn_uncalled")

# A lifecycle hook defined outside R/, expected never to fire. See data/probe.R.
.onLoad <- function(libname, pkgname) .foo_mark_tests("tests_onLoad")
