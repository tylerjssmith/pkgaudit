# Instrumented probe sites: demo/*.R.
#
# Run only when a user calls demo(). Nothing in the build, install, or check
# lifecycle should reach this, which is the result being measured; the control
# row in experiments.csv invokes it directly so that a silent log distinguishes
# "never reached" from "instrumentation broken".

.foo_mark_demo <- function(site) {
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                site, Sys.getpid()),
        file = p, append = TRUE)
  }
  invisible(NULL)
}

.foo_mark_demo("demo_R")

demo_fn_called <- function() .foo_mark_demo("demo_fn_called")
demo_fn_called()

demo_fn_uncalled <- function() .foo_mark_demo("demo_fn_uncalled")
