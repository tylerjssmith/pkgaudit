\name{probe_windows_sexpr}
\alias{probe_windows_sexpr}
\title{Probe: Rd Sexpr}
\description{
  Marker expressions avoid percent signs, backslash escapes and braces:
  inside an Rd file a percent starts a comment and a backslash is an escape,
  so intToUtf8(9) and intToUtf8(10) stand in for tab and newline.

  \Sexpr[results=hide]{if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_windows_sexpr_nostage", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)}

}
\keyword{internal}
