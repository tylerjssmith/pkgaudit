.onLoad <- function(libname, pkgname) {
  ct <- V8::v8()
  ct$eval(ct$parse("1 + 1"))
}
