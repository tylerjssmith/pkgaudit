#' Audit an R source package for security-relevant files and code
#'
#' Finds security-relevant file and code contexts and code patterns for review
#' before a package is trusted.
#'
#' The scan proceeds in four passes:
#' \enumerate{
#'   \item [find_file_contexts()] -- security-relevant files (e.g. `configure`,
#'     `src/Makevars`, `src/install.libs.R`);
#'   \item [find_scripts()] -- R scripts R evaluates at install/load time;
#'   \item for each script, [parse_script()] then [find_code_contexts()] and
#'     [find_patterns()];
#'   \item [determine_code_contexts()] -- attribute each pattern to the code
#'     context it executes in.
#' }
#'
#' Recoverable failures in the orchestrated finders are collected in the
#' `errors` data frame rather than aborting the audit. File paths in every
#' returned data frame are relative to the package root.
#'
#' @param pkg Path to the root directory of the R source package to audit.
#'   Defaults to the current directory.
#' @param rules Named list of rules as returned by [load_rules()]. Defaults to
#'   the rules bundled with the package.
#' @param .origin Internal. Used by [audit_tarball()] to record tarball
#'   provenance: a list with `path`, `sha256`, and `is_tarball`. Leave `NULL`
#'   for a directory scan, in which case the directory is hashed with
#'   [hash_manifest()].
#'
#' @return A [new_pkgaudit()] object: a named list with class `pkgaudit`
#'   containing four data frames and a `metadata` list.
#'   \describe{
#'     \item{file_contexts}{`file_context`, `file_path`, `message`.}
#'     \item{code_contexts}{`code_context`, `file_context`, `line_number`,
#'       `column_number`, `message`. Join to `file_contexts` on `file_context`.}
#'     \item{patterns}{`pattern`, `file_context`, `line_number`,
#'       `column_number`, `message`, `attck`, `code_context`. Join to the other
#'       tables on `file_context` and `code_context`.}
#'     \item{errors}{`stage`, `file_context`, `rule`, `message`.}
#'     \item{metadata}{List of `pkg_name`, `pkg_version`, `pkg_path`,
#'       `pkg_is_tarball`, `pkg_sha256`, `pkgaudit_version`,
#'       `pkgaudit_rules_version`, `pkgaudit_rules_sha256`, and `scanned`.}
#'   }
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
audit_package <- function(pkg = ".", rules = load_rules(), .origin = NULL) {
  stopifnot(is.character(pkg), length(pkg) == 1L, dir.exists(pkg))
  stopifnot(is.list(rules), length(names(rules)) == 3L)

  errors        <- .empty_errors()
  code_contexts <- .empty_code_contexts()
  patterns      <- .empty_patterns()

  fc            <- find_file_contexts(pkg, rules$file_contexts)
  file_contexts <- fc$file_contexts
  errors        <- rbind(errors, fc$errors)

  scripts <- find_scripts(pkg)

  for (script in scripts) {
    file_context <- .relativize(script, pkg)

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
    # Drop the node handle before accumulating; rbind() ignores attributes.
    attr(pat, "nodes") <- NULL
    patterns <- rbind(patterns, pat[, names(.empty_patterns()), drop = FALSE])
  }

  # Provenance: hash the tarball as received when scanning one (via
  # audit_tarball), otherwise hash a manifest of the directory.
  if (is.null(.origin)) {
    pkg_is_tarball <- FALSE
    pkg_path       <- pkg
    pkg_sha256     <- tryCatch(hash_manifest(pkg)$hash,
                               error = function(e) NA_character_)
  } else {
    pkg_is_tarball <- isTRUE(.origin$is_tarball)
    pkg_path       <- .origin$path
    pkg_sha256     <- .origin$sha256
  }

  metadata <- .build_metadata(pkg, pkg_path, pkg_is_tarball, pkg_sha256)

  new_pkgaudit(
    file_contexts = file_contexts,
    code_contexts = code_contexts,
    patterns      = patterns,
    errors        = errors,
    metadata      = metadata
  )
}
