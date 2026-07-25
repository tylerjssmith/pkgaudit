#' Find R scripts executed at install/load time
#'
#' Returns the R source files that R evaluates when a source package is
#' installed or its namespace is loaded: the top level of `R/`, `R/unix/`, and
#' `R/windows/`, plus `src/install.libs.R` when present. Subdirectories of `R/`
#' other than `unix/` and `windows/` are not processed by R and are excluded.
#'
#' @param pkg Path to the root of the package being audited.
#'
#' @return A character vector of absolute paths to R scripts. Empty if none.
#'
#' @details
#' The `list.files()` calls are intentionally not wrapped in `tryCatch()`: a
#' failure to list the package's own directories is unrecoverable, so it
#' propagates and aborts the audit (see [audit_package()]).
#'
#' @keywords internal
find_scripts <- function(pkg) {
  stopifnot(is.character(pkg), length(pkg) == 1L)

  # R/, including R/unix/ and R/windows/
  script_dirs <- file.path(pkg, c("R", file.path("R", "unix"),
                                  file.path("R", "windows")))

  scripts <- character(0L)
  for (dir in script_dirs) {
    if (!dir.exists(dir)) next
    files <- list.files(
      dir,
      pattern    = "\\.[RrSsq]$",
      recursive  = FALSE,
      full.names = TRUE,
      all.files  = TRUE
    )
    # list.files() with a pattern can still surface directory names; keep files.
    files <- files[file.exists(files) & !dir.exists(files)]
    scripts <- c(scripts, files)
  }

  # src/install.libs.R
  install_libs <- file.path(pkg, "src", "install.libs.R")
  if (file.exists(install_libs) && !dir.exists(install_libs)) {
    scripts <- c(scripts, install_libs)
  }

  scripts
}
