# Instrumented probe sites in R/.
#
# Every site appends one line to the log named by FOO_LOG, which run_foo.sh
# sets. When FOO_LOG is unset the package records nothing, so installing or
# loading it outside the harness has no effect.
#
# Each line is: <time>\t<site>\t<pid>. The pid matters because R CMD INSTALL and
# R CMD build run parts of their work in subprocesses, and a site firing in a
# subprocess is still a site that fired.

.foo_mark <- function(site) {
  path <- Sys.getenv("FOO_LOG", unset = "")
  if (!nzchar(path)) return(invisible(NULL))
  cat(
    sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"), site, Sys.getpid()),
    file   = path,
    append = TRUE
  )
  invisible(NULL)
}


# Top-level code in R/. Runs when the package's lazy-load database is built, not
# when the installed package is later loaded: the built database holds the
# resulting values, and loading restores them without re-evaluating this.
.foo_mark("top_level")


# The two bounds on a function body.
#
# Whether code inside a function definition runs is not a property of where the
# definition sits: it depends on whether something calls it. Both bounds are
# measured rather than reasoned about. One function is called from top level and
# fires wherever top-level code does; the other is only defined. The pair
# appears in every file context that carries R, so the two can be compared per
# context.
r_fn_called <- function() .foo_mark("r_fn_called")
r_fn_called()

r_fn_uncalled <- function() .foo_mark("r_fn_uncalled")


.onLoad <- function(libname, pkgname) {
  .foo_mark("onLoad")
}

.onAttach <- function(libname, pkgname) {
  .foo_mark("onAttach")
}

.onUnload <- function(libpath) {
  .foo_mark("onUnload")
}

.onDetach <- function(libpath) {
  .foo_mark("onDetach")
}

# Detaching an attached package calls .Last.lib as well as .onDetach. Kept
# alongside them so the two can be compared directly in the same log.
.Last.lib <- function(libpath) {
  .foo_mark("Last_lib")
}
