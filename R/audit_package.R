#' Audit an R package for security-relevant patterns
#'
#' Scans all R source files in a package for dangerous patterns using the
#' provided rules. Searches recursively from the package root, including
#' hidden files, so code in `inst/`, `exec/`, `tests/`, `vignettes/`, and
#' any other subdirectory is inspected alongside `R/`.
#'
#' @param path Path to the root directory of the R package to audit.
#'   Defaults to the current directory.
#' @param rules Named list of rule objects as returned by [load_rules()].
#'   Defaults to loading stable rules from the bundled database.
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
  rules = pkgaudit::load_rules()
) {
  stopifnot(is.character(path), length(path) == 1L)
  stopifnot(dir.exists(path))
  stopifnot(is.list(rules), length(rules) > 0L)

  if (!file.exists(file.path(path, "DESCRIPTION"))) {
    stop(
      "No DESCRIPTION file found at: ", path, "\n",
      "Ensure 'path' points to the root of an R package."
    )
  }

  result <- audit_dir(path, rules = rules)
  if (nrow(result$findings) == 0L && length(result$errors) == 0L) {
    message("No security findings in: ", path)
  }
  result
}
