# This script defines internal helpers shared across pkgaudit.

# Empty result-frame constructors. Every finder returns a data frame with a
# stable schema even when it finds nothing, so downstream rbind() calls always
# align and callers never have to special-case zero rows.

# A data frame of the nine phase columns, all FALSE, with n rows.
.empty_phase_cols <- function(n = 0L) {
  cols        <- lapply(.phase_columns, function(nm) logical(n))
  names(cols) <- .phase_columns
  as.data.frame(cols, stringsAsFactors = FALSE)
}


.empty_file_contexts <- function(with_phases = TRUE) {
  df <- data.frame(
    rule         = character(0L),
    file_context = character(0L),
    message      = character(0L),
    stringsAsFactors = FALSE
  )
  if (with_phases) cbind(df, .empty_phase_cols()) else df
}


.empty_code_contexts <- function(with_phases = TRUE) {
  df <- data.frame(
    rule          = character(0L),
    file_context  = character(0L),
    line_number   = integer(0L),
    column_number = integer(0L),
    message       = character(0L),
    stringsAsFactors = FALSE
  )
  if (with_phases) cbind(df, .empty_phase_cols()) else df
}


# While a scan is running the frame carries two more columns than the result
# does: `file_rule`, the file-context rule that claimed the file, and
# `rd_context`, which part of a help page the code came from. Resolving a
# pattern's phases needs both, and audit_package() drops them once the phases
# are attached, so they never reach the caller.
.internal_pattern_columns <- c("file_rule", "rd_context")

# What find_patterns() and find_indirect() return: only the columns a match on
# the parse tree can fill. Everything else a pattern eventually carries -- the
# code context, `guarded`, `indirect`, `preview`, the phases -- is attached by
# the caller from where the code sits, which a finder does not know. A finder
# that found nothing returns this shape too, so its result is the same frame
# either way.
.empty_found <- function() {
  data.frame(
    rule          = character(0L),
    file_context  = character(0L),
    line_number   = integer(0L),
    column_number = integer(0L),
    message       = character(0L),
    attck         = character(0L),
    stringsAsFactors = FALSE
  )
}

.empty_patterns <- function(with_phases = TRUE) {
  df <- data.frame(
    rule          = character(0L),
    file_context  = character(0L),
    line_number   = integer(0L),
    column_number = integer(0L),
    code_context  = character(0L),
    guarded       = logical(0L),
    indirect      = logical(0L),
    preview       = character(0L),
    message       = character(0L),
    attck         = character(0L),
    stringsAsFactors = FALSE
  )
  if (with_phases) {
    cbind(df, .empty_phase_cols())
  } else {
    df$file_rule       <- character(0L)
    df$rd_context <- character(0L)
    df
  }
}


# Matches carry no code_context: shell code has no R parse tree to sit in, so a
# match's phases come from the file context it was found in rather than from an
# enclosing code context.
.empty_matches <- function(with_phases = TRUE) {
  df <- data.frame(
    rule          = character(0L),
    file_context  = character(0L),
    line_number   = integer(0L),
    column_number = integer(0L),
    preview       = character(0L),
    message       = character(0L),
    attck         = character(0L),
    stringsAsFactors = FALSE
  )
  if (with_phases) cbind(df, .empty_phase_cols()) else df
}


# One row per file in the package, and per code span where a file yields
# several. Ordered skim-first, as the findings frames are: the path, what
# pkgaudit made of it, and why -- then its extent, then the rule that claimed it.
.empty_coverage <- function(with_phases = TRUE) {
  df <- data.frame(
    file_context = character(0L),
    language     = character(0L),
    status       = character(0L),
    reason       = character(0L),
    first_line   = integer(0L),
    last_line    = integer(0L),
    lines        = integer(0L),
    bytes        = integer(0L),
    rule         = character(0L),
    stringsAsFactors = FALSE
  )
  if (with_phases) cbind(df, .empty_phase_cols()) else df
}


.empty_errors <- function() {
  data.frame(
    step         = character(0L),
    file_context = character(0L),
    rule         = character(0L),
    message      = character(0L),
    stringsAsFactors = FALSE
  )
}


# Build a one-row errors data frame. rule is optional (NA for file-level or
# parse-level failures that are not tied to a specific rule).
.error_row <- function(step, file_context = NA_character_,
                       rule = NA_character_, message) {
  data.frame(
    step         = step,
    file_context = file_context,
    rule         = rule,
    message      = message,
    stringsAsFactors = FALSE
  )
}


# Make one or more absolute paths relative to a package root.
#
# normalizePath() expands Windows short-form names (RUNNER~1 -> runneradmin)
# and normalizes separators, so startsWith() works even when tempdir() and
# list.files() return different representations of the same path on Windows.
# Paths that do not sit under root are returned normalized but unchanged.
.relativize <- function(paths, root) {
  if (length(paths) == 0L) return(character(0L))
  norm <- function(p) suppressWarnings(
    normalizePath(p, winslash = "/", mustWork = FALSE)
  )
  prefix <- paste0(norm(root), "/")
  normed <- norm(paths)
  ifelse(
    startsWith(normed, prefix),
    substring(normed, nchar(prefix) + 1L),
    normed
  )
}


# Rewrite one line of prose so it holds only the code its inline macros carry,
# each sitting at the column it occupies in the source. `\Sexpr{system("id")}`
# in an .Rnw and `` `r system("id")` `` in an .Rmd both become a line of spaces
# with system("id") at the macro's own offset.
#
# That keeps a finding's line_number and column_number pointing into the real
# file, and the result parses as R because the prose around it is gone. Returns
# NA when the line carries no inline code, which the callers use to decide
# whether the line is worth keeping.
#
# `pattern` matches a whole macro; `extract` pulls the code out of one match.
# Every match on the line is placed, so a second macro is not lost.
.inline_code <- function(line, pattern, extract) {
  at <- gregexpr(pattern, line, perl = TRUE)[[1L]]
  if (at[[1L]] == -1L) return(NA_character_)

  macros <- regmatches(line, gregexpr(pattern, line, perl = TRUE))[[1L]]
  out    <- character(0L)
  for (i in seq_along(macros)) {
    code <- extract(macros[[i]])
    # Pad from wherever the previous macro's code ended, so each lands on its
    # own column rather than the second following the first. From the second
    # macro on, a semicolon takes the place of the first padding space: two
    # expressions separated by blanks alone are not parseable R, and spending a
    # space keeps every column after it where it was.
    pad <- at[[i]] - 1L - sum(nchar(out))
    out <- if (length(out)) {
      c(out, ";", strrep(" ", max(pad - 1L, 0L)), code)
    } else {
      c(out, strrep(" ", max(pad, 0L)), code)
    }
  }
  paste0(out, collapse = "")
}


# Evaluate an XPath, promoting libxml2 warnings (e.g. invalid XPath) to errors
# so an ill-formed match is caught rather than silently returning nothing.
# Returns the node set on success or the caught condition on failure.
.xml_find_all_safe <- function(tree, xpath) {
  tryCatch(
    withCallingHandlers(
      xml2::xml_find_all(tree, xpath),
      warning = function(w) stop(conditionMessage(w))
    ),
    error = function(e) e
  )
}


# --- Argument checks ----------------------------------------------------------

# stopifnot() reports the expression it tested, so a caller who passes a missing
# path is told "dir.exists(path) is not TRUE" -- a statement about pkgaudit's
# internals rather than about their call. These name the argument and say what
# was wrong with it. call. = FALSE because the failure is the caller's argument,
# not the frame it was checked in.
.stop_arg <- function(...) stop(..., call. = FALSE)

.check_path <- function(path, arg, dir = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    .stop_arg("`", arg, "` must be a single, non-empty file path.")
  }
  exists <- if (dir) dir.exists(path) else file.exists(path)
  if (!exists) {
    .stop_arg("`", arg, "` is not an existing ",
              if (dir) "directory" else "file", ": ", path)
  }
  invisible(path)
}

.check_rules <- function(rules) {
  if (!is.list(rules)) {
    .stop_arg("`rules` must be a list of rules, as load_rules() returns.")
  }
  absent <- setdiff(.rule_classes, names(rules))
  if (length(absent)) {
    .stop_arg("`rules` is missing ",
              paste0("`", absent, "`", collapse = ", "),
              "; pass the list load_rules() returns.")
  }
  invisible(rules)
}

.check_pkgaudit <- function(object, arg = "object") {
  if (!inherits(object, "pkgaudit")) {
    .stop_arg("`", arg, "` must be a pkgaudit object from audit_package() or ",
              "audit_tarball(), not ", class(object)[[1L]], ".")
  }
  invisible(object)
}

.check_flag <- function(x, arg) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    .stop_arg("`", arg, "` must be TRUE or FALSE.")
  }
  invisible(x)
}
