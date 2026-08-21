# Rebuild lib/ when it is absent. run_foo.sh calls this before its first use
# of the library; it can also be run by hand from this directory.
#
# lib.lock records the library the shipped measurements were made against, one
# Package\tVersion pair per line: the testing frameworks the probe exercises
# -- testthat, tinytest, RUnit -- and their dependency closure. Every locked
# package is installed explicitly, because run_foo.sh points R_LIBS_USER at
# lib/ as the only library besides R's own, and install.packages would skip a
# dependency it can see in some other library on this machine. CRAN serves
# current versions, not locked ones, so after installing this script compares
# every installed version against the lock and prints what differs: drift does
# not invalidate a rerun, but it is the first thing to check when a rerun
# disagrees with a shipped log. The probe package itself (`foo`) is not
# installed here -- installing it is what the experiments measure.

here <- dirname(normalizePath(sub("^--file=", "",
  grep("^--file=", commandArgs(), value = TRUE)[[1L]]
)))
lib  <- file.path(here, "lib")
lock <- file.path(here, "lib.lock")

locked <- read.delim(lock, stringsAsFactors = FALSE)

dir.create(lib, recursive = TRUE, showWarnings = FALSE)
install.packages(locked$Package, lib = lib,
                 repos = "https://cloud.r-project.org")

installed <- installed.packages(lib.loc = lib)[, c("Package", "Version")]

now   <- installed[match(locked$Package, installed[, "Package"]), "Version"]
drift <- is.na(now) | now != locked$Version
if (any(drift)) {
  cat("Versions differing from lib.lock (locked -> installed):\n")
  cat(sprintf("  %s %s -> %s\n", locked$Package[drift], locked$Version[drift],
              ifelse(is.na(now[drift]), "absent", now[drift])), sep = "")
} else {
  cat("lib/ matches lib.lock.\n")
}
