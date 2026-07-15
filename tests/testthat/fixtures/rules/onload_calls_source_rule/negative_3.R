.onLoad <- function(libname, pkgname) {
  ctx <- V8::v8()
  ctx$source(system.file("js/foo.js", package = pkgname))
}
