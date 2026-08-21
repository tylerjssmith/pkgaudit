# Instrumented probe site: R/unix/probe.R
#
# R/unix is added to the sourced R code on Unix-alikes only.
#
# Its own marker rather than .foo_mark() from R/probe.R: the collation order of
# R/ against its platform subdirectory is not guaranteed, so this file must not
# depend on another having been sourced first.

.foo_mark_r_unix <- function(site) {
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                site, Sys.getpid()),
        file = p, append = TRUE)
  }
  invisible(NULL)
}

.foo_mark_r_unix("r_unix")

r_unix_fn_called <- function() .foo_mark_r_unix("r_unix_fn_called")
r_unix_fn_called()

r_unix_fn_uncalled <- function() .foo_mark_r_unix("r_unix_fn_uncalled")
