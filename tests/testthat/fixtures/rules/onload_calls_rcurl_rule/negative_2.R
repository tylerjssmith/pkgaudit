.onUnload <- function(libpath) {
  RCurl::getURL("https://example.com/unloaded")
}
