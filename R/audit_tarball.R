#' Audit an R source package tarball
#'
#' Extracts a source package tarball to a temporary directory, applies
#' [audit_package()], removes the temporary directory, and returns the result.
#' This is the typical pre-install workflow: audit a downloaded tarball and
#' review the findings before calling [utils::install.packages()].
#'
#' @param path Path to a `.tar.gz` R source package tarball.
#' @param rules Named list of rules. Defaults to the rules bundled with the
#'   package as returned by [load_rules()].
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
#' The reported package name and version always come from the extracted
#' DESCRIPTION. If the DESCRIPTION `Package` or `Version` disagrees with the
#' corresponding part of the filename (`<package>_<version>.tar.gz`), a warning
#' is issued to flag a possible provenance mismatch (a mislabeled or repackaged
#' tarball); the DESCRIPTION values still win. The warning is a catchable
#' `pkgaudit_provenance_mismatch` condition carrying the filename and DESCRIPTION
#' name/version as fields, so callers can capture it programmatically.
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

  result <- audit_package(
    pkg_dir,
    rules   = rules,
    .origin = list(path = path, sha256 = tarball_sha256, is_tarball = TRUE)
  )

  fname_version <- if (grepl("_", tar_name)) sub("^[^_]*_", "", tar_name) else NA_character_
  desc_name     <- result$metadata$pkg_name
  desc_version  <- result$metadata$pkg_version

  mismatches <- character(0L)
  if (!is.na(desc_name) && !identical(desc_name, pkg_name)) {
    mismatches <- c(mismatches,
      paste0("package name '", pkg_name, "' vs DESCRIPTION Package '", desc_name, "'"))
  }
  if (!is.na(desc_version) && !is.na(fname_version) &&
      !identical(desc_version, fname_version)) {
    mismatches <- c(mismatches,
      paste0("version '", fname_version, "' vs DESCRIPTION Version '", desc_version, "'"))
  }
  if (length(mismatches) > 0L) {
    # Signal a classed condition (subclass of `warning`) so interactive callers
    # see a normal warning while programmatic callers (e.g. audit_cran()) can
    # catch it by class and read the structured fields, not the message string.
    warning(structure(
      class = c("pkgaudit_provenance_mismatch", "warning", "condition"),
      list(
        message = paste0(
          "Tarball '", basename(path),
          "' filename does not match its DESCRIPTION: ",
          paste(mismatches, collapse = "; "), "."
        ),
        call             = NULL,
        filename_name    = pkg_name,
        filename_version = fname_version,
        desc_name        = desc_name,
        desc_version     = desc_version
      )
    ))
  }

  result
}
