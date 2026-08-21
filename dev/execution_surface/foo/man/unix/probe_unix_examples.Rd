\name{probe_unix_examples}
\alias{probe_unix_examples}
\title{Probe: Rd examples}
\description{One instrumented \examples site.}
\examples{
if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_unix_examples", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)
}
\keyword{internal}
