fetch_data <- function(url) {
  req <- httr2::request(url)
  httr2::req_perform(req)
}
