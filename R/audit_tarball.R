#' Audit an R source package tarball
#'
#' Finds security-relevant file and code contexts and code patterns for review
#' before an R source package tarball is trusted.
#'
#' @param path Path to a gzip-compressed or uncompressed R source package
#'   tarball (`.tar.gz`, `.tgz`, or `.tar`). bzip2/xz archives are not
#'   supported.
#' @param rules Named list of rules. Defaults to the rules bundled with the
#'   package as returned by [load_rules()].
#' @param temp_dir Directory used for extraction. A unique subdirectory is
#'   created here and removed after auditing regardless of success or failure.
#'   Defaults to [base::tempdir()].
#' @inheritParams validate_tar
#'
#' @return The same `pkgaudit` object as [audit_package()]: a named list with
#' class `pkgaudit` containing four data frames and a `metadata` list.
#'
#' @details
#' Extracts a source package tarball to a temporary directory, applies
#' [audit_package()], removes the temporary directory, and returns the result.
#' This is the typical pre-install workflow: audit a downloaded tarball and
#' review the findings before calling [utils::install.packages()].
#'
#' Before extracting anything, the tarball is validated with [validate_tar()],
#' which fails closed on link entries, path traversal, absolute paths,
#' decompression bombs, and archives without exactly one top-level directory.
#'
#' After extraction, the tarball filename must be consistent with the top-level
#' directory it produced (e.g. `foo_0.1.0.tar.gz` must extract to `foo/`);
#' otherwise the tarball is rejected.
#'
#' The audited `DESCRIPTION` is then checked against the tarball filename: if
#' the `Package` name or `Version` disagrees with the name and version implied
#' by the filename (`foo` and `0.1.0` for `foo_0.1.0.tar.gz`), a warning is
#' issued. The `DESCRIPTION` values are authoritative and are what the returned
#' object reports.
#'
#' @examples
#' \dontrun{
#' result <- audit_tarball("path/to/foo_0.1.0.tar.gz")
#' print(result)
#' }
#'
#' @export
audit_tarball <- function(
  path,
  rules       = load_rules(),
  temp_dir    = tempdir(),
  max_entries = 100000L,
  max_bytes   = 2 * 1024^3,
  max_ratio   = Inf
) {
  stopifnot(is.character(path), length(path) == 1L, file.exists(path))
  stopifnot(is.list(rules), length(names(rules)) == 3L)
  stopifnot(is.character(temp_dir), length(temp_dir) == 1L)

  # validate_tar() reads gzip/uncompressed tar only
  if (!grepl("\\.(tar\\.gz|tgz|tar)$", path, ignore.case = TRUE)) {
    stop("audit_tarball(): unsupported archive '", basename(path),
         "'; expected .tar.gz, .tgz, or .tar.", call. = FALSE)
  }

  validate_tar(path, max_entries = max_entries, max_bytes = max_bytes,
               max_ratio = max_ratio)

  # hash tarball as received as its provenance record before extraction
  tarball_sha256 <- digest::digest(path, algo = "sha256", file = TRUE)

  extract_dir <- .extract_tarball(path, temp_dir)
  on.exit(
    if (dir.exists(extract_dir)) unlink(extract_dir, recursive = TRUE),
    add = TRUE
  )

  ex <- .validate_tarball_extraction(path, extract_dir)

  result <- audit_package(
    ex$pkg_dir,
    rules   = rules,
    .origin = list(
      path       = path,
      sha256     = tarball_sha256,
      is_tarball = TRUE
    )
  )

  .validate_tarball_name(
    path, ex$tar_name, ex$pkg_name,
    result$metadata$pkg_name, result$metadata$pkg_version
  )

  result
}


# Create a unique extraction subdirectory under temp_dir and untar `path` into
# it, returning the directory. Fails closed: on any error the just-created
# directory is removed here (via a transient on.exit that fires only when `ok`
# is still FALSE), so a failed extraction never leaks a temp dir. On success the
# directory is returned undeleted and the caller (audit_tarball()) owns its
# cleanup for the remainder of the audit.
.extract_tarball <- function(path, temp_dir) {
  extract_dir <- tempfile(tmpdir = temp_dir)
  ok <- FALSE
  on.exit(if (!ok && dir.exists(extract_dir)) {
    unlink(extract_dir, recursive = TRUE)
  })

  if (!dir.create(extract_dir, recursive = TRUE, showWarnings = FALSE)) {
    stop("Failed to create temporary extraction directory: ", extract_dir)
  }

  rc <- utils::untar(path, exdir = extract_dir, tar = "internal")
  if (!identical(rc, 0L)) {
    stop("untar() returned non-zero exit code: ", rc)
  }

  ok <- TRUE
  extract_dir
}


# Derive the expected package directory from the tarball filename and confirm
# the extraction produced it (`<package>_<version>.tar.gz` -> `<package>/`).
# Fails closed with a plain error. Returns the validated package directory plus
# the parsed names, which the caller reuses for the filename/DESCRIPTION
# provenance check.
.validate_tarball_extraction <- function(path, extract_dir) {
  tar_name <- sub("\\.(tar\\.gz|tgz|tar)$", "", basename(path),
    ignore.case = TRUE)
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

  list(pkg_dir = pkg_dir, pkg_name = pkg_name, tar_name = tar_name)
}


# Compare the tarball filename's package/version (parsed by
# .validate_tarball_extraction()) against the audited DESCRIPTION and, on any
# disagreement, signal a `pkgaudit_provenance_mismatch` condition. It subclasses
# `warning`, so a caller sees a normal warning but can also catch it by class and
# read its structured fields instead of parsing the message. The DESCRIPTION
# values still win; this only flags a possible mislabeled or repackaged tarball.
# Called for its side effect.
.validate_tarball_name <- function(path, tar_name, pkg_name, desc_name, desc_version) {
  fname_version <- if (grepl("_", tar_name)) sub("^[^_]*_", "", tar_name) else NA_character_

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

  invisible(NULL)
}
