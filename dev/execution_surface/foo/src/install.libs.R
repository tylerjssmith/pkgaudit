# Instrumented probe sites: src/install.libs.R.
#
# R sources this file during installation from source, after src/ has been
# compiled, in an R session that already defines R_PACKAGE_DIR, R_ARCH and
# SHLIB_EXT. It is a genuine R execution site that no rule for R/ would ever
# find, since it lives under src/.
#
# Markers written inline rather than through foo's own .foo_mark(): the package
# is not loaded at this point, so nothing in R/probe.R is reachable.

.foo_mark_install_libs <- function(site) {
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                site, Sys.getpid()),
        file = p, append = TRUE)
  }
  invisible(NULL)
}

.foo_mark_install_libs("install_libs")

install_libs_fn_called <- function()
  .foo_mark_install_libs("install_libs_fn_called")
install_libs_fn_called()

install_libs_fn_uncalled <- function()
  .foo_mark_install_libs("install_libs_fn_uncalled")

# Providing this file replaces R's default handling of the compiled artifacts,
# so the copying it would have done has to happen here or the package installs
# with no libs/ directory at all.
files <- Sys.glob(paste0("*", SHLIB_EXT))
dest  <- file.path(R_PACKAGE_DIR, paste0("libs", R_ARCH))
dir.create(dest, recursive = TRUE, showWarnings = FALSE)
file.copy(files, dest, overwrite = TRUE)
