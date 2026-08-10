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
#' `summary.pkgaudit()` rolls a scan up into the frequency of each R pattern and
#' each shell or make match by the lifecycle phase it executes in, with their
#' MITRE ATT&CK techniques; how much of the package was read; and the errors, if
#' any. It also collects the distinct file contexts found, which the report does
#' not show.
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
#'     \item{patterns}{`phase`, `rule`, `n`, `attck`: how often each pattern
#'       rule was matched, split by the lifecycle phase its code executes in,
#'       with the ATT&CK techniques the rule carries. The code context a finding
#'       sits in is how its phases were derived rather than a finding of its
#'       own, so it stays on the object's `patterns` frame and out of the
#'       report.}
#'     \item{matches}{`phase`, `rule`, `n`, `attck`: how often each match rule
#'       was matched across the shell scripts and Make-like files, split by the
#'       lifecycle phase those files execute in. Shaped as `patterns` is; which
#'       file each match sits in is on the object's `matches` frame.}
#'     \item{coverage}{`status`, `top_level`, `type`, `files`, `lines`: how much
#'       of the package pkgaudit read, grouped by where the files sit and what
#'       kind they are. `type` is what a file was read as where a rule read it,
#'       and its extension otherwise.}
#'     \item{errors}{`step`, `file_context`, `rule`, `error`: the rows of the
#'       object's `errors` data frame, renamed for display. The report shows
#'       only `step` and `file_context`; the notes are built from the other two.}
#'   }
#'   `print.summary.pkgaudit()` returns `x` invisibly.
#'
#' @details
#' The report opens with the same metadata block as [print.pkgaudit()], then
#' gives the `R Patterns`, `Shell / Make Matches`, `Coverage`, and `Errors`
#' sections. A section with nothing to report says so. The `file_contexts`
#' summary is returned for programmatic use but is not part of the report.
#'
#' `Coverage` is counts with reasons, and deliberately no percentage. Nothing in
#' a package is assumed inert, so coverage never reaches 100% and a ratio would
#' only ever flatter; what a reader needs is which files went unexamined and
#' whether they execute. Which files those are is in the object's own
#' `coverage` frame; the report gives the shape of the package, not the list.
#'
#' A pattern occurrence executes in every phase its code context does, and a
#' match in every phase its file context does, so each contributes one row per
#' phase and the `n` column sums to more than the number of occurrences.
#' Occurrences that execute in no phase at all are gathered under `none`.
#'
#' Both findings tables are grouped by phase and rule alone. Where a finding
#' sits -- the code context of a pattern, the file of a match -- is on the
#' object's own frames; the report answers what runs, and when.
#'
#' `phase` restricts the report to the phases named. It is the only way to
#' narrow it: the summary has already been expanded by phase, so it cannot be
#' subset afterwards. The default reports every phase, and a filtered report
#' names its phases in the header, so it cannot be mistaken for a full scan.
#'
#' The `Errors` section lists every error by step and file context, and is
#' followed by
#' one note per step stating what scan coverage was lost. The rule and the
#' message are left out of the table -- a message is often long enough to wrap
#' the report on its own -- and are in `s$errors` for a caller who wants them.
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
      patterns      = .summarize_findings(object$patterns, phase = phase),
      matches       = .summarize_findings(object$matches, phase = phase),
      coverage      = .summarize_coverage(object$coverage, phase),
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


# --- Coverage -----------------------------------------------------------------

# How much of the package pkgaudit read, by status, location and kind of file.
#
# Grouped by top-level directory and type rather than reduced to a status count,
# because "31 files unexamined" is not actionable and "24 .yaml files under
# inst/" is. `type` is what the file was read as where a rule read it, and its
# extension otherwise -- which is the answer to "what are all those files?".
.summarize_coverage <- function(coverage, phase = NULL) {
  empty <- data.frame(status = character(0L), top_level = character(0L),
                      type = character(0L), files = integer(0L),
                      lines = integer(0L), stringsAsFactors = FALSE)
  coverage <- .in_phase(coverage, phase)
  if (nrow(coverage) == 0L) return(empty)

  top  <- .top_level(coverage$file_context)
  type <- .coverage_type(coverage$file_context, coverage$language)
  key  <- paste(coverage$status, top, type, sep = "\r")

  rows <- lapply(unique(key), function(k) {
    at <- key == k
    data.frame(
      status    = coverage$status[at][[1L]],
      top_level = top[at][[1L]],
      type      = type[at][[1L]],
      files     = sum(at),
      lines     = if (all(is.na(coverage$lines[at]))) NA_integer_
                  else sum(coverage$lines[at], na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  # Statuses in the order they represent, best-read first, then by location and
  # by kind of file within it -- so a reader following a directory down the
  # table sees all of it together. Radix sort is C-locale, so the same package
  # reports in the same order wherever it is scanned.
  out[order(match(out$status, .coverage_statuses), out$top_level, out$type,
            method = "radix"), , drop = FALSE]
}


# The top-level directory a path sits in, or "." for a file at the root.
.top_level <- function(paths) {
  ifelse(grepl("/", paths), paste0(sub("/.*$", "", paths), "/"), ".")
}


# What kind of file each row is: what it was read as where something read it,
# its extension otherwise, and its own name where it has no extension -- so
# DESCRIPTION and NAMESPACE name themselves rather than showing up blank.
.coverage_type <- function(paths, language) {
  ext  <- .file_extension(paths)
  type <- ifelse(!is.na(language), language, ext)
  ifelse(nzchar(type), type, basename(paths))
}

# TRUE for each row that executes during at least one lifecycle phase.
.runs_automatically <- function(df) {
  if (nrow(df) == 0L) return(logical(0L))
  apply(as.matrix(df[, .phase_columns]), 1L, any)
}


# The rows a phase filter asks for. "none" selects what runs at no phase, which
# is how the findings summaries read it too.
.in_phase <- function(df, phase) {
  if (is.null(phase) || nrow(df) == 0L) return(df)
  runs <- .runs_automatically(df)
  keep <- rep(FALSE, nrow(df))
  if ("none" %in% phase) keep <- keep | !runs
  named <- intersect(phase, .phase_columns)
  for (p in named) keep <- keep | as.logical(df[[p]])
  df[keep, , drop = FALSE]
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
.summarize_findings <- function(findings, context = NULL, phase = NULL) {
  empty <- data.frame(
    phase = character(0L), context = character(0L), rule = character(0L),
    n = integer(0L), attck = character(0L), stringsAsFactors = FALSE
  )
  if (is.null(context)) empty$context <- NULL else names(empty)[[2L]] <- context
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
    keys  <- if (is.null(context)) found$rule
             else paste(found[[context]], found$rule, sep = "\r")
    first <- match(sort(unique(keys), method = "radix"), keys)
    out   <- data.frame(
      phase   = phase,
      context = if (is.null(context)) NA_character_ else found[[context]][first],
      rule    = found$rule[first],
      n       = tabulate(match(keys, keys[first]), length(first)),
      attck   = found$attck[first],
      stringsAsFactors = FALSE
    )
    if (is.null(context)) out$context <- NULL else names(out)[[2L]] <- context
    out
  })

  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}


# Rename the errors data frame for display. All four columns are kept: the
# notes under the table are built from the rule and the message, and a caller
# reading s$errors wants them. The report shows only step and script.
.summarize_errors <- function(errors) {
  data.frame(
    step         = errors$step,
    file_context = errors$file_context,
    rule         = errors$rule,
    error        = errors$message,
    stringsAsFactors = FALSE
  )
}
