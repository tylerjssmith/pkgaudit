#' Run pkgaudit::audit_package() on many packages
#'
#' For each `.tar.gz` source package tarball in `dir`, extracts the package to a
#' temporary directory, runs [audit_package()], removes the temporary directory,
#' and returns all findings as a single tidy data frame.
#'
#' @param dir Path to a directory containing `.tar.gz` source package
#'   tarballs, as downloaded from CRAN or another source repository.
#' @param rules Named list of rule objects as returned by [load_rules()].
#'   Defaults to loading stable rules from the bundled database.
#' @param temp_dir Path to a directory used for temporary extraction. Each
#'   package is extracted here and removed immediately after auditing.
#'   Defaults to a subdirectory of [base::tempdir()].
#' @param pattern Regular expression matching tarball file names. Defaults to
#'   files ending in `.tar.gz`.
#' @param on_error One of `"skip"` (default) or `"stop"`. If `"skip"`, errors
#'   during extraction or auditing are caught, a message is emitted, and
#'   processing continues with the next package. If `"stop"`, the first error
#'   halts the pipeline.
#' @param workers Number of workers. Passed as
#'   parallel::mclapply(mc.cores=workers)
#'
#' @return A named list with three elements:
#'   \describe{
#'     \item{findings}{Data frame of security findings across all packages,
#'       with the columns from [audit_package()] plus `package` and `version`
#'       as the first two columns. Returns an empty data frame with the correct
#'       schema if no findings are produced. Packages with no findings are not
#'       represented.}
#'     \item{errors}{Data frame of parse errors encountered during auditing,
#'       with columns `package`, `version`, `file`, and `error`.}
#'     \item{structure}{Data frame with one row per successfully processed
#'       package and columns `package` (character), `version` (character),
#'       `has_configure` (logical), `has_configure_win` (logical), and
#'       `has_src` (logical). Packages that failed to process are not
#'       represented.}
#'   }
#'
#' @details
#' ## Extraction and cleanup
#' Each tarball is extracted to `temp_dir/<package>_<version>/` using
#' [utils::untar()]. The extracted directory is removed with [base::unlink()]
#' immediately after [audit_package()] returns, whether or not findings were
#' produced and whether or not an error occurred.
#'
#' ## Package name and version parsing
#' Names and versions are parsed from tarball filenames following the CRAN
#' convention `<package>_<version>.tar.gz`. Filenames not matching this
#' pattern are skipped with a warning.
#'
#' ## Progress
#' A message is emitted for each package processed, showing the package name,
#' version, and finding count. This provides visibility into long-running
#' analyses without requiring an external progress bar dependency.
#'
#' @examples
#' \dontrun{
#' # Download a handful of source packages first, e.g. with
#' # download_r_packages()
#' rules    <- load_rules()
#' findings <- run_pipeline("~/cran_source/", rules = rules)
#'
#' # Record the rules version used
#' attr(findings, "rules_version") <- rules_version()
#'
#' # Inspect findings for a specific package
#' findings[findings$package == "somepackage", ]
#' }
#'
#' @importFrom parallel mclapply
#' @export
run_pipeline <- function(
  dir,
  rules    = load_rules(),
  temp_dir = file.path(tempdir(), "pkgaudit"),
  pattern  = "\\.tar\\.gz$",
  on_error = c("skip", "stop"),
  workers  = parallel::detectCores(logical = FALSE) - 1L
) {
  on_error <- match.arg(on_error)
  workers  <- max(1L, as.integer(workers))

  stopifnot(is.character(dir), length(dir) == 1L)
  if (!dir.exists(dir)) {
    stop("dir does not exist: ", dir)
  }
  stopifnot(is.list(rules), length(rules) > 0L)

  tarballs <- list.files(
    dir,
    pattern    = pattern,
    full.names = TRUE
  )

  if (length(tarballs) == 0L) {
    message("No tarballs found in: ", dir)
    return(.empty_pipeline_findings())
  }

  message("Found ", length(tarballs), " tarballs in ", dir)
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

  results <- parallel::mclapply(
    seq_along(tarballs),
    function(i) {
      tarball <- tarballs[[i]]
      meta    <- .parse_tarball_name(tarball)

      if (is.null(meta)) {
        warning(
          "Skipping -- filename does not match <package>_<version>.tar.gz: ",
          basename(tarball)
        )
        return(NULL)
      }

      pkg_name    <- meta$name
      pkg_version <- meta$version
      extract_dir <- file.path(temp_dir, paste0(pkg_name, "_", pkg_version))

      res <- tryCatch(
        .audit_one_tarball(
          tarball     = tarball,
          extract_dir = extract_dir,
          rules       = rules,
          pkg_name    = pkg_name,
          pkg_version = pkg_version
        ),
        error = function(e) {
          msg <- paste0(
            "Error processing ", pkg_name, " ", pkg_version, ": ",
            conditionMessage(e)
          )
          if (on_error == "stop") stop(msg, call. = FALSE)
          message(msg)
          NULL
        }
      )

      n_findings <- if (is.null(res)) "ERROR" else nrow(res$findings)
      n_errors   <- if (is.null(res)) 0L      else nrow(res$errors)
      message(sprintf(
        "[%d/%d] %s %s -- %s finding(s), %d parse error(s)",
        i, length(tarballs), pkg_name, pkg_version, n_findings, n_errors
      ))

      res
    },
    mc.cores       = workers,
    mc.preschedule = TRUE
  )

  results <- Filter(Negate(is.null), results)

  findings_list  <- Filter(function(x) nrow(x) > 0L, lapply(results, `[[`, "findings"))
  errors_list    <- Filter(function(x) nrow(x) > 0L, lapply(results, `[[`, "errors"))
  structure_list <- Filter(Negate(is.null),            lapply(results, `[[`, "structure"))

  findings  <- if (length(findings_list)  > 0L) do.call(rbind, findings_list)  else .empty_pipeline_findings()
  errors    <- if (length(errors_list)    > 0L) do.call(rbind, errors_list)    else .empty_pipeline_errors()
  structure <- if (length(structure_list) > 0L) do.call(rbind, structure_list) else .empty_pipeline_structure()

  rownames(findings)  <- NULL
  rownames(errors)    <- NULL
  rownames(structure) <- NULL

  if (nrow(findings) == 0L) {
    message("No security findings across ", length(tarballs), " packages.")
  }

  n_configure     <- sum(structure$has_configure)
  n_configure_win <- sum(structure$has_configure_win)
  n_src           <- sum(structure$has_src)
  message(sprintf(
    "Structure: %d configure, %d configure.win, %d src/ (of %d packages)",
    n_configure, n_configure_win, n_src, nrow(structure)
  ))

  list(findings = findings, errors = errors, structure = structure)
}


# --- Helpers ------------------------------------------------------------------
# Extract and audit a single tarball, returning a findings data frame with
# package and version columns prepended. Cleanup runs on exit regardless of
# success or failure.
.audit_one_tarball <- function(
  tarball,
  extract_dir,
  rules,
  pkg_name,
  pkg_version
) {
  # Ensure extraction directory is removed on exit -- always, even on error
  on.exit(
    if (dir.exists(extract_dir)) unlink(extract_dir, recursive = TRUE),
    add = TRUE
  )

  dir.create(extract_dir, recursive = TRUE, showWarnings = FALSE)

  rc <- utils::untar(tarball, exdir = extract_dir)
  if (!identical(rc, 0L)) {
    stop("untar() returned non-zero exit code: ", rc)
  }

  # untar() creates a subdirectory named after the package inside extract_dir
  pkg_dirs <- list.dirs(extract_dir, recursive = FALSE, full.names = TRUE)
  if (length(pkg_dirs) == 0L) {
    stop("No directory created by untar() in: ", extract_dir)
  }
  pkg_dir <- pkg_dirs[[1L]]

  # --- Structural inspection --------------------------------------------------
  # Check for configure scripts and src/ directory. Performed against the
  # extracted package directory before auditing so the results are available
  # regardless of whether audit_package() succeeds.
  structure_out <- data.frame(
    package          = pkg_name,
    version          = pkg_version,
    has_configure     = file.exists(file.path(pkg_dir, "configure")),
    has_configure_win = file.exists(file.path(pkg_dir, "configure.win")),
    has_src           = dir.exists( file.path(pkg_dir, "src")),
    stringsAsFactors = FALSE
  )

  # --- Audit ------------------------------------------------------------------
  result <- pkgaudit::audit_package(pkg_dir, rules = rules)

  if (length(result$errors) > 0L) {
    message(sprintf(
      "  %d file(s) failed to parse in %s %s",
      length(result$errors), pkg_name, pkg_version
    ))
  }

  findings <- result$findings
  errors   <- result$errors

  findings_out <- if (nrow(findings) > 0L) {
    cbind(data.frame(package = pkg_name, version = pkg_version), findings)
  } else {
    .empty_pipeline_findings()
  }

  errors_out <- if (length(errors) > 0L) {
    data.frame(
      package = pkg_name,
      version = pkg_version,
      file    = names(errors),
      error   = unname(errors),
      stringsAsFactors = FALSE
    )
  } else {
    .empty_pipeline_errors()
  }

  list(findings = findings_out, errors = errors_out, structure = structure_out)
}


# Parse <package>_<version>.tar.gz from a full path.
# Returns list(name, version) or NULL if the filename does not match.
.parse_tarball_name <- function(path) {
  fname <- basename(path)
  fname <- sub("\\.tar\\.gz$", "", fname)

  # CRAN package names cannot contain underscores; the first _ separates
  # name from version
  parts <- regmatches(fname, regexpr("_", fname), invert = TRUE)[[1L]]
  if (length(parts) != 2L) return(NULL)

  list(name = parts[[1L]], version = parts[[2L]])
}


# Empty data frame with the full pipeline schema
.empty_pipeline_findings <- function() {
  cbind(
    data.frame(
      package = character(0L),
      version = character(0L),
      stringsAsFactors = FALSE
    ),
    pkgaudit:::.empty_findings()
  )
}

.empty_pipeline_errors <- function() {
  data.frame(
    package = character(0L),
    version = character(0L),
    file    = character(0L),
    error   = character(0L),
    stringsAsFactors = FALSE
  )
}

.empty_pipeline_structure <- function() {
  data.frame(
    package           = character(0L),
    version           = character(0L),
    has_configure     = logical(0L),
    has_configure_win = logical(0L),
    has_src           = logical(0L),
    stringsAsFactors  = FALSE
  )
}
