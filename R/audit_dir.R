#' Audit all R source files in a directory for security-relevant patterns
#'
#' Recursively finds R source files matching `pattern`, applies [audit_file()]
#' to each, and returns a combined result.
#'
#' @param path Path to a directory containing R source files.
#' @param rules Named list of rule objects as returned by [load_rules()].
#' @param pattern Regular expression matching R source file names. Defaults to
#'   files with `.R` or `.r` extension.
#' @param recurse Logical indicating whether to search subdirectories
#'   recursively. Defaults to `TRUE`. Hidden files are always included.
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
  rules,
  pattern = "\\.[Rr]$",
  recurse = TRUE
) {
  stopifnot(is.character(path), length(path) == 1L)
  stopifnot(dir.exists(path))
  stopifnot(is.list(rules), length(rules) > 0L)

  files <- list.files(
    path,
    pattern    = pattern,
    recursive  = recurse,
    full.names = TRUE,
    all.files  = TRUE
  )

  if (length(files) == 0L) {
    message("No R source files found in: ", path)
    return(.pkgaudit_result(.empty_findings()))
  }

  results  <- lapply(files, audit_file, rules = rules)
  findings <- do.call(rbind, lapply(results, `[[`, "findings"))
  errors   <- unlist(lapply(results, `[[`, "errors"), use.names = TRUE)

  .pkgaudit_result(findings, if (length(errors) == 0L) character() else errors)
}
