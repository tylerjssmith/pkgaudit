#' Find security-relevant expressions in a shell script or Make-like file
#'
#' Finds expressions -- regular-expression matches in a file R executes through
#' a shell or through make (e.g., `configure`, `src/Makevars`).
#'
#' @param path Absolute path to the file to scan.
#' @param regex_rules Data frame of regex rules (`rules$regex` from
#'   [load_rules()]), with columns `name`, `regex`, `message`, and `attck`.
#' @param file_context Package-root-relative path of the file, carried through
#'   for joining to the file-contexts table.
#'
#' @return A list with two data frames:
#'   \describe{
#'     \item{expressions}{Data frame with columns `rule` (the matching rule's
#'       name), `file_context`, `line_number`, `column_number`, `message`,
#'       `attck`. The phase columns are not set here; [audit_package()] attaches
#'       them from the file context the file belongs to.}
#'     \item{errors}{Data frame with columns `stage`, `file_context`, `rule`,
#'       `message`.}
#'   }
#'
#' @details
#' The file is read as lines, and each rule's regular expression is evaluated
#' against all of them with `base::gregexpr()` using `perl = TRUE`,
#' `ignore.case = FALSE`, and `useBytes = FALSE`. Every match is an expression
#' found, reported at the line it occurs on and the character position it starts
#' at; a line matched more than once yields one row per match. A failing regular
#' expression (including one R reports only as a warning) is recorded in the
#' errors data frame before the loop moves on to the next rule.
#'
#' Matching text is inherently less precise than matching a parse tree: an
#' expression has no syntactic structure behind it, so a match inside a comment,
#' a quoted string, or a branch that never runs is reported the same as a live
#' command. Findings are candidates for review, not confirmed behavior.
#'
#' @section Security considerations:
#' A file being audited is untrusted input, so two limits are enforced before it
#' is matched against. A file larger than 10 MB is not read at all, and lines
#' that are not valid UTF-8 are blanked before matching. Both are recorded as
#' errors, so the summary reports the lost coverage rather than a clean scan of
#' a file that was never fully examined. Blanking rather than dropping a line
#' keeps the line numbers of everything after it correct.
#'
#' @keywords internal
find_regex <- function(path, regex_rules, file_context) {
  stopifnot(is.character(path), length(path) == 1L)

  rows   <- list()
  errors <- .empty_errors()
  empty  <- function() {
    list(expressions = .empty_expressions(with_phases = FALSE), errors = errors)
  }

  if (is.null(regex_rules) || nrow(regex_rules) == 0L) return(empty())

  read <- .read_lines_safe(path)
  if (inherits(read$lines, "condition")) {
    errors <- rbind(errors, .error_row(
      stage        = "find_regex",
      file_context = file_context,
      message      = conditionMessage(read$lines)
    ))
    return(empty())
  }
  if (!is.na(read$skipped)) {
    errors <- rbind(errors, .error_row(
      stage        = "find_regex",
      file_context = file_context,
      message      = read$skipped
    ))
  }
  lines <- read$lines

  for (i in seq_len(nrow(regex_rules))) {
    rule    <- regex_rules[i, , drop = FALSE]
    matches <- .gregexpr_safe(rule$regex, lines)

    if (inherits(matches, "condition")) {
      errors <- rbind(errors, .error_row(
        stage        = "find_regex",
        file_context = file_context,
        rule         = rule$name,
        message      = conditionMessage(matches)
      ))
      next
    }

    # gregexpr() reports a line with no match as the single position -1.
    starts <- lapply(matches, function(m) {
      pos <- as.integer(m)
      pos[pos > 0L]
    })
    n <- lengths(starts)
    if (sum(n) == 0L) next

    rows[[length(rows) + 1L]] <- data.frame(
      rule          = rule$name,
      file_context  = file_context,
      line_number   = rep(seq_along(lines), n),
      column_number = unlist(starts, use.names = FALSE),
      message       = rule$message,
      attck         = rule$attck,
      stringsAsFactors = FALSE
    )
  }

  expressions <- if (length(rows) == 0L) {
    .empty_expressions(with_phases = FALSE)
  } else {
    do.call(rbind, rows)
  }

  list(expressions = expressions, errors = errors)
}


# The largest file this scans. A source package is untrusted input, and reading
# an arbitrarily large file into memory to match against would let a malformed
# or hostile package exhaust the auditing machine. Well above any real configure
# script, which autoconf generates at a few hundred kilobytes.
.max_scan_bytes <- 10 * 1024^2


# Read a file as lines for matching, refusing what cannot be scanned safely.
#
# Returns a list of `lines` -- the character vector, or the caught condition if
# the file could not be read or was too large -- and `skipped`, a message naming
# the coverage lost within a file that was read, or NA when none was.
#
# Lines that are not valid UTF-8 are replaced with an empty line rather than
# dropped: gregexpr() with useBytes = FALSE would otherwise fail on the whole
# file, and dropping them would shift every subsequent line number.
.read_lines_safe <- function(path) {
  size <- suppressWarnings(file.size(path))
  if (!is.na(size) && size > .max_scan_bytes) {
    return(list(
      lines = simpleError(sprintf(
        "File is %.0f MB, above the %.0f MB scanning limit, and was not read.",
        size / 1024^2, .max_scan_bytes / 1024^2
      )),
      skipped = NA_character_
    ))
  }

  lines <- tryCatch(
    withCallingHandlers(
      readLines(path, warn = FALSE),
      warning = function(w) stop(conditionMessage(w))
    ),
    error = function(e) e
  )
  if (inherits(lines, "condition")) {
    return(list(lines = lines, skipped = NA_character_))
  }

  valid <- validUTF8(lines)
  valid[is.na(valid)] <- FALSE
  if (all(valid)) return(list(lines = lines, skipped = NA_character_))

  lines[!valid] <- ""
  list(lines = lines, skipped = sprintf(
    "%d line(s) are not valid UTF-8 and were not scanned.", sum(!valid)
  ))
}


# Evaluate a regular expression over a character vector, promoting warnings
# (e.g. a regex R accepts but cannot apply to the input) to errors so a rule
# that cannot be evaluated is caught rather than silently matching nothing.
# Returns the match positions on success or the caught condition on failure.
.gregexpr_safe <- function(regex, lines) {
  tryCatch(
    withCallingHandlers(
      gregexpr(regex, lines, ignore.case = FALSE, perl = TRUE,
               useBytes = FALSE),
      warning = function(w) stop(conditionMessage(w))
    ),
    error = function(e) e
  )
}
