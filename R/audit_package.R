#' Audit an R package for security-relevant patterns
#'
#' Scans R source files in the locations processed at (source) package install
#' time: the top level of `R/`, `R/unix/`, `R/windows/`, and `src/install.libs.R`.
#' Subdirectories of `R/` other than `unix/` and `windows/` are not processed by
#' R at install time and are excluded.
#'
#' @param path Path to the root directory of the R package to audit.
#'   Defaults to the current directory.
#' @param rules Named list of rule objects as returned by [load_rules()].
#'   Defaults to loading stable rules from the bundled database.
#' @param label Display name used in diagnostic messages. Defaults to
#'   `basename(path)`. [audit_tarball()] sets this to the tarball filename so
#'   messages refer to the original file rather than a temporary directory.
#'
#' @return A `pkgaudit_result` with two fields:
#'   \describe{
#'     \item{findings}{Data frame of findings across all files, with the same
#'       columns as [audit_file()]. Zero rows when no patterns match.}
#'     \item{errors}{Named character vector of files that could not be parsed,
#'       where names are file paths and values are error messages. Zero-length
#'       when all files were successfully inspected.}
#'   }
#'
#' @examples
#' \dontrun{
#' result <- audit_package("/path/to/somepackage")
#' result$findings
#' result$errors
#'
#' # Record rules version alongside findings
#' attr(result, "rules_version") <- rules_version()
#' }
#'
#' @export
audit_package <- function(
  path  = ".",
  rules = pkgaudit::load_rules(),
  label = basename(path)
) {
  stopifnot(is.character(path), length(path) == 1L)
  stopifnot(dir.exists(path))
  stopifnot(is.list(rules), length(rules) > 0L)
  stopifnot(is.character(label), length(label) == 1L)

  if (!file.exists(file.path(path, "DESCRIPTION"))) {
    stop(
      "No DESCRIPTION file found at: ", path, "\n",
      "Ensure 'path' points to the root of an R package."
    )
  }

  results <- list()

  # R/
  r_dir <- file.path(path, "R")
  if (dir.exists(r_dir)) {
    results <- c(results, list(audit_dir(r_dir, rules = rules,
      recurse = FALSE)))
    for (sub in c("unix", "windows")) {
      sub_dir <- file.path(r_dir, sub)
      if (dir.exists(sub_dir)) {
        results <- c(results, list(audit_dir(sub_dir, rules = rules,
          recurse = FALSE)))
      }
    }
  }

  # src/install.libs.R
  install_libs <- file.path(path, "src", "install.libs.R")
  if (file.exists(install_libs)) {
    results <- c(results, list(audit_file(install_libs, rules = rules)))
  }

  if (length(results) == 0L) {
    message("No scannable files found in: ", label)
    return(.pkgaudit_result(.empty_findings()))
  }

  findings <- do.call(rbind, lapply(results, `[[`, "findings"))
  errors   <- unlist(lapply(results, `[[`, "errors"), use.names = TRUE)
  result   <- .pkgaudit_result(findings, if (length(errors) == 0L) character() else errors)
  result   <- .strip_path_prefix(result, path)

  if (nrow(result$findings) == 0L && length(result$errors) == 0L) {
    message("No security findings in: ", label)
  }
  result
}
