# Instrumented probe sites: data/*.R.
#
# Sourced by data() on demand, and evaluated at install time when DESCRIPTION
# sets LazyData, which foo does. Markers written inline: the package is not
# loaded when this runs, so .foo_mark() in R/probe.R is not reachable.

.foo_mark_data <- function(site) {
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                site, Sys.getpid()),
        file = p, append = TRUE)
  }
  invisible(NULL)
}

.foo_mark_data("data_R")

data_fn_called <- function() .foo_mark_data("data_fn_called")
data_fn_called()

data_fn_uncalled <- function() .foo_mark_data("data_fn_uncalled")

# A lifecycle hook defined outside R/. Only code that becomes the package
# namespace can supply one, so this is expected never to fire: it ships as an
# ordinary object and nothing calls it. That is what separates a hook from a
# function that merely carries a hook's name.
.onLoad <- function(libname, pkgname) .foo_mark_data("data_onLoad")

# A data file has to leave an object behind, or there is nothing to lazy-load.
probe_data <- 1L
