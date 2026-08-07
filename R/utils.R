# This script defines internal helpers shared across pkgaudit.

# Empty result-frame constructors. Every finder returns a data frame with a
# stable schema even when it finds nothing, so downstream rbind() calls always
# align and callers never have to special-case zero rows.
#
# The finders do not know a rule's lifecycle phases -- those live in the rules
# database and are attached once, in audit_package(). Each constructor therefore
# takes with_phases: TRUE gives the object's public schema, FALSE the narrower
# frame a finder builds before the phase columns are joined on.

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


.empty_patterns <- function(with_phases = TRUE) {
  df <- data.frame(
    rule          = character(0L),
    file_context  = character(0L),
    line_number   = integer(0L),
    column_number = integer(0L),
    code_context  = character(0L),
    guarded       = logical(0L),
    preview       = character(0L),
    message       = character(0L),
    attck         = character(0L),
    stringsAsFactors = FALSE
  )
  if (with_phases) cbind(df, .empty_phase_cols()) else df
}


# Matches carry no code_context: a shell script or Make-like file has no R
# parse tree to sit in, so a match's phases come from the file context it
# was found in rather than from an enclosing code context.
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


# Vectorised isTRUE: NA and NULL entries become FALSE. Used where a missing rule
# field must fail closed rather than propagate NA into a logical branch.
isTRUE_vec <- function(x) {
  if (is.null(x)) return(logical(0L))
  out <- as.logical(x)
  out[is.na(out)] <- FALSE
  out
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
