.onUnload <- function(libpath) {
  httr2::req_perform(httr2::request("https://example.com/unloaded"))
}
