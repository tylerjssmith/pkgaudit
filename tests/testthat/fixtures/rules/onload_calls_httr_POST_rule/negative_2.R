.onUnload <- function(libpath) {
  httr::POST("https://example.com/unloaded")
}
