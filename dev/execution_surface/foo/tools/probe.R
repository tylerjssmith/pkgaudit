# Instrumented probe sites: tools/probe.R
#
# Nothing runs this on its own; it is reached only if configure or a Makevars
# invokes it, which foo does not.

.foo_mark_tools <- function(site) {
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                site, Sys.getpid()),
        file = p, append = TRUE)
  }
  invisible(NULL)
}

.foo_mark_tools("tools_R")

tools_fn_called <- function() .foo_mark_tools("tools_fn_called")
tools_fn_called()

tools_fn_uncalled <- function() .foo_mark_tools("tools_fn_uncalled")
