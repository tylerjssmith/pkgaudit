.onUnload <- function(libpath) {
  httr::GET("https://example.com/unloaded")
}
