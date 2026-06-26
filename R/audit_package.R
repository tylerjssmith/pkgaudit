#' Audit an R package for security issues
#'
#' Scans the `R/` subdirectory of a package for dangerous patterns using the
#' provided rules. Unlike standard `lintr` workflows, `# nolint` comments in the
#' audited package are unconditionally ignored.
#'
#' @param path Path to the root directory of the R package to audit.
#'   Defaults to the current directory.
#' @param rules Named list of rule objects as returned by [load_rules()].
#'   Defaults to loading stable rules from the bundled database.
#'
#' @return A data frame of findings across all files in the directory, with
#'   the same columns as [lint_file()]. Returns an empty data frame with the
#'   correct columns if no findings are produced.
#'
#' @examples
#' \dontrun{
#' # Audit a package with default stable rules
#' rules    <- load_rules()
#' findings <- audit_package("/path/to/somepackage", rules = rules)
#'
#' # Record rules version alongside findings
#' attr(findings, "rules_version") <- rules_version()
#' }
#'
#' @export
audit_package <- function(
  path  = ".",
  rules = load_rules()
) {
  stopifnot(is.character(path), length(path) == 1L)
  stopifnot(dir.exists(path))
  stopifnot(is.list(rules), length(rules) > 0L)

  r_dir <- file.path(path, "R")
  if (!dir.exists(r_dir)) {
    stop(
      "No R/ directory found at: ", path, "\n",
      "Ensure 'path' points to the root of an R package."
    )
  }

  findings <- lint_dir(r_dir, rules = rules)
  if (nrow(findings) == 0L) {
    message("No security findings in: ", path)
  }
  findings
}
