.onUnload <- function(libpath) {
  eval(parse(text = "message('unloaded')"))
}
