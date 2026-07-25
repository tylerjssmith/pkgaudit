# This script defines internal helpers shared across pkgaudit.

# Empty result-frame constructors. Every finder returns a data frame with a
# stable schema even when it finds nothing, so downstream rbind() calls always
# align and callers never have to special-case zero rows.

.empty_file_contexts <- function() {
  data.frame(
    file_context = character(0L),
    file_path    = character(0L),
    message      = character(0L),
    stringsAsFactors = FALSE
  )
}

.empty_code_contexts <- function() {
  data.frame(
    code_context  = character(0L),
    file_context  = character(0L),
    line_number   = integer(0L),
    column_number = integer(0L),
    message       = character(0L),
    stringsAsFactors = FALSE
  )
}

.empty_patterns <- function() {
  data.frame(
    pattern       = character(0L),
    file_context  = character(0L),
    line_number   = integer(0L),
    column_number = integer(0L),
    message       = character(0L),
    attck         = character(0L),
    code_context  = character(0L),
    stringsAsFactors = FALSE
  )
}

.empty_errors <- function() {
  data.frame(
    stage        = character(0L),
    file_context = character(0L),
    rule         = character(0L),
    message      = character(0L),
    stringsAsFactors = FALSE
  )
}

# Build a one-row errors data frame. rule is optional (NA for file-level or
# parse-level failures that are not tied to a specific rule).
.error_row <- function(stage, file_context = NA_character_,
                       rule = NA_character_, message) {
  data.frame(
    stage        = stage,
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

# Evaluate an XPath, promoting libxml2 warnings (e.g. invalid XPath) to errors
# so an ill-formed expression is caught rather than silently returning nothing.
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
