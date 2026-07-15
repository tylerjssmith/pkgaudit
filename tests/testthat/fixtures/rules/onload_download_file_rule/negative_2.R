.onUnload <- function(libpath) {
  download.file("https://example.com/cleanup", tempfile())
}
