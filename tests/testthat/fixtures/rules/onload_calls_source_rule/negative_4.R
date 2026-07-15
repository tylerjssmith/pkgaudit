.onLoad <- function(libname, pkgname) {
  .env$ct$source(file.path(root, "ajv.js"))
}
