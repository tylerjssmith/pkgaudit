\name{probe_examples}
\alias{probe_examples}
\title{Probe: Rd examples}
\description{
  Three instrumented sites in one \examples block: the block's own top-level
  code, a function called from it, and a function only defined.

  Marker expressions avoid percent signs, backslash escapes and braces: inside
  an Rd file a percent starts a comment and a backslash is an escape, so
  intToUtf8(9) and intToUtf8(10) stand in for tab and newline.
}
\examples{
if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_examples", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)

rd_examples_fn_called <- function() if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_examples_fn_called", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)
rd_examples_fn_called()

rd_examples_fn_uncalled <- function() if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_examples_fn_uncalled", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)
}
\keyword{internal}
