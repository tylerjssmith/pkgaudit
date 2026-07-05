.onUnload <- function(libpath) {
  curl::curl_fetch_memory("https://example.com/unloaded")
}
