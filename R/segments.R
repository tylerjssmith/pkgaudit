# The two extension points of the scan, dispatching on two axes. A source's
# class -- the rule's `type` -- selects how a file is read; a segment's class --
# the language of the code that came out -- selects how it is analysed. One file
# can yield segments in more than one language, so neither class serves for both.
#
# A new variety of file needs a script of methods and a file-context rule.

# --- Constructors -------------------------------------------------------------

# One file queued for scanning, classed by its rule's type so extract_segments()
# can dispatch on it.
#
#   file_rule      the file-context rule that claimed this file, which a
#                  pattern's phases depend on as well as on where the code sits.
#   code_contexts  the code-context rules that can apply here, or NULL for none.
#                  This is what keeps the lifecycle hooks out of data/ and
#                  tests/, where a .onLoad ships as an ordinary object and is
#                  never called.
new_source <- function(path, file_context, type, macros = NULL,
                       file_rule = NA_character_, code_contexts = NULL) {
  structure(
    list(path = path, file_context = file_context, macros = macros,
         file_rule = file_rule, code_contexts = code_contexts),
    class = .source_class(type)
  )
}

# Types read exactly like another inherit from it rather than repeating a
# method, while staying distinct so a Makefile is still reported as one.
.source_parents <- list(make = "shell", qmd = "Rmd")

.source_class <- function(type) {
  c(type, .source_parents[[type]], "pkgaudit_source")
}

#' Build one code segment
#'
#' A contiguous, line-aligned run of code in one language, classed by that
#' language so [analyze_segment()] can dispatch on it. An [extract_segments()]
#' method returns these.
#'
#' @param language The language of the code, which selects the analyser.
#' @param lines Character vector of the segment's lines, blank-padded to the
#'   line numbers they occupy in the file so a finding's line is the real one.
#' @param file_context Package-root-relative path of the file it came from.
#' @param context The segment's label, matched by a `kind: segment` code-context
#'   rule, or `NA` where it has none. It is the only record of which part of a
#'   help file the code came from.
#' @param file_rule The file-context rule that claimed the file.
#' @param code_contexts The code-context rules that can apply, from the source.
#' @param guarded_lines Lines whose code ships but the lifecycle does not run --
#'   a `\dontrun{}` block, or a chunk marked `eval=FALSE`. Phases still come from
#'   the context, so they are an upper bound.
#'
#' @return A `pkgaudit_segment` object.
#'
#' @seealso [extract_segments()], whose methods return these.
#' @examples
#' seg <- new_segment(language = "R", lines = c("", "system('id')"),
#'                    file_context = "R/f.R")
#' class(seg)
#' @export
new_segment <- function(language, lines, file_context,
                        context = NA_character_, file_rule = NA_character_,
                        code_contexts = NULL, guarded_lines = integer(0L)) {
  structure(
    list(lines = lines, file_context = file_context, context = context,
         file_rule = file_rule, code_contexts = code_contexts,
         guarded_lines = guarded_lines),
    class = c(language, "pkgaudit_segment")
  )
}


# --- Extraction ---------------------------------------------------------------

#' Read one source file into the code segments it contains
#'
#' Dispatches on the file-context rule's `type`, which is the only place a new
#' variety of file is named.
#'
#' @param source A `pkgaudit_source` from `new_source()`.
#'
#' @return A list of two elements:
#'   \describe{
#'     \item{segments}{List of segments from `new_segment()`, each holding
#'       `lines` aligned to the lines of the source file.}
#'     \item{errors}{Data frame with columns `step`, `file_context`, `rule`,
#'       `message`.}
#'   }
#'
#' @section Security considerations:
#' The scanning size limit is enforced here, before dispatch, so no method can
#' skip it. A method must not re-implement it.
#'
#' A method reads untrusted bytes and must never evaluate them. Return the code
#' as text in a segment; deciding what it means is [analyze_segment()]'s job.
#'
#' @seealso [analyze_segment()], the other axis of dispatch, and
#'   `vignette("internals")`.
#' @examples
#' # Adding a file format outside pkgaudit: a method for a new rule `type`,
#' # here one that treats a .txt file as if it held R code.
#' extract_segments.txt <- function(source) {
#'   list(segments = list(new_segment(language = "R",
#'                                    lines = readLines(source$path),
#'                                    file_context = source$file_context)),
#'        errors = NULL)
#' }
#' registerS3method("extract_segments", "txt", extract_segments.txt)
#' @export
extract_segments <- function(source) {
  oversize <- .over_scan_limit(source$path)
  if (!is.null(oversize)) {
    return(list(segments = list(), errors = .error_row(
      step = "extract_segments", file_context = source$file_context,
      message = oversize
    )))
  }
  UseMethod("extract_segments")
}

# A type with no reader yields no segment: how "other" is reported but never
# read, and how an unrecognised type fails closed.
#' @export
extract_segments.default <- function(source) {
  list(segments = list(), errors = .empty_errors())
}


# --- Analysis -----------------------------------------------------------------

#' Find code contexts, patterns and matches in one segment
#'
#' Dispatches on the segment's language, which the extractor set. This is a
#' separate axis from the source's type: a help file and an R script both yield
#' R segments, and one literate file can yield several languages.
#'
#' @param segment A `pkgaudit_segment` from `new_segment()`.
#' @param rules Named list of rules as returned by [load_rules()].
#'
#' @return A list of `patterns`, `matches`, `coverage` and `errors` data
#'   frames, each with the columns [audit_package()] documents, less the phase
#'   columns.
#'
#' @section Method contract:
#' A method must build its return value with [new_findings()], which holds every
#' analyser to the same frame shape. `UseMethod()` ends the generic, so this
#' cannot be enforced after dispatch.
#'
#' A method must not evaluate the code it is given. It reads untrusted text and
#' reports what it finds; nothing in a scan is ever run.
#'
#' @seealso [extract_segments()], the other axis of dispatch, [new_findings()],
#'   and `vignette("internals")`.
#' @examples
#' # Adding a language outside pkgaudit: a method for segments the extractor
#' # labelled "python", reporting each line that calls eval().
#' analyze_segment.python <- function(segment, rules) {
#'   at <- grep("\\beval\\(", segment$lines)
#'   new_findings(matches = data.frame(
#'     rule = "py_eval", file_context = segment$file_context,
#'     line_number = at, column_number = NA_integer_,
#'     preview = trimws(segment$lines[at]),
#'     message = "eval() in Python code", attck = NA_character_))
#' }
#' registerS3method("analyze_segment", "python", analyze_segment.python)
#' @export
analyze_segment <- function(segment, rules) UseMethod("analyze_segment")

# A language with no analyser yields no findings and no error -- but it does
# yield a coverage row, so a {python} chunk in a vignette is accounted for
# rather than silently absent. An unhandled engine is a segment nothing
# matches, not a forgotten branch.
#' @export
analyze_segment.default <- function(segment, rules) {
  new_findings(coverage = .segment_coverage(segment))
}


# The coverage row for a segment no analyser read: the span it occupies in its
# source file, in the language it is written in.
#
# Segments are blank-padded to the length of the file they came from, so the
# lines carrying code are the span. A segment with nothing in it is not a gap.
.segment_coverage <- function(segment) {
  at <- which(nzchar(trimws(segment$lines)))
  if (length(at) == 0L) return(.empty_coverage(with_phases = FALSE))

  data.frame(
    file_context = segment$file_context,
    language     = class(segment)[[1L]],
    status       = "exportable",
    reason       = "no_analyser",
    first_line   = min(at),
    last_line    = max(at),
    lines        = length(at),
    bytes        = NA_integer_,
    rule         = NA_character_,
    stringsAsFactors = FALSE
  )
}


#' Build the return value of an [analyze_segment()] method
#'
#' Each frame is reduced to its canonical columns and an omitted one is empty.
#' `rbind()` accepts a stray column silently, so conforming here is what keeps a
#' malformed frame out of the result.
#'
#' @param patterns,matches,coverage Data frames with the columns
#'   [audit_package()] documents, less the phase columns, or `NULL` for none.
#'   Extra columns are dropped; the phases are resolved later, from context.
#' @param errors Data frame with columns `step`, `file_context`, `rule` and
#'   `message`.
#'
#' @return A list of the four frames, each conformed to its canonical columns.
#'
#' @seealso [analyze_segment()], whose methods return this.
#' @examples
#' # An analyser that found nothing still returns all four frames.
#' str(new_findings(), max.level = 1)
#' @export
new_findings <- function(patterns = NULL, matches = NULL, coverage = NULL,
                      errors = .empty_errors()) {
  conform <- function(df, template) {
    if (is.null(df)) template else df[, names(template), drop = FALSE]
  }
  list(
    patterns      = conform(patterns,      .empty_patterns(FALSE)),
    matches       = conform(matches,       .empty_matches(FALSE)),
    coverage      = conform(coverage,      .empty_coverage(FALSE)),
    errors        = errors
  )
}


# --- Previews -----------------------------------------------------------------

# How much of a line a preview shows, and how much room is kept to its left when
# the window has to move off the start of the line to reach the match.
.preview_width <- 72L
.preview_lead  <- 16L

# A one-line, display-only excerpt of the source a finding sits on.
#
# Anchored on the line, not the matched span: the span is usually just the
# function's name, and what decides whether a finding matters is around it. A
# long line is windowed to keep the match visible; a trailing "..." means there
# is more to see.
#
# For reading, not indexing: whitespace is collapsed and the text may start
# partway into the line, so `column_number` does not address it.
.preview <- function(lines, line_number, column_number, continues = FALSE) {
  n <- length(line_number)
  if (n == 0L) return(character(0L))
  continues <- rep_len(continues, n)

  out <- character(n)
  for (i in seq_len(n)) {
    ln <- line_number[i]
    if (is.na(ln) || ln < 1L || ln > length(lines)) {
      out[i] <- NA_character_
      next
    }
    raw  <- lines[[ln]]
    lead <- attr(regexpr("^[[:space:]]*", raw), "match.length")
    col  <- if (is.na(column_number[i])) lead + 1L else column_number[i]

    # Windowing is done on the raw line, where the column is exact, and the
    # whitespace collapsed afterwards.
    start <- lead + 1L
    if (col > start + .preview_width - .preview_lead) start <- col - .preview_lead
    end   <- start + .preview_width - 1L

    text <- gsub("[[:space:]]+", " ", trimws(substr(raw, start, end)))
    if (start > lead + 1L) text <- paste0("...", text)
    if (end < nchar(raw) || continues[i]) text <- paste0(text, "...")
    out[i] <- text
  }
  out
}
