# This script reads a file being audited into lines, and holds the limits
# protecting against hostile input. The size limit is enforced by
# extract_segments() before it dispatches, so it holds for every file type; the
# UTF-8 handling covers what read_code() returns, which is everything but help
# files.

#' Read a file context as lines
#'
#' Reads a file being audited into the character vector its analyzers work on.
#'
#' @param path Absolute path to the file to read.
#'
#' @return A list with two elements:
#'   \describe{
#'     \item{lines}{Character vector of lines, or `NULL` when the file could not
#'       be read.}
#'     \item{error}{`NULL` when the whole file was read, otherwise a character
#'       message. A message with `lines` present means the file was read but
#'       part of it could not be scanned.}
#'   }
#'
#' @section Security considerations:
#' A file being audited is untrusted input, so two limits are enforced. A file
#' larger than 10 MB is not read at all: reading an arbitrarily large file into
#' memory would let a malformed or hostile package exhaust the auditing machine.
#' Lines that are not valid UTF-8 are replaced with an empty line rather than
#' dropped, since dropping them would shift the line numbers of everything after
#' them, and matching against them would fail for the whole file.
#'
#' Both cases are reported through `error`, so the scan records the coverage it
#' lost instead of reporting a clean read of a file it never fully examined.
#'
#' @keywords internal
read_code <- function(path) {
  stopifnot(is.character(path), length(path) == 1L)

  oversize <- .over_scan_limit(path)
  if (!is.null(oversize)) return(list(lines = NULL, error = oversize))

  lines <- tryCatch(
    withCallingHandlers(
      readLines(path, warn = FALSE),
      warning = function(w) stop(conditionMessage(w))
    ),
    error = function(e) e
  )
  if (inherits(lines, "condition")) {
    return(list(lines = NULL, error = conditionMessage(lines)))
  }

  valid <- validUTF8(lines)
  valid[is.na(valid)] <- FALSE
  if (all(valid)) return(list(lines = lines, error = NULL))

  lines[!valid] <- ""
  list(lines = lines, error = sprintf(
    "%d line(s) are not valid UTF-8 and were not scanned.", sum(!valid)
  ))
}


# The largest file the scan will read. Well above any real source file: an
# autoconf-generated configure runs to a few hundred kilobytes.
.max_scan_bytes <- 10 * 1024^2

# The message for a file above that limit, or NULL for one within it. Every
# reader of an audited file goes through this, so the limit holds whatever the
# file's type and is refused in the same words.
.over_scan_limit <- function(path) {
  size <- suppressWarnings(file.size(path))
  if (is.na(size) || size <= .max_scan_bytes) return(NULL)
  sprintf(
    "File is %.0f MB, above the %.0f MB scanning limit, and was not read.",
    size / 1024^2, .max_scan_bytes / 1024^2
  )
}
