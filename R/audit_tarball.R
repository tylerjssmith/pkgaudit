#' Audit an R source package tarball for security-relevant patterns
#'
#' Extracts a source package tarball to a temporary directory, applies
#' [audit_package()], removes the temporary directory, and returns the result.
#' This is the primary entry point for auditing packages before installation:
#' the typical workflow is to call `audit_tarball()` on a downloaded tarball
#' and review findings before calling [utils::install.packages()].
#'
#' @param path Path to a `.tar.gz` source package tarball.
#' @param rules Named list of rule objects as returned by [load_rules()].
#'   Defaults to loading stable rules from the bundled database.
#' @param temp_dir Directory used for extraction. A unique subdirectory is
#'   created here and removed after auditing regardless of success or failure.
#'   Defaults to [base::tempdir()].
#'
#' @return A `pkgaudit_result` with the same fields as [audit_package()]:
#'   \describe{
#'     \item{findings}{Data frame of findings with the same columns as
#'       [audit_file()]. File paths are relative to the package root
#'       (e.g., `R/zzz.R`). Zero rows when no patterns match.}
#'     \item{errors}{Named character vector of files that could not be parsed,
#'       where names are relative file paths and values are error messages.
#'       Zero-length when all files were successfully inspected.}
#'   }
#'
#' @examples
#' \dontrun{
#' result <- audit_tarball("path/to/package_1.0.0.tar.gz")
#' result$findings
#' result$errors
#' }
#'
#' @export
audit_tarball <- function(
  path,
  rules    = pkgaudit::load_rules(),
  temp_dir = tempdir()
) {
  stopifnot(is.character(path), length(path) == 1L)
  stopifnot(file.exists(path))
  stopifnot(is.list(rules), length(rules) > 0L)
  stopifnot(is.character(temp_dir), length(temp_dir) == 1L)

  extract_dir <- tempfile(tmpdir = temp_dir)
  on.exit(
    if (dir.exists(extract_dir)) unlink(extract_dir, recursive = TRUE),
    add = TRUE
  )
  if (!dir.create(extract_dir, recursive = TRUE, showWarnings = FALSE)) {
    stop("Failed to create temporary extraction directory: ", extract_dir)
  }

  rc <- utils::untar(path, exdir = extract_dir)
  if (!identical(rc, 0L)) {
    stop("untar() returned non-zero exit code: ", rc)
  }

  pkg_dirs <- list.dirs(extract_dir, recursive = FALSE, full.names = TRUE)
  if (length(pkg_dirs) == 0L) {
    stop("No package directory found after extracting: ", basename(path))
  }

  audit_package(pkg_dirs[[1L]], rules = rules, label = basename(path))
}
