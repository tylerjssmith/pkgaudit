\name{probe_sexpr}
\alias{probe_sexpr}
\title{Probe: Rd Sexpr}
\description{
  Marker expressions avoid percent signs, backslash escapes and braces:
  inside an Rd file a percent starts a comment and a backslash is an escape,
  so intToUtf8(9) and intToUtf8(10) stand in for tab and newline.

  Each stage carries three sites: the macro's own code, a function it calls,
  and a function it only defines. The three are separate macros of the same
  stage rather than one macro of three statements, so a parse failure in any
  one of them cannot cost the others.

  \Sexpr[stage=build,results=hide]{if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_sexpr_build", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)}

  \Sexpr[stage=build,results=hide]{rd_sexpr_build_fn_called <- function() if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_sexpr_build_fn_called", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)}

  \Sexpr[stage=build,results=hide]{rd_sexpr_build_fn_called()}

  \Sexpr[stage=build,results=hide]{rd_sexpr_build_fn_uncalled <- function() if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_sexpr_build_fn_uncalled", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)}

  \Sexpr[stage=install,results=hide]{if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_sexpr_install", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)}

  \Sexpr[stage=install,results=hide]{rd_sexpr_install_fn_called <- function() if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_sexpr_install_fn_called", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)}

  \Sexpr[stage=install,results=hide]{rd_sexpr_install_fn_called()}

  \Sexpr[stage=install,results=hide]{rd_sexpr_install_fn_uncalled <- function() if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_sexpr_install_fn_uncalled", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)}

  \Sexpr[stage=render,results=hide]{if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_sexpr_render", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)}

  \Sexpr[stage=render,results=hide]{rd_sexpr_render_fn_called <- function() if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_sexpr_render_fn_called", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)}

  \Sexpr[stage=render,results=hide]{rd_sexpr_render_fn_called()}

  \Sexpr[stage=render,results=hide]{rd_sexpr_render_fn_uncalled <- function() if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_sexpr_render_fn_uncalled", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)}

  \Sexpr[results=hide]{if (nzchar(Sys.getenv("FOO_LOG"))) cat(paste0(format(Sys.time()), intToUtf8(9), "rd_sexpr_nostage", intToUtf8(9), Sys.getpid(), intToUtf8(10)), file = Sys.getenv("FOO_LOG"), append = TRUE)}

}
\keyword{internal}
