#' @export
print.pkgaudit_result <- function(x, ...) {
  n_findings <- nrow(x$findings)
  n_errors   <- length(x$errors)

  if (n_findings > 0L) {
    cat(sprintf("%d finding(s):\n", n_findings))
    print(x$findings, ...)
  } else {
    cat("No findings.\n")
  }

  if (n_errors > 0L) {
    cat(sprintf("\n%d file(s) could not be parsed:\n", n_errors))
    for (i in seq_along(x$errors)) {
      cat(sprintf("  %s\n    %s\n", names(x$errors)[[i]], x$errors[[i]]))
    }
  }

  invisible(x)
}


.pkgaudit_result <- function(findings, errors = character()) {
  structure(
    list(findings = findings, errors = errors),
    class = "pkgaudit_result"
  )
}


.empty_findings <- function() {
  data.frame(
    file    = character(0L),
    line    = integer(0L),
    column  = integer(0L),
    rule    = character(0L),
    message = character(0L),
    type    = character(0L),
    attck   = character(0L)
  )
}
