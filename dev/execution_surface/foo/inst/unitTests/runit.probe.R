# Instrumented probe sites: inst/unitTests/runit.*.R
#
# RUnit sources each test file, then calls the functions in it whose names match
# its test pattern. That makes the file the one place where a function body is
# reached by the framework rather than by code in the same file, so the two
# bounds are joined here by a third site: a function the runner itself calls.

.foo_mark_runit <- function(site) {
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                site, Sys.getpid()),
        file = p, append = TRUE)
  }
  invisible(NULL)
}

.foo_mark_runit("runit_test")

runit_fn_called <- function() .foo_mark_runit("runit_fn_called")
runit_fn_called()

runit_fn_uncalled <- function() .foo_mark_runit("runit_fn_uncalled")

# Named to match RUnit's test pattern, so the framework calls it.
test.probe <- function() {
  .foo_mark_runit("runit_fn_framework_called")
  RUnit::checkTrue(TRUE)
}
