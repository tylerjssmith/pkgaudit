# Instrumented probe sites: .Rprofile at the package root.
#
# R evaluates a .Rprofile found in the working directory at startup, so this
# fires only if some R process in the lifecycle starts with its cwd inside the
# package. Runs before any package is loaded, so it must stay in base R.

.foo_mark_rprofile <- function(site) {
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                site, Sys.getpid()),
        file = p, append = TRUE)
  }
  invisible(NULL)
}

.foo_mark_rprofile("rprofile")

rprofile_fn_called <- function() .foo_mark_rprofile("rprofile_fn_called")
rprofile_fn_called()

rprofile_fn_uncalled <- function() .foo_mark_rprofile("rprofile_fn_uncalled")
