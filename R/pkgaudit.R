# This script defines the pkgaudit S3 object with a constructor, validators, and
# format() and print() methods.

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


# Expected columns for each result data frame
.pkgaudit_columns <- list(
  file_contexts = c("file_context", "file_path", "message"),
  code_contexts = c("code_context", "file_context", "line_number",
                    "column_number", "message"),
  patterns      = c("pattern", "file_context", "line_number", "column_number",
                    "message", "attck", "code_context"),
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
#' @examples
#' \dontrun{
#' result <- audit_package("/path/to/package")
#' print(result)
#' print(result, path = FALSE)   # omit the local Path: line for sharing
#' }
#'
#' @export
format.pkgaudit <- function(x, path = TRUE, ...) {
  m <- x$metadata
  field <- function(label, value) {
    sprintf("%-16s%s", label, as.character(value))
  }

  header <- paste0("--- pkgaudit ",
                   strrep("-", max(0L, 80L - nchar("--- pkgaudit "))))

  name_part <- .or_unknown(m$pkg_name)
  ver_part  <- if (is.na(m$pkg_version)) "" else paste0(" v", m$pkg_version)
  kind      <- if (isTRUE(m$pkg_is_tarball)) "source tarball" else "source directory"
  pkg_value <- paste0(name_part, ver_part, " (", kind, ")")

  scanned_value <- paste0(
    .format_scanned(m$scanned),
    " with pkgaudit ", .or_unknown(m$pkgaudit_version),
    ", rules v", .or_unknown(m$pkgaudit_rules_version)
  )

  n_errors  <- nrow(x$errors)
  err_value <- if (n_errors > 0L) {
    paste0(n_errors, "   (coverage incomplete)")
  } else {
    as.character(n_errors)
  }

  lines <- c(header, field("Package:", pkg_value))
  if (isTRUE(path)) {
    lines <- c(lines, field("Path:", .or_unknown(m$pkg_path)))
  }
  c(
    lines,
    field("SHA-256:",       .or_unknown(m$pkg_sha256)),
    field("Scanned:",       scanned_value),
    field("File contexts:", nrow(x$file_contexts)),
    field("Code contexts:", nrow(x$code_contexts)),
    field("Patterns:",      nrow(x$patterns)),
    field("Errors:",        err_value)
  )
}


#' @rdname format.pkgaudit
#' @export
print.pkgaudit <- function(x, path = TRUE, ...) {
  writeLines(format(x, path = path, ...))
  invisible(x)
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
