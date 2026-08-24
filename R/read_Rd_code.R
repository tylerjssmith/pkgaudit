#' Read the R code out of an .Rd help file
#'
#' Recovers the R code an `.Rd` file carries -- the body of `\examples{}` and the
#' code inside `\Sexpr{}` macros -- as text suitable for `base::parse(text = )`.
#'
#' @param path Path to a single `.Rd` file.
#' @param macros Rd macros to expand while parsing, as returned by
#'   [tools::loadPkgRdMacros()]. Defaults to `NULL`, which parses the file alone
#'   and leaves code reaching the page through a user-defined macro invisible.
#'
#' @return A named list:
#'   \describe{
#'     \item{examples}{Length-one character string: the code from `\examples{}`.}
#'     \item{guarded}{Integer vector: the lines of `examples` sitting inside
#'       `\dontrun{}`, which no example run reaches.}
#'     \item{sexpr}{Named list of three length-one strings -- `build`, `install`
#'       and `render` -- holding each `\Sexpr{}` macro's code by the stage it
#'       runs at. An unlabeled macro counts as `install`.}
#'     \item{error}{`NULL` when the file parsed cleanly, otherwise a message. The
#'       code strings are `""` when nothing was read, and may be incomplete when
#'       the file parsed with a warning, so a non-`NULL` `error` means the
#'       extraction is not a full account of the file's code.}
#'   }
#'
#' @details
#' Examples and `\Sexpr` are returned separately, and `\Sexpr` by stage, because
#' they run at different times: examples under `R CMD check`, a macro while the
#' page is built, installed or rendered. Merging them would lose that.
#'
#' Every string is *line-aligned*: line N of the returned text is line N of the
#' `.Rd` file, and the rest is blank padding. Parsing with `keep.source = TRUE`
#' therefore yields source references pointing straight into the original file,
#' with no offset to apply.
#'
#' Code is recovered from `tools::parse_Rd()`'s parse tree rather than by
#' matching text, so brace nesting, `%` comments and the `\%` / `\\` / `\{`
#' escapes are handled by R's own parser; an example written `cat("a\\nb")` comes
#' back as `cat("a\nb")`. Inside `\examples{}`, `\dontrun{}` and its siblings are
#' unwrapped and their contents included -- all four are code that ships -- while
#' Rd comments are dropped and an inline `\Sexpr{}` moves to the `sexpr` string.
#'
#' @section Security considerations:
#' Nothing here evaluates the code it extracts. R's Rd machinery separates
#' parsing from rendering: `tools::parse_Rd()` and `tools::loadPkgRdMacros()`
#' only read, while the `tools::prepare_Rd()` and `tools::Rd2*()` family evaluate
#' `\Sexpr{}` as a matter of course. pkgaudit must never call the latter, and a
#' regression test asserts that scanning a package whose Rd code would write a
#' marker file leaves no marker behind.
#'
#' A help file is untrusted input like any other, so one above the scanning limit
#' is refused unread and reported through `error`.
#'
#' @section Known limits:
#' `\Sexpr[results=rd]` produces Rd that is itself parsed and may carry further
#' code; that second-order surface is not followed.
#'
#' `tools::parse_Rd()` recovers from some malformed input with a warning and a
#' truncated tree. Whatever was recovered is still returned, since dropping it
#' would lose real code, and the warning is reported in `error`.
#'
#' The `examples` string is not guaranteed to parse. R never syntax-checks
#' `\dontrun{}`, so including that code exposes blocks that are not valid R.
#' The string is assembled whole, so one broken `\dontrun{}` costs the valid
#' example code in the same file.
#'
#' @keywords internal
read_Rd_code <- function(path, macros = NULL) {
  stopifnot(is.character(path), length(path) == 1L, !is.na(path))
  if (!file.exists(path) || dir.exists(path)) {
    return(.empty_Rd_code(paste0("not a readable file: ", path)))
  }
  oversize <- .over_scan_limit(path)
  if (!is.null(oversize)) return(.empty_Rd_code(oversize))

  parsed <- .parse_Rd_safe(path, macros)
  if (is.null(parsed$rd)) return(.empty_Rd_code(parsed$error))

  frags <- .Rd_fragments(parsed$rd)
  list(
    # Example fragments are pieces of one continuous run of code and are joined
    # exactly as they sit; each \Sexpr is an independent expression, so those
    # are separated when two land on one line.
    examples = .assemble_lines(frags$examples, separator = ""),
    guarded  = frags$guarded,
    sexpr    = lapply(frags$sexpr, .assemble_lines, separator = ";"),
    # Non-NULL when the file parsed with a warning: the code above is whatever
    # survived, and the caller is told not to read it as the whole file.
    error    = parsed$error
  )
}


# --- Rd parsing ---------------------------------------------------------------

# Rd tags whose contents are R code but are wrapped for display purposes. All
# four are unwrapped: each is code that ships in the package, and which of them
# a given run reaches is not something this function decides.
.Rd_example_wrappers <- c("\\dontrun", "\\donttest", "\\dontshow", "\\testonly")

# Of those four, the one no example run reaches. `\donttest` is not among them:
# it is skipped by a plain `R CMD check` but run under `--as-cran`, which is the
# check CRAN performs, so treating it as unrun would understate the surface.
# Code under `\dontrun` still ships, so it is scanned and marked rather than
# dropped.
.Rd_unrun_wrappers <- "\\dontrun"

# Leaf tags that carry code. Inside \examples, R code is tagged RCODE, except
# within \dontrun, which R treats as verbatim and tags VERB.
.Rd_code_leaves <- c("RCODE", "VERB")

# Tags standing for the literal ellipsis in an R-like section.
.Rd_dots <- c("\\dots", "\\ldots")


# Parse an .Rd file, returning list(rd, error). An unparseable file is data, not
# a failure: a package under audit is untrusted input, and one malformed help
# file must not be able to abort a scan.
#
# Warnings are captured rather than left to print. parse_Rd() recovers from some
# malformed input by warning and returning a truncated tree, which would
# otherwise yield a partial extraction indistinguishable from a complete one.
# The tree is kept -- it holds real code -- and the warning is returned with it.
.parse_Rd_safe <- function(path, macros = NULL) {
  # The handler runs in a frame of its own, so what it collects lives in an
  # environment parented on emptyenv(): the store is named, and no binding
  # outside this call is reachable from it.
  seen <- new.env(parent = emptyenv())
  seen$warnings <- character(0L)

  rd <- tryCatch(
    withCallingHandlers(
      if (is.null(macros)) {
        tools::parse_Rd(path)
      } else {
        tools::parse_Rd(path, macros = macros)
      },
      warning = function(w) {
        seen$warnings <- c(seen$warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) e
  )

  if (inherits(rd, "condition")) {
    return(list(rd = NULL, error = conditionMessage(rd)))
  }
  list(
    rd    = rd,
    error = if (length(seen$warnings) > 0L) {
      paste(trimws(seen$warnings), collapse = "; ")
    } else {
      NULL
    }
  )
}


# Walk an Rd parse tree and collect code fragments, split into the kinds that
# run at different times.
#
# A fragment is list(line, col, text), positioned by the srcref of the node it
# came from. Returns list(examples, guarded, sexpr), where `guarded` holds the
# .Rd lines occupied by example code inside a wrapper R CMD check does not run,
# and `sexpr` is one fragment list per \Sexpr stage.
.Rd_fragments <- function(rd) {
  # The walk is recursive and collects into three buckets, so the buckets live
  # in an environment parented on emptyenv(): the store is named, and no
  # binding outside this call is reachable from it.
  acc <- new.env(parent = emptyenv())
  acc$examples <- list()
  acc$guarded  <- integer(0L)
  acc$sexpr    <- list(build = list(), install = list(), render = list())

  add <- function(kind, node, text, is_guarded = FALSE) {
    if (!nzchar(text)) return(invisible(NULL))
    src <- attr(node, "srcref")
    if (is.null(src)) return(invisible(NULL))
    line <- as.integer(src[[1L]])
    frag <- list(line = line, col = as.integer(src[[2L]]), text = text)

    if (identical(kind, "examples")) {
      acc$examples[[length(acc$examples) + 1L]] <- frag
      if (is_guarded) {
        span <- line + seq_len(length(strsplit(text, "\n", fixed = TRUE)[[1L]])) - 1L
        acc$guarded <- c(acc$guarded, span)
      }
    } else {
      acc$sexpr[[kind]][[length(acc$sexpr[[kind]]) + 1L]] <- frag
    }
    invisible(NULL)
  }

  # \Sexpr holds its code in leaf nodes; take them wherever the macro appears,
  # positioned by the inner node so the code -- not the "\Sexpr{" wrapper -- is
  # what lines up.
  visit_sexpr <- function(node, stage) {
    if (is.list(node)) {
      for (child in node) visit_sexpr(child, stage)
    } else if (identical(attr(node, "Rd_tag"), "RCODE")) {
      add(stage, node, as.character(node))
    }
    invisible(NULL)
  }

  visit <- function(node, in_examples, is_guarded) {
    tag <- attr(node, "Rd_tag")

    if (identical(tag, "\\Sexpr")) {
      visit_sexpr(node, .Sexpr_stage(attr(node, "Rd_option")))
      return(invisible(NULL))
    }
    # A zero-length list, so tested before the general list case below.
    if (in_examples && !is.null(tag) && tag %in% .Rd_dots) {
      add("examples", node, "...", is_guarded)
      return(invisible(NULL))
    }
    if (is.list(node)) {
      inside  <- in_examples || identical(tag, "\\examples")
      # Code under a wrapper no example run reaches is still scanned -- it
      # ships in the package -- but flagged, so the phases it carries are read
      # as an upper bound.
      guarded_here <- is_guarded ||
        (!is.null(tag) && tag %in% .Rd_unrun_wrappers)
      for (child in node) visit(child, inside, guarded_here)
      return(invisible(NULL))
    }
    # Leaf. COMMENT is an Rd comment rather than R code and is dropped; any
    # other tag in an R-like section is markup that carries no code.
    if (in_examples && !is.null(tag) && tag %in% .Rd_code_leaves) {
      add("examples", node, as.character(node), is_guarded)
    }
    invisible(NULL)
  }

  visit(rd, in_examples = FALSE, is_guarded = FALSE)
  list(examples = acc$examples, guarded = unique(acc$guarded), sexpr = acc$sexpr)
}


# The stage a \Sexpr runs at, from its option string. Writing R Extensions gives
# install as the default when no stage is named, and an instrumented probe
# package confirms an unlabeled \Sexpr behaves identically to stage=install.
#
# tools::parse_Rd() rejects a stage that is not one of the three, so this is
# never asked about an invalid one -- the file fails to parse first and the
# error is recorded. Matching is case-insensitive because parse_Rd() lowercases
# before it validates, so stage=BUILD is a build-stage macro. Anything this
# still cannot read falls back to install, the broadest of the three, so an
# option it does not understand is never under-reported.
.Sexpr_stage <- function(option) {
  if (is.null(option)) return("install")
  m <- regmatches(option, regexpr("stage[[:space:]]*=[[:space:]]*[[:alnum:]]+",
                                  as.character(option)))
  if (length(m) == 0L) return("install")
  stage <- tolower(sub("^stage[[:space:]]*=[[:space:]]*", "", m))
  if (stage %in% c("build", "render")) stage else "install"
}


# --- Line-aligned assembly ----------------------------------------------------

# Lay fragments out so line N of the result is line N of the .Rd file.
#
# Each fragment is written at its own line and column, with blank padding
# elsewhere, so a parse of the result reports positions in the original file.
# separator is placed between two fragments that share a line, for the kind
# where neighboring fragments are separate matches rather than pieces of
# one.
.assemble_lines <- function(frags, separator = "") {
  if (length(frags) == 0L) return("")

  pieces <- lapply(frags, function(f) {
    parts <- strsplit(f$text, "\n", fixed = TRUE)[[1L]]
    if (length(parts) == 0L) return(NULL)
    # Only the first line of a fragment starts at the fragment's column; a
    # continuation line starts where the source line does.
    list(line = f$line, col = f$col, parts = parts)
  })
  pieces <- Filter(Negate(is.null), pieces)
  if (length(pieces) == 0L) return("")

  last <- max(vapply(pieces, function(p) p$line + length(p$parts) - 1L,
                     integer(1L)))
  buf  <- rep("", last)

  for (p in pieces) {
    for (i in seq_along(p$parts)) {
      buf <- .place(buf, p$line + i - 1L, if (i == 1L) p$col else 1L,
                    p$parts[[i]], separator)
    }
  }
  paste(buf, collapse = "\n")
}


# Write text into one line of the buffer at the given column.
#
# The line is padded with spaces up to the column. Text that would overlap what
# is already there is appended instead, which shifts it right: a column is worth
# preserving but never at the cost of losing code.
.place <- function(buf, line, col, text, separator) {
  if (!nzchar(text)) return(buf)
  cur <- buf[[line]]

  if (nzchar(separator) && nzchar(trimws(cur))) {
    cur <- paste0(sub("[[:space:]]+$", "", cur), separator)
  }
  if (nchar(cur) < col - 1L) {
    cur <- paste0(cur, strrep(" ", col - 1L - nchar(cur)))
  }

  buf[[line]] <- paste0(cur, text)
  buf
}


# The result for a file with no recoverable code, carrying the reason when there
# was one.
.empty_Rd_code <- function(error = NULL) {
  list(examples = "", guarded = integer(0L),
       sexpr = list(build = "", install = "", render = ""), error = error)
}
