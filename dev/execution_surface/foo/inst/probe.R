# Instrumented probe site: inst/probe.R
#
# Control for inst/CITATION: inst/ is copied verbatim, so a plain R script under it should never be sourced.

local({
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                "inst_R", Sys.getpid()),
        file = p, append = TRUE)
  }
})
