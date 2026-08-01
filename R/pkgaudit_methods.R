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
#' `summary.pkgaudit()` rolls a scan up into the distinct file and code contexts
#' found, the frequency of each pattern by the lifecycle phase and code context
#' it executes in with its MITRE ATT&CK techniques, and the errors, if any.
#' `print.summary.pkgaudit()` writes that summary as a sectioned report and
#' returns the object invisibly.
#'
#' @param object A `pkgaudit` object.
#' @param x A `summary.pkgaudit` object.
#' @param path Logical; if `TRUE` (default) include the `Path:` line showing the
#'   local filesystem location scanned. Set `FALSE` to omit local paths.
#'   `summary.pkgaudit()` records the choice in the object it returns;
#'   `print.summary.pkgaudit()` uses that recorded value unless given its own.
#' @param ... Ignored, for S3 compatibility.
#'
#' @return `summary.pkgaudit()` returns a `summary.pkgaudit` object: a named list
#'   of three summary data frames, the errors, the scan `metadata`, and the
#'   recorded `path`.
#'   \describe{
#'     \item{file_contexts}{`file_context`: each file context found, once.}
#'     \item{code_contexts}{`code_context`: each code-context rule matched,
#'       once.}
#'     \item{patterns}{`phase`, `code_context`, `rule`, `n`, `attck`: how often
#'       each pattern rule was matched in each code context, split by the
#'       lifecycle phase that context executes in, with the ATT&CK techniques
#'       the rule carries.}
#'     \item{errors}{`stage`, `script`, `rule`, `error`: the rows of the object's
#'       `errors` data frame, renamed for display.}
#'   }
#'   `print.summary.pkgaudit()` returns `x` invisibly.
#'
#' @details
#' The report opens with the same metadata block as [print.pkgaudit()], then
#' gives one section per result. A section with nothing to report says so.
#'
#' A pattern occurrence executes in every phase its code context does, so it
#' contributes one row per phase and the `n` column sums to more than the number
#' of occurrences. Occurrences that execute in no phase at all are gathered
#' under `none`.
#'
#' The `Errors` section lists every error, whatever stage produced it, and is
#' followed by one note per stage stating what scan coverage was lost. An error
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
#' summary(result, path = FALSE)   # omit the local Path: line for sharing
#'
#' s <- summary(result)
#' s$patterns                      # pattern frequencies as a data frame
#' }
#'
#' @method summary pkgaudit
#' @export
summary.pkgaudit <- function(object, path = TRUE, ...) {
  structure(
    list(
      file_contexts = .summarize_contexts(object$file_contexts$file_context,
                                          "file_context"),
      code_contexts = .summarize_contexts(object$code_contexts$rule,
                                          "code_context"),
      patterns      = .summarize_patterns(object$patterns),
      errors        = .summarize_errors(object$errors),
      metadata      = object$metadata,
      path          = isTRUE(path)
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


# --- Summary Construction -----------------------------------------------------

# Reduce a context column to the distinct values found, in the order first seen,
# as a one-column data frame named for the column summarized.
.summarize_contexts <- function(values, column) {
  df <- data.frame(unique(values), stringsAsFactors = FALSE)
  names(df) <- column
  df
}


# Count pattern occurrences by the phase and code context they execute in, one
# row per phase, code context, and rule, carrying each rule's ATT&CK labels.
#
# An occurrence executes in every phase its code context does, so it is counted
# once per phase and `n` sums to more than the number of occurrences. An
# occurrence that executes in no phase -- code reached only when something calls
# it -- is gathered under "none". The ATT&CK labels come from the rule, so they
# are constant across a rule's rows and any one of them describes them all.
#
# Rows are ordered by phase in lifecycle order with "none" last, then by code
# context and rule name. Context and rule names mix cases, so those two are
# sorted in the C locale: a report of the same scan reads the same wherever it
# is run.
.summarize_patterns <- function(patterns) {
  empty <- data.frame(
    phase = character(0L), code_context = character(0L), rule = character(0L),
    n = integer(0L), attck = character(0L), stringsAsFactors = FALSE
  )
  if (nrow(patterns) == 0L) return(empty)

  levels <- c(.phase_columns, "none")
  rows   <- lapply(levels, function(phase) {
    in_phase <- if (phase == "none") {
      rowSums(as.matrix(patterns[, .phase_columns, drop = FALSE])) == 0L
    } else {
      patterns[[phase]]
    }
    if (!any(in_phase)) return(empty)

    found <- patterns[in_phase, , drop = FALSE]
    keys  <- paste(found$code_context, found$rule, sep = "\r")
    first <- match(sort(unique(keys), method = "radix"), keys)
    data.frame(
      phase        = phase,
      code_context = found$code_context[first],
      rule         = found$rule[first],
      n            = tabulate(match(keys, keys[first]), length(first)),
      attck        = found$attck[first],
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}


# Rename the errors data frame for display. All four columns are kept: which
# stage failed, and both of the fields that identify what failed, since no one
# stage sets them both.
.summarize_errors <- function(errors) {
  data.frame(
    stage  = errors$stage,
    script = errors$file_context,
    rule   = errors$rule,
    error  = errors$message,
    stringsAsFactors = FALSE
  )
}


# --- Summary Rendering --------------------------------------------------------

# Render a summary object as the sectioned report lines.
.format_summary <- function(x, path = TRUE) {
  c(
    .section_header("pkgaudit Summary"),
    .metadata_lines(x$metadata, path = path),
    "",
    .section_header("Contexts"),
    .summary_section(x$file_contexts, "No file contexts were found."),
    "",
    .summary_section(x$code_contexts, "No code contexts were found."),
    "",
    .section_header("Patterns"),
    .summary_section(x$patterns, "No patterns were found."),
    "",
    .section_header("Errors"),
    .errors_section(x$errors)
  )
}


# Render one summary section: the table, or a message when there is nothing to
# report.
.summary_section <- function(df, empty_message) {
  if (nrow(df) == 0L) empty_message else .format_table(df)
}


# Render the Errors section: the table of every error followed by the notes
# describing the coverage lost, or the all-clear when there were none.
.errors_section <- function(errors) {
  if (nrow(errors) == 0L) return("No exceptions were raised.")
  c(.format_table(errors), "", .error_notes(errors))
}


# --- Error Notes --------------------------------------------------------------

# Build one note per stage that recorded an error, in pipeline order, each
# stating what the failure cost the scan. Notes are wrapped to the report width
# and separated by a blank line.
.error_notes <- function(errors) {
  notes <- character(0L)
  for (stage in names(.error_note_builders)) {
    rows <- errors[errors$stage == stage, , drop = FALSE]
    if (nrow(rows) == 0L) next
    notes <- c(notes, .error_note_builders[[stage]](rows))
  }
  # A stage this method does not know about still gets counted rather than
  # silently dropped from the notes.
  other <- errors[!errors$stage %in% names(.error_note_builders), , drop = FALSE]
  for (stage in unique(other$stage)) {
    n     <- sum(other$stage == stage)
    notes <- c(notes, paste0(
      .count(n, "error"), " occurred during ", stage,
      ". Findings may not reflect a complete scan."
    ))
  }

  wrapped <- lapply(notes, strwrap, width = .report_width)
  unlist(.interleave(wrapped, ""), use.names = FALSE)
}


# Note builders keyed by stage, in the order the stages run. Each takes that
# stage's error rows and returns one unwrapped sentence.
.error_note_builders <- list(
  find_file_contexts = function(rows) {
    paste0(
      .count(.n_rules(rows), "file-context rule"),
      " could not be evaluated. Findings may not reflect all ",
      "security-relevant files."
    )
  },
  parse_script = function(rows) {
    n <- .n_scripts(rows)
    paste0(
      .count(n, "R script"), " could not be parsed for code contexts or ",
      "patterns, and ", if (n == 1L) "was" else "were", " not scanned. ",
      "Findings do not reflect the contents of ", .those_scripts(n), "."
    )
  },
  find_code_contexts = function(rows) {
    n <- .n_scripts(rows)
    paste0(
      .count(.n_rules(rows), "code-context rule"), " could not be evaluated in ",
      .count(n, "R script"), ". Findings may not reflect all code contexts in ",
      .those_scripts(n), "."
    )
  },
  find_patterns = function(rows) {
    n <- .n_scripts(rows)
    paste0(
      .count(.n_rules(rows), "pattern rule"), " could not be evaluated in ",
      .count(n, "R script"), ". Findings may not reflect all patterns in ",
      .those_scripts(n), "."
    )
  }
)


# Distinct rules and scripts named in a set of error rows. Either field may be
# NA for a given stage, in which case the row count is the best available
# measure and is never reported as zero.
.n_rules   <- function(rows) .n_distinct(rows$rule,   nrow(rows))
.n_scripts <- function(rows) .n_distinct(rows$script, nrow(rows))

.n_distinct <- function(x, fallback) {
  n <- length(unique(x[!is.na(x)]))
  if (n == 0L) fallback else n
}


# "1 R script" / "3 R scripts", and the pronoun that agrees with it.
.count <- function(n, singular, plural = paste0(singular, "s")) {
  paste(n, if (n == 1L) singular else plural)
}

.those_scripts <- function(n) if (n == 1L) "that script" else "these scripts"


# Place sep between the elements of a list, but not around them.
.interleave <- function(items, sep) {
  if (length(items) <= 1L) return(items)
  c(items[1L], unlist(lapply(items[-1L], function(x) list(sep, x)),
                      recursive = FALSE))
}


# --- Shared Display Helpers ---------------------------------------------------

# The metadata block shared by the print and summary reports: what was scanned,
# where it came from, and what scanned it.
.metadata_lines <- function(m, path = TRUE) {
  name_part <- .or_unknown(m$pkg_name)
  ver_part  <- if (is.na(m$pkg_version)) "" else paste0(" v", m$pkg_version)
  kind      <- if (isTRUE(m$pkg_is_tarball)) "source tarball" else "source directory"
  pkg_value <- paste0(name_part, ver_part, " (", kind, ")")

  scanned_value <- paste0(
    .format_scanned(m$scanned),
    " with pkgaudit v", .or_unknown(m$pkgaudit_version),
    ", rules v", .or_unknown(m$pkgaudit_rules_version)
  )

  lines <- .field("Package:", pkg_value)
  if (isTRUE(path)) {
    lines <- c(lines, .field("Path:", .or_unknown(m$pkg_path)))
  }
  c(
    lines,
    .field("SHA-256:", .or_unknown(m$pkg_sha256)),
    .field("Scanned:", scanned_value)
  )
}


# The report width. Three characters narrower than a terminal line, so that
# knitr output prefixed with "#> " still fits in 80 columns.
.report_width <- 77L

# Label field widths. The metadata labels are short enough to set their values
# close to the left margin; the finding counts carry longer labels of their own.
.metadata_label_width <- 11L
.count_label_width    <- 16L


# Render one labelled line, padding the label to the given field width.
.field <- function(label, value, width = .metadata_label_width) {
  sprintf("%-*s%s", width, label, as.character(value))
}


# Render a section rule: the label set off by dashes to the report width.
.section_header <- function(label) {
  prefix <- paste0("--- ", label, " ")
  paste0(prefix, strrep("-", max(0L, .report_width - nchar(prefix))))
}


# Render a data frame as aligned text: a header line of column names followed by
# one line per row, columns three spaces apart. Character columns are
# left-aligned and numeric columns right-aligned, and NA renders blank.
# print.data.frame() cannot be used here: it right-aligns character columns and
# reserves a leading gutter for row names.
.format_table <- function(df) {
  columns <- lapply(names(df), function(column) {
    values <- df[[column]]
    text   <- ifelse(is.na(values), "", as.character(values))
    formatC(
      c(column, text),
      width = max(nchar(c(column, text))),
      flag  = if (is.numeric(values)) "" else "-"
    )
  })
  trimws(do.call(paste, c(columns, sep = "   ")), which = "right")
}


# Render a length-one metadata value, or "<unknown>" when it is absent or NA.
# new_pkgaudit() validates field types but not knownness, so any metadata field
# may be NA in a hand-constructed object; the display renders those uniformly.
.or_unknown <- function(x) {
  if (length(x) != 1L || is.na(x)) "<unknown>" else x
}


# Render the stored ISO 8601 UTC timestamp as "YYYY-MM-DD HH:MM UTC". Falls back
# to the raw stored value if it cannot be parsed, and to "<unknown>" if absent.
.format_scanned <- function(scanned) {
  if (length(scanned) != 1L || is.na(scanned)) return("<unknown>")
  t <- tryCatch(
    as.POSIXct(scanned, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    error = function(e) NA
  )
  if (is.na(t)) return(scanned)
  format(t, "%Y-%m-%d %H:%M UTC", tz = "UTC")
}
