# This script defines the pkgaudit S3 object with a constructor and validators.
# Its methods live in pkgaudit_methods.R.

# --- Constructor --------------------------------------------------------------

#' Construct a pkgaudit object
#'
#' Assembles the five result data frames and a metadata list into a validated
#' `pkgaudit` S3 object. [audit_package()] calls this at the end of a scan. It
#' is also used to construct objects directly (e.g., in tests).
#'
#' @param file_contexts,patterns,matches,coverage,errors Data frames with the
#'   columns documented in [audit_package()].
#' @param metadata Named list with the fields documented in [audit_package()],
#'   each a length-one value of the expected type.
#'
#' @return A `pkgaudit` object: a named list of `file_contexts`, `patterns`,
#'   `matches`, `coverage`, `errors`, and `metadata`.
#'
#' @keywords internal
new_pkgaudit <- function(
  file_contexts,
  patterns,
  matches,
  coverage,
  errors,
  metadata
) {
  .validate_result_df(file_contexts, "file_contexts")
  .validate_result_df(patterns,      "patterns")
  .validate_result_df(matches,       "matches")
  .validate_result_df(coverage,      "coverage")
  .validate_result_df(errors,        "errors")
  .validate_metadata(metadata)

  structure(
    list(
      file_contexts = file_contexts,
      patterns      = patterns,
      matches   = matches,
      coverage      = coverage,
      errors        = errors,
      metadata      = metadata
    ),
    class = "pkgaudit"
  )
}


# --- Validators ---------------------------------------------------------------

# Validate that a result data frame has exactly its expected columns
.validate_result_df <- function(df, name) {
  if (!is.data.frame(df)) {
    stop("new_pkgaudit(): '", name, "' must be a data frame.", call. = FALSE)
  }
  expected <- .pkgaudit_columns[[name]]
  missing  <- setdiff(expected, names(df))
  extra    <- setdiff(names(df), expected)
  if (length(missing) > 0L || length(extra) > 0L) {
    stop(
      "new_pkgaudit(): '", name, "' must have exactly columns: ",
      paste(expected, collapse = ", "),
      if (length(missing) > 0L) paste0("; missing: ",
        paste(missing, collapse = ", ")),
      if (length(extra)   > 0L) paste0("; unexpected: ",
        paste(extra, collapse = ", ")),
      call. = FALSE
    )
  }
  invisible(TRUE)
}


# The package lifecycle phases, in the order they occur. Every findings frame
# carries one logical column per phase, TRUE when that finding's code runs
# during the phase. Defined here, ahead of .pkgaudit_columns, because that
# object is built at build time and R/ files are collated alphabetically.
.phase_columns <- c(
  "at_autoconf", "at_build", "at_check", "at_install_src", "at_install_bin",
  "at_load", "at_attach", "at_unload", "at_detach"
)


# The two computed code contexts, which no rule defines. They are the whole of
# what a parse tree can tell on its own: code at the top level, and code inside
# a function definition. Everything else is a rule.
#
# Neither carries phases of its own. Both inherit from the file context they sit
# in, except where a rule sets `assume_called: FALSE`, as the rules for R/ do.
.context_top_level   <- "top_level"
.context_in_function <- "in_function"

# The labels the extractors stamp on a segment, and the vocabulary a
# `kind: segment` code-context rule matches against. They exist because the
# distinction is invisible to the parse tree: once an .Rd file has yielded R
# code, nothing in it says which part of the page it came from.
.context_rd_examples <- "Rd_examples"

# One label per \Sexpr stage. The three phase profiles are not nested --
# stage=render does not run at either install, and stage=build does not run when
# a tarball is installed, its result having been frozen into the Rd at build
# time -- so they cannot share a context.
.context_rd_sexpr <- c(build   = "Rd_Sexpr_build",
                       install = "Rd_Sexpr_install",
                       render  = "Rd_Sexpr_render")

.segment_labels <- c(.context_rd_examples, unname(.context_rd_sexpr))

.computed_contexts <- c(.context_top_level, .context_in_function)


# The rule classes load_rules() returns, and that a rules list must carry all
# of. A scan missing one reports no findings of that kind, which is
# indistinguishable from a package that has none -- so it is refused rather
# than run.
.rule_classes <- c("file_contexts", "code_contexts", "patterns", "matches",
                   "phases")


# Expected columns for each result data frame. `rule` names the rule that
# produced the row and joins to the rules database; `file_context` is the
# package-root-relative path and joins the frames to each other.
.pkgaudit_columns <- list(
  file_contexts = c("rule", "file_context", "message", .phase_columns),
  patterns      = c("rule", "file_context", "line_number", "column_number",
                    "code_context", "guarded", "indirect", "preview",
                    "message", "attck", .phase_columns),
  matches   = c("rule", "file_context", "line_number", "column_number",
                    "preview", "message", "attck", .phase_columns),
  coverage      = c("file_context", "language", "status", "reason",
                    "first_line", "last_line", "lines", "bytes", "rule",
                    .phase_columns),
  errors        = c("step", "file_context", "rule", "message")
)


# What pkgaudit made of a file, and why it made no more of it.
#
# `error` and `unexamined` are not the same claim: pkgaudit tried to read a file
# it reports as `error` and could not, and never tried to read an unexamined
# one. Every `error` row has a matching row in the `errors` frame, and only a
# failure at a reading step counts -- a rule that fails on a file says nothing
# about the file. `reason` says what stood in the way, NA where nothing did.
.coverage_statuses <- c("parsed", "matched", "exportable", "unexamined",
                        "error")
.coverage_reasons <- c("no_analyser", "no_extractor", "serialized", "binary",
                       "no_rule", "symlink", "too_large", "unreadable",
                       "unparseable")


# Validate that a metadata list has exactly its expected fields and that each
# field is a length-one scalar of its expected type
.validate_metadata <- function(metadata) {
  if (!is.list(metadata)) {
    stop("new_pkgaudit(): 'metadata' must be a list.", call. = FALSE)
  }
  missing <- setdiff(names(.pkgaudit_metadata_types), names(metadata))
  extra   <- setdiff(names(metadata), names(.pkgaudit_metadata_types))
  if (length(missing) > 0L || length(extra) > 0L) {
    stop(
      "new_pkgaudit(): 'metadata' must have exactly fields: ",
      paste(names(.pkgaudit_metadata_types), collapse = ", "),
      if (length(missing) > 0L) paste0("; missing: ",
        paste(missing, collapse = ", ")),
      if (length(extra)   > 0L) paste0("; unexpected: ",
        paste(extra, collapse = ", ")),
      call. = FALSE
    )
  }
  for (field in names(.pkgaudit_metadata_types)) {
    want <- .pkgaudit_metadata_types[[field]]
    val  <- metadata[[field]]
    ok   <- switch(want,
      character = is.character(val),
      logical   = is.logical(val),
      FALSE
    )
    if (!ok || length(val) != 1L) {
      stop(
        "new_pkgaudit(): 'metadata$", field, "' must be a length-one ", want,
        ".", call. = FALSE
      )
    }
  }
  invisible(TRUE)
}


# Expected fields and scalar types for metadata list
.pkgaudit_metadata_types <- list(
  pkg_name               = "character",
  pkg_version            = "character",
  pkg_path               = "character",
  pkg_is_tarball         = "logical",
  pkg_sha256             = "character",
  pkgaudit_version       = "character",
  pkgaudit_rules_version = "character",
  pkgaudit_rules_sha256  = "character",
  scanned                = "character"
)


# Validate the provenance a caller supplied for a scan
#
# `.origin` records the tarball as received rather than the temporary directory
# it was extracted into, so these three fields become the scan's provenance.
# Checked before the scan, and strictly: a metadata block that claims a directory
# scan while carrying a tarball's path is worse than a refused one.
.validate_origin <- function(origin) {
  if (is.null(origin)) return(invisible(TRUE))

  bad <- function(why) {
    stop("audit_package(): '.origin' must be NULL or ", why, ".", call. = FALSE)
  }
  if (!is.list(origin)) bad("a list")

  missing <- setdiff(names(.pkgaudit_origin_types), names(origin))
  if (length(missing) > 0L) {
    bad(paste0("a list with fields: ",
               paste(names(.pkgaudit_origin_types), collapse = ", "),
               "; missing: ", paste(missing, collapse = ", ")))
  }
  for (field in names(.pkgaudit_origin_types)) {
    want <- .pkgaudit_origin_types[[field]]
    val  <- origin[[field]]
    ok   <- switch(want,
      character = is.character(val),
      logical   = is.logical(val) && !is.na(val),
      FALSE
    )
    if (!ok || length(val) != 1L) {
      bad(paste0("a list whose '", field, "' is a length-one ", want,
                 if (identical(want, "logical")) " that is not NA"))
    }
  }
  invisible(TRUE)
}

# Expected fields and scalar types for the .origin list. A path and hash may be
# NA -- hashing can fail and the scan still records what it could -- but
# is_tarball may not: it is a claim about what was scanned.
.pkgaudit_origin_types <- list(
  path       = "character",
  sha256     = "character",
  is_tarball = "logical"
)
