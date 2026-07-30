# This script defines the pkgaudit S3 object with a constructor and validators.
# Its methods live in pkgaudit_methods.R.

# --- Constructor --------------------------------------------------------------

#' Construct a pkgaudit object
#'
#' Assembles the four result data frames and a metadata list into a validated
#' `pkgaudit` S3 object. [audit_package()] calls this at the end of a scan. It
#' is also used to construct objects directly (e.g., in tests).
#'
#' @param file_contexts,code_contexts,patterns,errors Data frames with the
#'   columns documented in [audit_package()].
#' @param metadata Named list with the fields documented in [audit_package()],
#'   each a length-one value of the expected type.
#'
#' @return A `pkgaudit` object: a named list of `file_contexts`,
#'   `code_contexts`, `patterns`, `errors`, and `metadata`.
#'
#' @keywords internal
new_pkgaudit <- function(
  file_contexts,
  code_contexts,
  patterns,
  errors,
  metadata
) {
  .validate_result_df(file_contexts, "file_contexts")
  .validate_result_df(code_contexts, "code_contexts")
  .validate_result_df(patterns,      "patterns")
  .validate_result_df(errors,        "errors")
  .validate_metadata(metadata)

  structure(
    list(
      file_contexts = file_contexts,
      code_contexts = code_contexts,
      patterns      = patterns,
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
  "on_load", "on_attach", "on_unload", "on_detach"
)


# The two code contexts that are computed rather than rule-matched. Both have
# rows in the phases table, so resolving a pattern's phases stays a lookup.
.context_top_level <- "Top-level"
.context_other     <- "Other"
.sentinel_contexts <- c(.context_top_level, .context_other)


# Expected columns for each result data frame. `rule` names the rule that
# produced the row and joins to the rules database; `file_context` is the
# package-root-relative path and joins the frames to each other.
.pkgaudit_columns <- list(
  file_contexts = c("rule", "file_context", "message", .phase_columns),
  code_contexts = c("rule", "file_context", "line_number", "column_number",
                    "message", .phase_columns),
  patterns      = c("rule", "file_context", "line_number", "column_number",
                    "message", "attck", "code_context", .phase_columns),
  errors        = c("stage", "file_context", "rule", "message")
)


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

