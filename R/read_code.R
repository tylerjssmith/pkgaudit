# This script reads a file context into the code streams an analyzer can work
# on. It is the only place in the scan that touches a file being audited, so the
# limits protecting against hostile input live here and apply to every file
# type rather than to one of them.

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

  size <- suppressWarnings(file.size(path))
  if (!is.na(size) && size > .max_scan_bytes) {
    return(list(lines = NULL, error = sprintf(
      "File is %.0f MB, above the %.0f MB scanning limit, and was not read.",
      size / 1024^2, .max_scan_bytes / 1024^2
    )))
  }

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


# --- Streams ------------------------------------------------------------------

# Read one file context into the code streams it contains.
#
# A stream is the unit the scan actually analyzes: a run of code in one
# language, tagged with the code context it belongs to. Most files hold exactly
# one. A help file holds two -- its examples and its \Sexpr macros -- which run
# at different phases and so cannot share a context.
#
# Returns list(streams, errors). Each stream is a list of:
#   language  "R" or "shell"; selects the analyzer
#   context   the code context to attribute patterns to, or NA to compute it
#             from the parse tree
#   lines     character vector, aligned to the lines of the source file
#
# Dispatch is on the file-context rule's type. A type with no reader yields no
# streams, which is how "other" is reported but never read.
.read_streams <- function(path, type, file_context, macros = NULL) {
  errors <- .empty_errors()
  none   <- function() list(streams = list(), errors = errors)

  if (identical(type, "Rd")) {
    rd <- extract_Rd_code(path, macros = macros)
    if (!is.null(rd$error)) {
      errors <- rbind(errors, .error_row(
        stage = "extract_Rd_code", file_context = file_context,
        message = rd$error
      ))
      # Whatever was recovered is still scanned; the error records that the
      # account of the file is incomplete.
    }
    streams <- list()
    for (part in list(list(text = rd$examples, context = .context_rd_examples),
                      list(text = rd$sexpr,    context = .context_rd_sexpr))) {
      if (!nzchar(trimws(part$text))) next
      streams[[length(streams) + 1L]] <- list(
        language = "R",
        context  = part$context,
        lines    = strsplit(part$text, "\n", fixed = TRUE)[[1L]]
      )
    }
    return(list(streams = streams, errors = errors))
  }

  language <- switch(type, R = "R", shell = "shell", make = "shell", NULL)
  if (is.null(language)) return(none())

  read <- read_code(path)
  if (!is.null(read$error)) {
    errors <- rbind(errors, .error_row(
      stage = "read_code", file_context = file_context, message = read$error
    ))
  }
  if (is.null(read$lines)) return(list(streams = list(), errors = errors))

  list(
    streams = list(list(language = language, context = NA_character_,
                        lines = read$lines)),
    errors  = errors
  )
}
