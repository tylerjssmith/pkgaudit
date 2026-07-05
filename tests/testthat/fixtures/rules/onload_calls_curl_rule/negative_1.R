download_data <- function(url, dest) {
  curl::curl_download(url, destfile = dest)
}
