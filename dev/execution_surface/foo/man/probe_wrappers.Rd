\name{probe_wrappers}
\alias{probe_wrappers}
\title{Probe: Rd example wrappers}
\description{
  One instrumented site per wrapper tag that can appear in an \examples block,
  plus an unwrapped control. Which of these an example run reaches is what
  decides whether pkgaudit may call the code under a tag guarded.

  Marker expressions avoid percent signs, backslash escapes and braces, as in
  \link{probe_examples}: inside an Rd file a percent starts a comment and a
  backslash is an escape, so intToUtf8(9) and intToUtf8(10) stand in for tab
  and newline.
}
\examples{
if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_unwrapped", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)

\dontshow{
if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_dontshow", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)
}

\donttest{
if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_donttest", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)
}

\dontrun{
if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_dontrun", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)
}

\testonly{
if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_testonly", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)
}
}
\keyword{internal}
