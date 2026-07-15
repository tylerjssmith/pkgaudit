#' Audit all R source files in a directory for security-relevant patterns
#'
#' Recursively finds R source files matching `pattern`, applies [audit_file()]
#' to each, and returns a combined result.
#'
#' @param path Path to a directory containing R source files.
#' @param rules Named list of rule objects as returned by [load_rules()].
#'   Defaults to loading stable rules from the bundled database.
#' @param pattern Regular expression matching R source file names. Defaults to
#'   files with `.R`, `.r`, `.S`, `.s`, or `.q` extension.
#' @param recurse Logical indicating whether to search subdirectories
#'   recursively. Defaults to `TRUE`. Hidden files are always included.
#' @param exclude_dirs Character vector of subdirectory names to skip. Any
#'   file whose path contains one of these names as a directory component is
#'   excluded. Defaults to `character()` (no exclusions).
#'
#' @return A `pkgaudit_result` with two fields:
#'   \describe{
#'     \item{findings}{Combined data frame of all findings across every file,
#'       with the same columns as [audit_file()]. Zero rows when no patterns
#'       match.}
#'     \item{errors}{Named character vector of files that could not be parsed,
#'       where names are file paths and values are error messages. Zero-length
#'       when all files were successfully inspected.}
#'   }
#'
#' @examples
#' \dontrun{
#' rules  <- load_rules()
#' result <- audit_dir("R/", rules = rules)
#' result$findings
#' result$errors
#' }
#'
#' @export
audit_dir <- function(
  path,
  rules        = load_rules(),
  pattern      = "\\.[qRrSs]$",
  recurse      = TRUE,
  exclude_dirs = character()
) {
  stopifnot(is.character(path), length(path) == 1L)
  stopifnot(dir.exists(path))
  stopifnot(is.list(rules), length(rules) > 0L)
  stopifnot(is.character(exclude_dirs))

  files <- list.files(
    path,
    pattern    = pattern,
    recursive  = recurse,
    full.names = TRUE,
    all.files  = TRUE
  )

  if (length(exclude_dirs) > 0L) {
    sep   <- .Platform$file.sep
    keep  <- !Reduce(`|`, lapply(
      paste0(sep, exclude_dirs, sep),
      grepl, x = files, fixed = TRUE
    ))
    files <- files[keep]
  }

  if (length(files) == 0L) {
    message("No R source files found in: ", path)
    return(.pkgaudit_result(.empty_findings()))
  }

  results  <- lapply(files, audit_file, rules = rules)
  findings <- do.call(rbind, lapply(results, `[[`, "findings"))
  errors   <- unlist(lapply(results, `[[`, "errors"), use.names = TRUE)

  .pkgaudit_result(findings, if (length(errors) == 0L) character() else errors)
}
