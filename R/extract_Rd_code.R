#' Extract the R code from an .Rd help file
#'
#' Recovers the two kinds of R code an `.Rd` file can carry -- the body of
#' `\examples{}` and the code inside `\Sexpr{}` macros -- as text suitable for
#' `base::parse(text = )`.
#'
#' @param path Path to a single `.Rd` file.
#' @param macros Rd macros to expand while parsing, as returned by
#'   [tools::loadPkgRdMacros()]. Defaults to `NULL`, which parses the file
#'   alone.
#'
#' @return A named list of three elements:
#'   \describe{
#'     \item{examples}{Length-one character string: the code from
#'       `\examples{}`.}
#'     \item{sexpr}{Length-one character string: the code from every `\Sexpr{}`
#'       macro in the file, wherever it appears.}
#'     \item{error}{`NULL` when the file parsed cleanly, otherwise the parser's
#'       message. Both code strings are `""` when the file could not be parsed
#'       at all, and may be *incomplete* when it parsed with a warning, so a
#'       non-`NULL` `error` means the extraction is not to be trusted as a full
#'       account of the file's code.}
#'   }
#'
#' @details
#' The two streams are returned separately because they run at different times.
#' `\examples{}` runs under `R CMD check` and when a user calls `example()`;
#' `\Sexpr{}` runs while the help page is built or installed, which is the
#' earlier and less visible of the two. Merging them would make that distinction
#' unrecoverable.
#'
#' Both strings are *line-aligned*: line N of the returned text is line N of the
#' `.Rd` file, and everything else is blank padding. Parsing with
#' `parse(text = , keep.source = TRUE)` therefore yields source references whose
#' line and column numbers point straight into the original file, with no offset
#' table to carry around. Columns are preserved the same way where the fragments
#' allow it.
#'
#' Code is recovered from `tools::parse_Rd()`'s parse tree rather than by
#' matching text, so brace nesting, `%` comments, and the `\%` / `\\` / `\{`
#' escapes are handled by R's own Rd parser. The extracted text is real R code:
#' an example written `cat("a\\nb")` in the `.Rd` comes back as `cat("a\nb")`.
#'
#' Inside `\examples{}`:
#' \itemize{
#'   \item `\dontrun{}`, `\donttest{}`, `\dontshow{}`, and `\testonly{}` are
#'     unwrapped and their contents included. Whether the code is reached is a
#'     question for the caller; all four are R code shipped in the package.
#'   \item `\dots` becomes `...`, so a call does not silently lose an argument.
#'   \item Rd comments (`%` to end of line) are dropped, as they are not R code
#'     and would not parse.
#'   \item An inline `\Sexpr{}` goes to the `sexpr` stream and leaves a gap in
#'     the `examples` stream, so `h(\Sexpr{2+2})` yields `h()` there.
#' }
#'
#' User-defined Rd macros are expanded when `macros` is supplied, so a
#' `\Sexpr{}` reaching a page through a macro is recovered at the point of use,
#' with a source reference pointing at the page that used it. Without `macros`,
#' that code is invisible and each use records an `unknown macro` warning.
#' Scanning `man/macros/` directly would not help: `tools::parse_Rd()` returns a
#' `\newcommand` body as an opaque token, so the code inside it is not reachable
#' until the macro is expanded somewhere.
#'
#' @section Security considerations:
#' Nothing here evaluates the code it extracts. R's Rd machinery separates
#' parsing from rendering: `tools::parse_Rd()` and `tools::loadPkgRdMacros()`
#' only read, while the `tools::prepare_Rd()` and `tools::Rd2*()` family
#' evaluate `\Sexpr{}` as a matter of course. pkgaudit must never call the
#' latter, and a regression test asserts that a scan of a package whose Rd code
#' would write a marker file leaves no marker behind.
#'
#' @section Known limits:
#' `\Sexpr[results=rd]` produces Rd that is itself parsed and may contain
#' further code; that second-order surface is not followed. No `stage` option is
#' consulted, so the `sexpr` stream mixes build-, install-, and render-time code
#' together.
#'
#' `tools::parse_Rd()` recovers from some malformed input with a warning rather
#' than an error, returning a truncated tree. Whatever was recovered is still
#' returned, since dropping it would lose real code, but the warning is reported
#' in `error` so that a partial extraction is never mistaken for a complete one.
#'
#' The `examples` stream is not guaranteed to parse. R never syntax-checks
#' `\dontrun{}`: `tools::Rd2ex()` comments those lines out with `##D`, and
#' `R CMD check` therefore never sees them. Including that code, as this
#' function does, exposes `\dontrun{}` blocks that are not valid R -- a stray
#' bracket, a sentence of prose, a mis-escaped backslash. Over a sample of 3081
#' `.Rd` files from CRAN, 5 (0.16%) produced an `examples` stream that would not
#' parse, every one of them for that reason; no `sexpr` stream failed. Since the
#' two streams are each assembled whole, one broken `\dontrun{}` costs the
#' valid example code in the same file, which is worth weighing before this is
#' wired into a scan.
#'
#' @examples
#' \dontrun{
#' res <- extract_Rd_code("man/audit_package.Rd")
#' cat(res$examples)
#' parse(text = res$examples, keep.source = TRUE)
#' parse(text = res$sexpr)
#' }
extract_Rd_code <- function(path, macros = NULL) {
  stopifnot(is.character(path), length(path) == 1L, !is.na(path))
  if (!file.exists(path) || dir.exists(path)) {
    return(.empty_Rd_code(paste0("not a readable file: ", path)))
  }

  parsed <- .parse_Rd_safe(path, macros)
  if (is.null(parsed$rd)) return(.empty_Rd_code(parsed$error))

  frags <- .Rd_fragments(parsed$rd)
  list(
    # Example fragments are pieces of one continuous code stream and are joined
    # exactly as they sit; each \Sexpr is an independent expression, so those
    # are separated when two land on one line.
    examples = .assemble_lines(frags$examples, separator = ""),
    sexpr    = .assemble_lines(frags$sexpr,    separator = ";"),
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
  warnings <- character(0L)
  rd <- tryCatch(
    withCallingHandlers(
      if (is.null(macros)) {
        tools::parse_Rd(path)
      } else {
        tools::parse_Rd(path, macros = macros)
      },
      warning = function(w) {
        warnings[[length(warnings) + 1L]] <<- conditionMessage(w)
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
    error = if (length(warnings) > 0L) {
      paste(trimws(warnings), collapse = "; ")
    } else {
      NULL
    }
  )
}


# Walk an Rd parse tree and collect code fragments, split into the two streams.
#
# A fragment is list(line, col, text), positioned by the srcref of the node it
# came from. Returns list(examples = <fragments>, sexpr = <fragments>).
.Rd_fragments <- function(rd) {
  examples <- list()
  sexpr    <- list()

  add <- function(stream, node, text) {
    if (!nzchar(text)) return(invisible(NULL))
    src <- attr(node, "srcref")
    if (is.null(src)) return(invisible(NULL))
    frag <- list(line = as.integer(src[[1L]]), col = as.integer(src[[2L]]),
                 text = text)
    if (identical(stream, "sexpr")) {
      sexpr[[length(sexpr) + 1L]]       <<- frag
    } else {
      examples[[length(examples) + 1L]] <<- frag
    }
    invisible(NULL)
  }

  # \Sexpr holds its code in leaf nodes; take them wherever the macro appears,
  # positioned by the inner node so the code -- not the "\Sexpr{" wrapper -- is
  # what lines up.
  visit_sexpr <- function(node) {
    if (is.list(node)) {
      for (child in node) visit_sexpr(child)
    } else if (identical(attr(node, "Rd_tag"), "RCODE")) {
      add("sexpr", node, as.character(node))
    }
    invisible(NULL)
  }

  visit <- function(node, in_examples) {
    tag <- attr(node, "Rd_tag")

    if (identical(tag, "\\Sexpr")) {
      visit_sexpr(node)
      return(invisible(NULL))
    }
    # A zero-length list, so tested before the general list case below.
    if (in_examples && !is.null(tag) && tag %in% .Rd_dots) {
      add("examples", node, "...")
      return(invisible(NULL))
    }
    if (is.list(node)) {
      inside <- in_examples ||
        identical(tag, "\\examples") ||
        (in_examples && tag %in% .Rd_example_wrappers)
      for (child in node) visit(child, inside)
      return(invisible(NULL))
    }
    # Leaf. COMMENT is an Rd comment rather than R code and is dropped; any
    # other tag in an R-like section is markup that carries no code.
    if (in_examples && !is.null(tag) && tag %in% .Rd_code_leaves) {
      add("examples", node, as.character(node))
    }
    invisible(NULL)
  }

  visit(rd, in_examples = FALSE)
  list(examples = examples, sexpr = sexpr)
}


# --- Line-aligned assembly ----------------------------------------------------

# Lay fragments out so line N of the result is line N of the .Rd file.
#
# Each fragment is written at its own line and column, with blank padding
# elsewhere, so a parse of the result reports positions in the original file.
# separator is placed between two fragments that share a line, for the stream
# where neighbouring fragments are separate expressions rather than pieces of
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
  list(examples = "", sexpr = "", error = error)
}
