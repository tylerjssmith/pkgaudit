#' Audit an R source package
#'
#' Finds security-relevant file and code contexts and code patterns for review
#' before an R source package is trusted.
#'
#' @param path Path to an R source package root directory. Defaults to the
#'   current directory.
#' @param rules Named list of rules. Defaults to the rules bundled with the
#'   package as returned by [load_rules()].
#' @param .origin Internal. Used by [audit_tarball()] to record tarball
#'   provenance. Leave `NULL` for a directory scan.
#'
#' @return A [new_pkgaudit()] object: a named list with class `pkgaudit`
#'   containing four data frames and a `metadata` list.
#'   \describe{
#'     \item{file_contexts}{`rule`, `file_context`, `message`.}
#'     \item{code_contexts}{`rule`, `file_context`, `line_number`,
#'       `column_number`, `message`. Join to `file_contexts` on `file_context`.}
#'     \item{patterns}{`rule`, `file_context`, `line_number`,
#'       `column_number`, `message`, `attck`, `code_context`. Join to the other
#'       tables on `file_context`, and to `code_contexts$rule` on
#'       `code_context`.}
#'     \item{errors}{`stage`, `file_context`, `rule`, `message`.}
#'     \item{metadata}{List of `pkg_name`, `pkg_version`, `pkg_path`,
#'       `pkg_is_tarball`, `pkg_sha256`, `pkgaudit_version`,
#'       `pkgaudit_rules_version`, `pkgaudit_rules_sha256`, and `scanned`.}
#'   }
#'
#' @details
#' Recoverable failures in the orchestrated finders are collected in the
#' `errors` data frame rather than aborting the audit. File paths in every
#' returned data frame are relative to the package root.
#'
#' Each findings data frame also carries one logical column per package
#' lifecycle phase -- `at_autoconf`, `at_build`, `at_check`, `at_install_src`,
#' `at_install_bin`, `on_load`, `on_attach`, `on_unload`, and `on_detach` --
#' which is `TRUE` when that finding's code runs during the phase, so findings
#' can be filtered by when they execute. A file or code context takes its phases
#' from the rule that matched; a pattern inherits them from its `code_context`.
#' A pattern in an ordinary function is `FALSE` for every phase: it runs only if
#' something calls it. A finding can belong to several phases, so the phase
#' columns do not partition the rows.
#'
#' When called by [audit_tarball()], `.origin` is a list with `path`, `sha256`,
#' and `is_tarball`, which are used for the `metadata` list. When calling
#' [audit_package()].on a package directory directly, leave `NULL`, in which
#' case the directory is hashed with [hash_manifest()].
#'
#' @examples
#' \dontrun{
#' rules  <- load_rules()
#' result <- audit_package("/path/to/somepackage", rules = rules)
#' result$file_contexts
#' result$patterns
#' print(result)
#' }
#'
#' @export
audit_package <- function(path = ".", rules = load_rules(), .origin = NULL) {
  stopifnot(is.character(path), length(path) == 1L, dir.exists(path))
  stopifnot(
    is.list(rules),
    all(c("file_contexts", "code_contexts", "patterns", "phases") %in%
          names(rules))
  )

  # The finders build frames without phase columns; phases are attached once,
  # from rules$phases, after every script has been scanned.
  errors        <- .empty_errors()
  code_contexts <- .empty_code_contexts(with_phases = FALSE)
  patterns      <- .empty_patterns(with_phases = FALSE)

  fc            <- find_file_contexts(path, rules$file_contexts)
  file_contexts <- fc$file_contexts
  errors        <- rbind(errors, fc$errors)

  scripts <- find_scripts(path)

  for (script in scripts) {
    file_context <- .relativize(script, path)

    parsed <- parse_script(script)
    if (!is.null(parsed$error)) {
      errors <- rbind(errors, .error_row(
        stage        = "parse_script",
        file_context = file_context,
        message      = parsed$error
      ))
      next
    }
    tree <- parsed$tree

    cc            <- find_code_contexts(tree, rules$code_contexts, file_context)
    code_contexts <- rbind(code_contexts, cc$code_contexts)
    errors        <- rbind(errors, cc$errors)

    fp     <- find_patterns(tree, rules$patterns, file_context)
    errors <- rbind(errors, fp$errors)

    pat <- fp$patterns
    if (nrow(pat) > 0L) {
      pat <- determine_code_contexts(tree, pat, rules)
    } else {
      pat$code_context <- character(0L)
    }
    # drop the node handle before accumulating; rbind() ignores attributes.
    attr(pat, "nodes") <- NULL
    patterns <- rbind(
      patterns,
      pat[, names(.empty_patterns(with_phases = FALSE)), drop = FALSE]
    )
  }

  file_contexts <- .attach_phases(file_contexts, rules$phases)
  code_contexts <- .attach_phases(code_contexts, rules$phases)
  patterns      <- .resolve_pattern_phases(patterns, rules$phases)

  # provenance: hash the tarball as received when scanning one (via
  # audit_tarball), otherwise hash a manifest of the directory.
  if (is.null(.origin)) {
    pkg_is_tarball <- FALSE
    pkg_path       <- path
    pkg_sha256     <- tryCatch(hash_manifest(path)$hash,
                               error = function(e) NA_character_)
  } else {
    pkg_is_tarball <- isTRUE(.origin$is_tarball)
    pkg_path       <- .origin$path
    pkg_sha256     <- .origin$sha256
  }

  metadata <- .build_metadata(path, pkg_path, pkg_is_tarball, pkg_sha256)

  new_pkgaudit(
    file_contexts = file_contexts,
    code_contexts = code_contexts,
    patterns      = patterns,
    errors        = errors,
    metadata      = metadata
  )
}

# --- Metadata construction ----------------------------------------------------

# Build the nine-field metadata list for a scanned package. Package name and
# version come from DESCRIPTION and are NA (never an error) when it is missing or
# malformed. The rules version and hash describe the bundled rules database.
.build_metadata <- function(pkg, pkg_path, pkg_is_tarball, pkg_sha256) {
  desc <- .read_description(pkg)
  list(
    pkg_name               = desc$name,
    pkg_version            = desc$version,
    pkg_path               = pkg_path,
    pkg_is_tarball         = pkg_is_tarball,
    pkg_sha256             = pkg_sha256,
    pkgaudit_version       = .pkgaudit_version(),
    pkgaudit_rules_version = tryCatch(rules_version(), error = function(e) NA_character_),
    pkgaudit_rules_sha256  = .rules_db_sha256(),
    scanned                = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
}

# Read Package and Version from a package's DESCRIPTION. Returns NA_character_
# for either field when DESCRIPTION is missing, unparseable, or lacks it -- a
# malformed package must not abort the scan.
.read_description <- function(pkg) {
  out  <- list(name = NA_character_, version = NA_character_)
  desc <- file.path(pkg, "DESCRIPTION")
  if (!file.exists(desc) || dir.exists(desc)) return(out)

  dcf <- tryCatch(suppressWarnings(read.dcf(desc)), error = function(e) NULL)
  if (is.null(dcf) || nrow(dcf) == 0L) return(out)

  pick <- function(fieldname) {
    if (!fieldname %in% colnames(dcf)) return(NA_character_)
    v <- unname(dcf[1L, fieldname])
    if (is.na(v) || !nzchar(trimws(v))) NA_character_ else trimws(v)
  }
  out$name    <- pick("Package")
  out$version <- pick("Version")
  out
}

# Installed pkgaudit version, or NA if it cannot be determined.
.pkgaudit_version <- function() {
  tryCatch(as.character(utils::packageVersion("pkgaudit")),
           error = function(e) NA_character_)
}

# The published SHA-256 of the bundled rules database, read from its sidecar
# (the value load_rules() verifies the database against). NA if unavailable.
.rules_db_sha256 <- function(db_path = .db_path()) {
  sidecar <- paste0(db_path, ".sha256")
  tryCatch(trimws(readLines(sidecar, warn = FALSE)[[1L]]),
           error = function(e) NA_character_)
}
