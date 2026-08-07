# This script defines the format(), print(), and summary() methods for the
# pkgaudit S3 object, the print() method for the summary object those return,
# and the display helpers shared across them.

# --- format() and print() Methods ---------------------------------------------

#' Format or print a pkgaudit result
#'
#' `format.pkgaudit()` renders the scan metadata and finding counts as a
#' character vector of lines; `print.pkgaudit()` writes those lines and returns
#' the object invisibly.
#'
#' @param x A `pkgaudit` object.
#' @param path Logical; if `TRUE` (default) include the `Path:` line showing the
#'   local filesystem location scanned. Set `FALSE` to omit local paths.
#' @param ... Ignored, for S3 compatibility.
#'
#' @return `format.pkgaudit()` returns a character vector of lines.
#'   `print.pkgaudit()` returns `x` invisibly.
#'
#' @seealso [summary.pkgaudit()] for a sectioned report of the findings
#'   themselves rather than their counts.
#'
#' @examples
#' \dontrun{
#' result <- audit_package("/path/to/package")
#' print(result)
#' print(result, path = FALSE)   # omit the local Path: line for sharing
#' }
#'
#' @method format pkgaudit
#' @export
format.pkgaudit <- function(x, path = TRUE, ...) {
  n_errors  <- nrow(x$errors)
  err_value <- if (n_errors > 0L) {
    paste0(n_errors, "   (coverage incomplete)")
  } else {
    as.character(n_errors)
  }

  c(
    .section_header("pkgaudit"),
    .metadata_lines(x$metadata, path = path),
    "",
    .field("File contexts:", nrow(x$file_contexts), .count_label_width),
    .field("Code contexts:", nrow(x$code_contexts), .count_label_width),
    .field("Patterns:",      nrow(x$patterns),      .count_label_width),
    .field("Matches:",       nrow(x$matches),   .count_label_width),
    .field("Errors:",        err_value,             .count_label_width)
  )
}


#' @rdname format.pkgaudit
#' @method print pkgaudit
#' @export
print.pkgaudit <- function(x, path = TRUE, ...) {
  writeLines(format(x, path = path, ...))
  invisible(x)
}


# --- summary() and its print() Method -----------------------------------------

#' Summarize a pkgaudit result
#'
#' `summary.pkgaudit()` rolls a scan up into the frequency of each R pattern by
#' the lifecycle phase and code context it executes in, the frequency of each
#' shell or make match by the phase and file context it executes in, both
#' with their MITRE ATT&CK techniques, and the errors, if any. It also collects
#' the distinct file and code contexts found, which the report does not show.
#' `print.summary.pkgaudit()` writes that summary as a sectioned report and
#' returns the object invisibly.
#'
#' @param object A `pkgaudit` object.
#' @param x A `summary.pkgaudit` object.
#' @param path Logical; if `TRUE` (default) include the `Path:` line showing the
#'   local filesystem location scanned. Set `FALSE` to omit local paths.
#'   `summary.pkgaudit()` records the choice in the object it returns;
#'   `print.summary.pkgaudit()` uses that recorded value unless given its own.
#' @param phase Character vector of lifecycle phases to report, e.g.
#'   `"at_load"`, or `"none"` for occurrences that execute in no phase.
#'   `NULL` (default) reports every phase. An unrecognised name is an error.
#' @param ... Ignored, for S3 compatibility.
#'
#' @return `summary.pkgaudit()` returns a `summary.pkgaudit` object: a named list
#'   of four summary data frames, the errors, the scan `metadata`, and the
#'   recorded `path`.
#'   \describe{
#'     \item{file_contexts}{`file_context`: each file context found, once.}
#'     \item{code_contexts}{`code_context`: each code-context rule matched,
#'       once.}
#'     \item{patterns}{`phase`, `code_context`, `rule`, `n`, `attck`: how often
#'       each pattern rule was matched in each code context, split by the
#'       lifecycle phase that context executes in, with the ATT&CK techniques
#'       the rule carries.}
#'     \item{matches}{`phase`, `file_context`, `rule`, `n`, `attck`: how
#'       often each regex rule was matched in each shell script or Make-like
#'       file, split by the lifecycle phase that file executes in.}
#'     \item{errors}{`step`, `script`, `rule`, `error`: the rows of the object's
#'       `errors` data frame, renamed for display.}
#'   }
#'   `print.summary.pkgaudit()` returns `x` invisibly.
#'
#' @details
#' The report opens with the same metadata block as [print.pkgaudit()], then
#' gives the `R Patterns`, `Shell / Make Matches`, and `Errors` sections. A
#' section with nothing to report says so. The `file_contexts` and
#' `code_contexts` summaries are returned for programmatic use but are not part
#' of the report.
#'
#' A pattern occurrence executes in every phase its code context does, and a
#' match in every phase its file context does, so each contributes one row per
#' phase and the `n` column sums to more than the number of occurrences.
#' Occurrences that execute in no phase at all are gathered under `none`.
#'
#' `phase` restricts the report to the phases named. It is the only way to
#' narrow it: the summary has already been expanded by phase, so it cannot be
#' subset afterwards. The default reports every phase, and a filtered report
#' names its phases in the header, so it cannot be mistaken for a full scan.
#'
#' The `Errors` section lists every error, whatever step produced it, and is
#' followed by one note per step stating what scan coverage was lost. An error
#' recorded against a file-context rule is not tied to a script, and one
#' recorded against a script that would not parse is not tied to a rule, so both
#' columns are shown and the inapplicable one is left blank.
#'
#' @seealso [print.pkgaudit()] for the finding counts alone.
#'
#' @examples
#' \dontrun{
#' result <- audit_package("/path/to/package")
#' summary(result)
#' summary(result, path = FALSE)     # omit the local Path: line for sharing
#' summary(result, phase = "at_load")  # only what runs when the package loads
#' summary(result, phase = "none")     # ships, but runs at no phase
#'
#' s <- summary(result)
#' s$patterns                      # pattern frequencies as a data frame
#' s$matches                   # match frequencies as a data frame
#' }
#'
#' @method summary pkgaudit
#' @export
summary.pkgaudit <- function(object, path = TRUE, phase = NULL, ...) {
  phase <- .check_phases(phase)
  structure(
    list(
      file_contexts = .summarize_contexts(object$file_contexts$file_context,
                                          "file_context"),
      code_contexts = .summarize_contexts(object$code_contexts$rule,
                                          "code_context"),
      patterns      = .summarize_findings(object$patterns, "code_context", phase),
      matches       = .summarize_findings(object$matches, "file_context", phase),
      errors        = .summarize_errors(object$errors),
      metadata      = object$metadata,
      path          = isTRUE(path),
      phase         = phase
    ),
    class = "summary.pkgaudit"
  )
}


#' @rdname summary.pkgaudit
#' @method print summary.pkgaudit
#' @export
print.summary.pkgaudit <- function(x, path = x$path, ...) {
  writeLines(.format_summary(x, path = path))
  invisible(x)
}


# The phases a summary was asked for, or NULL for all of them. An unrecognised
# name is refused rather than matching nothing: a report that silently covered
# no phase would read as a package with no findings.
.check_phases <- function(phase) {
  if (is.null(phase)) return(NULL)
  valid <- c(.phase_columns, "none")
  if (!is.character(phase) || length(phase) == 0L || anyNA(phase)) {
    stop("summary(): 'phase' must be a character vector or NULL.", call. = FALSE)
  }
  bad <- setdiff(phase, valid)
  if (length(bad) > 0L) {
    stop("summary(): unknown phase: ", paste(bad, collapse = ", "),
         ". Must be one of: ", paste(valid, collapse = ", "), ".", call. = FALSE)
  }
  unique(phase)
}


# --- Summary Construction -----------------------------------------------------

# Reduce a context column to the distinct values found, in the order first seen,
# as a one-column data frame named for the column summarized.
.summarize_contexts <- function(values, column) {
  df <- data.frame(unique(values), stringsAsFactors = FALSE)
  names(df) <- column
  df
}


# Count findings by the phase and context they execute in, one row per phase,
# context, and rule, carrying each rule's ATT&CK labels. Shared by the two
# findings frames that carry ATT&CK labels: patterns, whose context is the
# `code_context` they sit in, and matches, whose context is the
# `file_context` they were found in.
#
# An occurrence executes in every phase its context does, so it is counted once
# per phase and `n` sums to more than the number of occurrences. An occurrence
# that executes in no phase -- code reached only when something calls it -- is
# gathered under "none". The ATT&CK labels come from the rule, so they are
# constant across a rule's rows and any one of them describes them all.
#
# Rows are ordered by phase in lifecycle order with "none" last, then by context
# and rule name. Context and rule names mix cases, so those two are sorted in
# the C locale: a report of the same scan reads the same wherever it is run.
.summarize_findings <- function(findings, context, phase = NULL) {
  empty <- data.frame(
    phase = character(0L), context = character(0L), rule = character(0L),
    n = integer(0L), attck = character(0L), stringsAsFactors = FALSE
  )
  names(empty)[[2L]] <- context
  if (nrow(findings) == 0L) return(empty)

  levels <- if (is.null(phase)) c(.phase_columns, "none") else phase
  rows   <- lapply(levels, function(phase) {
    in_phase <- if (phase == "none") {
      rowSums(as.matrix(findings[, .phase_columns, drop = FALSE])) == 0L
    } else {
      findings[[phase]]
    }
    if (!any(in_phase)) return(empty)

    found <- findings[in_phase, , drop = FALSE]
    keys  <- paste(found[[context]], found$rule, sep = "\r")
    first <- match(sort(unique(keys), method = "radix"), keys)
    out   <- data.frame(
      phase   = phase,
      context = found[[context]][first],
      rule    = found$rule[first],
      n       = tabulate(match(keys, keys[first]), length(first)),
      attck   = found$attck[first],
      stringsAsFactors = FALSE
    )
    names(out)[[2L]] <- context
    out
  })

  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}


# Rename the errors data frame for display. All four columns are kept: which
# step failed, and both of the fields that identify what failed, since no one
# step sets them both.
.summarize_errors <- function(errors) {
  data.frame(
    step  = errors$step,
    script = errors$file_context,
    rule   = errors$rule,
    error  = errors$message,
    stringsAsFactors = FALSE
  )
}
