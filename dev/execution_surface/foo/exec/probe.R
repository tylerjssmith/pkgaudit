# Instrumented probe sites: exec/*.R.
#
# exec/ is installed and its contents marked executable, but nothing in the
# lifecycle sources an R file there. The companion exec/probe.sh covers the
# shell case; this covers the R one, which pkgaudit carries a separate rule for.

.foo_mark_exec <- function(site) {
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                site, Sys.getpid()),
        file = p, append = TRUE)
  }
  invisible(NULL)
}

.foo_mark_exec("exec_R")

exec_fn_called <- function() .foo_mark_exec("exec_fn_called")
exec_fn_called()

exec_fn_uncalled <- function() .foo_mark_exec("exec_fn_uncalled")
