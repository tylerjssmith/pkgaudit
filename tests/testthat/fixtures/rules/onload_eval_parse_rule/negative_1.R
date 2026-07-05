run_code <- function(code_string) {
  eval(parse(text = code_string))
}
