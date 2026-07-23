#' Audit an R source package tarball for security-relevant files and code
#'
#' Extracts a source package tarball to a temporary directory, applies
#' [audit_package()], removes the temporary directory, and returns the result.
#' This is the typical pre-install workflow: audit a downloaded tarball and
#' review the findings before calling [utils::install.packages()].
#'
#' @param path Path to a `.tar.gz` source package tarball.
#' @param rules Named list of rules as returned by [load_rules()]. Defaults to
#'   the rules bundled with the package.
#' @param temp_dir Directory used for extraction. A unique subdirectory is
#'   created here and removed after auditing regardless of success or failure.
#'   Defaults to [base::tempdir()].
#'
#' @return The same `pkgaudit` object as [audit_package()]. File paths in the
#'   data frames are relative to the package root (e.g. `R/zzz.R`); the
#'   `metadata` records `pkg_is_tarball = TRUE`, `pkg_path` as the tarball path,
#'   and `pkg_sha256` as the SHA-256 of the tarball as received.
#'
#' @details
#' The package directory audited is the one named after the package, derived
#' from the tarball filename (`<package>_<version>.tar.gz` extracts to
#' `<package>/`). If no directory of that name is present, the tarball is
#' rejected rather than guessing which directory to audit.
#'
#' @examples
#' \dontrun{
#' result <- audit_tarball("path/to/package_1.0.0.tar.gz")
#' result$patterns
#' }
#'
#' @export
audit_tarball <- function(
  path,
  rules    = load_rules(),
  temp_dir = tempdir()
) {
  stopifnot(is.character(path), length(path) == 1L, file.exists(path))
  stopifnot(is.list(rules), length(names(rules)) == 3L)
  stopifnot(is.character(temp_dir), length(temp_dir) == 1L)

  # Hash the tarball as received, before extraction, as its provenance record.
  tarball_sha256 <- digest::digest(path, algo = "sha256", file = TRUE)

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

  tar_name <- sub("\\.(tar\\.gz|tgz|tar\\.bz2|tar\\.xz|tar)$", "", basename(path))
  pkg_name <- sub("_.*$", "", tar_name)
  pkg_dir  <- file.path(extract_dir, pkg_name)

  if (!nzchar(pkg_name) || !dir.exists(pkg_dir)) {
    stop(
      "No directory named '", pkg_name, "' found after extracting ",
      basename(path), ".\n",
      "A source package tarball must extract to a directory named after the ",
      "package (without the version)."
    )
  }

  audit_package(
    pkg_dir,
    rules   = rules,
    .origin = list(path = path, sha256 = tarball_sha256, is_tarball = TRUE)
  )
}
