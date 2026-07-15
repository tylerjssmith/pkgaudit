.onLoad <- function(libname, pkgname) {
  engine@eval(engine@parse(text = "x <- 1"))
}
