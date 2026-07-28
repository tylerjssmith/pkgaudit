# Build the example source package scanned in vignettes/getting-started.Rmd.
#
# Run from the package root:
#   Rscript data-raw/create_untrustedpkg.R
#
# untrustedpkg is a synthetic package. It is never built, installed, or loaded;
# it exists only so the vignette has something with findings to scan. Its
# contents are deliberately chosen to produce one finding of each kind: a file
# context (configure), a code context (.onLoad), and two patterns in different
# code contexts (system() at load, download.file() in an ordinary function).

create_untrustedpkg <- function(
  dest    = file.path("inst", "extdata", "untrustedpkg"),
  version = "0.1.0"
) {
  src <- file.path(tempdir(), "untrustedpkg")
  unlink(src, recursive = TRUE)
  dir.create(file.path(src, "R"), recursive = TRUE)

  writeLines(c(
    "Package: untrustedpkg",
    "Title: An Example Package",
    paste0("Version: ", version),
    "Description: A small package used to demonstrate pkgaudit.",
    "License: MIT + file LICENSE"
  ), file.path(src, "DESCRIPTION"))

  # A configure script runs at install time, before any R code is loaded.
  writeLines(c(
    "#!/bin/sh",
    "echo configuring"
  ), file.path(src, "configure"))

  # .onLoad() runs automatically when the namespace is loaded.
  writeLines(c(
    ".onLoad <- function(libname, pkgname) {",
    '  system("uname -a")',
    "}"
  ), file.path(src, "R", "zzz.R"))

  # An ordinary function only runs if the user calls it.
  writeLines(c(
    "fetch_data <- function(url) {",
    "  download.file(url, tempfile())",
    "}"
  ), file.path(src, "R", "fetch.R"))

  if (!dir.exists(dest)) dir.create(dest, recursive = TRUE)
  tarball <- file.path(
    normalizePath(dest, mustWork = TRUE),
    sprintf("untrustedpkg_%s.tar.gz", version)
  )

  # Archive from the parent directory so the tarball holds relative paths.
  # validate_tar() refuses absolute paths, as a real source tarball has none.
  owd <- setwd(dirname(src))
  on.exit(setwd(owd), add = TRUE)
  utils::tar(tarball, files = basename(src), compression = "gzip",
             tar = "internal")

  message("Wrote: ", tarball)
  invisible(tarball)
}

create_untrustedpkg()
