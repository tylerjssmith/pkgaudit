#' Audit all R source files in a directory for security-relevant patterns
#'
#' Recursively finds R source files matching `pattern`, applies [audit_file()]
#' to each, and returns a combined data frame of all findings.
#'
#' @param path Path to a directory containing R source files.
#' @param rules Named list of rule objects as returned by [load_rules()].
#' @param pattern Regular expression matching R source file names. Defaults to
#'   files with `.R` or `.r` extension.
#' @param recurse Logical indicating whether to search subdirectories
#'   recursively. Defaults to `TRUE`.
#'
#' @return A data frame of findings across all files in the directory, with
#'   the same columns as [audit_file()]. Returns an empty data frame with the
#'   correct columns if no findings are produced.
#'
#' @examples
#' \dontrun{
#' rules    <- load_rules()
#' findings <- audit_dir("R/", rules = rules)
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
    full.names = TRUE
  )

  if (length(files) == 0L) {
    message("No R source files found in: ", path)
    return(.empty_findings())
  }

  results <- lapply(files, audit_file, rules = rules)
  results <- Filter(Negate(is.null), results)

  if (length(results) == 0L) return(.empty_findings())
  do.call(rbind, results)
}


# Helpers ----------------------------------------------------------------------
# Returns an empty data frame with the correct column structure so that callers
# can expect the same schema regardless of whether findings were produced.
.empty_findings <- function() {
  data.frame(
    file    = character(0L),
    line    = integer(0L),
    column  = integer(0L),
    rule    = character(0L),
    message = character(0L),
    type    = character(0L),
    attck   = character(0L),
    stringsAsFactors = FALSE
  )
}
