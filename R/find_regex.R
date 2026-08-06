#' Find security-relevant expressions in a shell script or Make-like file
#'
#' Finds expressions -- regular-expression matches in a file R executes through
#' a shell or through make (e.g., `configure`, `src/Makevars`).
#'
#' @param lines Character vector of the file's lines, as returned by
#'   [read_code()].
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
#' Each rule's regular expression is evaluated against every line with
#' `base::gregexpr()` using `perl = TRUE`,
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
#' Reading the file, and the limits that protect against hostile input, are
#' [read_code()]'s responsibility rather than this function's.
#'
#' @keywords internal
find_regex <- function(lines, regex_rules, file_context) {
  stopifnot(is.character(lines))

  rows   <- list()
  errors <- .empty_errors()
  empty  <- function() {
    list(expressions = .empty_expressions(with_phases = FALSE), errors = errors)
  }

  if (is.null(regex_rules) || nrow(regex_rules) == 0L) return(empty())

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
