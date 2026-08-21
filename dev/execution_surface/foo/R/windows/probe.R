# Instrumented probe site: R/windows/probe.R
#
# R/windows is added on Windows only, so this should never fire here.

local({
  p <- Sys.getenv("FOO_LOG")
  if (nzchar(p)) {
    cat(sprintf("%s\t%s\t%d\n", format(Sys.time(), "%H:%M:%OS3"),
                "r_windows", Sys.getpid()),
        file = p, append = TRUE)
  }
})
