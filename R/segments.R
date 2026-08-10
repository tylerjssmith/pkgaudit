# The two extension points of the scan, dispatching on two axes. A source's
# class -- the rule's `type` -- selects how a file is read; a segment's class --
# the language of the code that came out -- selects how it is analysed. One file
# can yield segments in more than one language, so neither class serves for both.
#
# A new variety of file needs a script of methods and a file-context rule.

# --- Constructors -------------------------------------------------------------

# One file queued for scanning, classed by its rule's type so extract_segments()
# can dispatch on it.
# namespace_source says whether this file's R code becomes the package
# namespace. Only there can a lifecycle hook actually run: a .onLoad defined in,
# say, data/ ships as an ordinary object and is never called, so attributing it
# to onLoad_base would be a false reading rather than a cautious one.
# code_context names the computed context that top-level code in this file
# belongs to. "R" means compute it from the parse tree as usual; any
# other value replaces it, which is how data/, demo/ and the rest carry phases
# of their own rather than the ones R/ carries.
new_source <- function(path, file_context, type, macros = NULL,
                       namespace_source = FALSE,
                       code_context = .context_top_level) {
  structure(
    list(path = path, file_context = file_context, macros = macros,
         namespace_source = isTRUE(namespace_source),
         code_context = code_context),
    class = .source_class(type)
  )
}

# Types read exactly like another inherit from it rather than repeating a
# method, while staying distinct so a Makefile is still reported as one.
.source_parents <- list(make = "shell", qmd = "Rmd")

.source_class <- function(type) {
  c(type, .source_parents[[type]], "pkgaudit_source")
}

# A contiguous, line-aligned run of code in one language, classed by that
# language so analyze_segment() can dispatch on it.
#
#   context         the code context to attribute patterns to, or NA to compute
#                   it from the parse tree
#   named_contexts  whether the named code-context rules (.onLoad and friends)
#                   apply here. A hook assigned in a help-page example is not a
#                   hook, so a help file's segments withhold them.
#   guarded_lines   lines whose code ships but the lifecycle does not run --
#                   a \dontrun{} block, or a chunk marked eval=FALSE. Phases
#                   still come from the context, so they are an upper bound.
new_segment <- function(language, lines, file_context,
                        context = NA_character_, named_contexts = FALSE,
                        guarded_lines = integer(0L)) {
  structure(
    list(lines = lines, file_context = file_context, context = context,
         named_contexts = named_contexts, guarded_lines = guarded_lines),
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
#' @keywords internal
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
#' A method must build its return value with `.findings()`, which holds every
#' analyser to the same frame shape. `UseMethod()` ends the generic, so this
#' cannot be enforced after dispatch.
#'
#' @keywords internal
analyze_segment <- function(segment, rules) UseMethod("analyze_segment")

# A language with no analyser yields no findings and no error -- but it does
# yield a coverage row, so a {python} chunk in a vignette is accounted for
# rather than silently absent. An unhandled engine is a segment nothing
# matches, not a forgotten branch.
#' @export
analyze_segment.default <- function(segment, rules) {
  .findings(coverage = .segment_coverage(segment))
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


# The return value of an analyser: each frame reduced to its canonical columns,
# an omitted one empty. rbind() accepts a stray column silently, so conforming
# here is what keeps a malformed frame out of the result.
.findings <- function(patterns = NULL, matches = NULL, coverage = NULL,
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
# Anchored on the line rather than on the matched span. Most pattern rules match
# a bare SYMBOL_FUNCTION_CALL, so the span is the function's name and repeats
# what `rule` already says; the arguments that decide whether a finding matters
# are on the line around it. When the line is too long to show whole, the window
# moves to keep the match visible rather than truncating it away. A trailing
# "..." means there is more to see, further along the line or on the lines
# after it.
#
# The result is for reading, not indexing: whitespace is collapsed and the text
# may start partway into the line, so `column_number` does not address it.
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
