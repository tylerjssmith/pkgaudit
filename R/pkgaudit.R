# The pkgaudit S3 object: the four result data frames plus a metadata list,
# with a constructor, validators, and format()/print() methods.

# Expected columns for each result data frame.
.pkgaudit_columns <- list(
  file_contexts = c("file_context", "file_path", "message"),
  code_contexts = c("code_context", "file_context", "line_number",
                    "column_number", "message"),
  patterns      = c("pattern", "file_context", "line_number", "column_number",
                    "message", "attck", "code_context"),
  errors        = c("stage", "file_context", "rule", "message")
)

# Expected metadata fields and their scalar types.
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


#' Construct a pkgaudit result object
#'
#' Assembles the four result data frames and a metadata list into a validated
#' `pkgaudit` S3 object. [audit_package()] calls this at the end of a scan; it is
#' also used to construct objects directly (e.g. in tests).
#'
#' @param file_contexts,code_contexts,patterns,errors Data frames with the
#'   columns documented in [audit_package()].
#' @param metadata Named list with the nine fields documented in
#'   [audit_package()] (`pkg_name`, `pkg_version`, `pkg_path`, `pkg_is_tarball`,
#'   `pkg_sha256`, `pkgaudit_version`, `pkgaudit_rules_version`,
#'   `pkgaudit_rules_sha256`, `scanned`), each a length-one value of the
#'   expected type.
#'
#' @return A `pkgaudit` object: a list of `file_contexts`, `code_contexts`,
#'   `patterns`, `errors`, and `metadata`.
#'
#' @examples
#' \dontrun{
#' # Most callers get a pkgaudit object from audit_package(); new_pkgaudit()
#' # is for constructing one directly, e.g. from stored results.
#' result <- audit_package("/path/to/package")
#' obj <- new_pkgaudit(
#'   result$file_contexts, result$code_contexts,
#'   result$patterns, result$errors, result$metadata
#' )
#' }
#'
#' @keywords internal
new_pkgaudit <- function(file_contexts, code_contexts, patterns, errors,
                         metadata) {
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


# Validate one result data frame against its expected columns.
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
      if (length(missing) > 0L) paste0("; missing: ", paste(missing, collapse = ", ")),
      if (length(extra)   > 0L) paste0("; unexpected: ", paste(extra, collapse = ", ")),
      call. = FALSE
    )
  }
  invisible(TRUE)
}


# Validate the metadata list: all fields present, each a length-one scalar of
# the expected type.
.validate_metadata <- function(metadata) {
  if (!is.list(metadata)) {
    stop("new_pkgaudit(): 'metadata' must be a list.", call. = FALSE)
  }
  missing <- setdiff(names(.pkgaudit_metadata_types), names(metadata))
  if (length(missing) > 0L) {
    stop(
      "new_pkgaudit(): 'metadata' is missing field(s): ",
      paste(missing, collapse = ", "), call. = FALSE
    )
  }
  for (field in names(.pkgaudit_metadata_types)) {
    want <- .pkgaudit_metadata_types[[field]]
    val  <- metadata[[field]]
    ok <- switch(want,
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


#' Format or print a pkgaudit result
#'
#' `format.pkgaudit()` renders the scan metadata and finding counts as a
#' character vector of lines; `print.pkgaudit()` writes those lines and returns
#' the object invisibly. The output reports what was observed -- counts of file
#' contexts, code contexts, patterns, and errors -- without any verdict. The
#' rules-database SHA-256 is held in metadata but not shown.
#'
#' @param x A `pkgaudit` object.
#' @param path Logical; if `TRUE` (default) include the `Path:` line showing the
#'   local filesystem location scanned. Set `FALSE` to omit local paths from
#'   output that will be shared.
#' @param ... Ignored, for S3 compatibility.
#'
#' @return `format.pkgaudit()` returns a character vector of lines.
#'   `print.pkgaudit()` returns `x` invisibly.
#'
#' @examples
#' \dontrun{
#' result <- audit_package("/path/to/package")
#' print(result)                 # metadata + finding counts
#' print(result, path = FALSE)   # omit the local Path: line for sharing
#' writeLines(format(result))    # the same lines as a character vector
#' }
#'
#' @export
format.pkgaudit <- function(x, path = TRUE, ...) {
  m <- x$metadata
  field <- function(label, value) sprintf("%-16s%s", label, as.character(value))

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


# --- Metadata construction ----------------------------------------------------

# Build the nine-field metadata list for a scanned package. Package name and
# version come from DESCRIPTION and are NA (never an error) when it is missing or
# malformed. The rules version and hash describe the bundled rules database.
.build_metadata <- function(pkg, pkg_path, pkg_is_tarball, pkg_sha256) {
  desc <- .read_description(pkg)
  list(
    pkg_name               = desc$name,
    pkg_version            = desc$version,
    pkg_path               = pkg_path,
    pkg_is_tarball         = pkg_is_tarball,
    pkg_sha256             = pkg_sha256,
    pkgaudit_version       = .pkgaudit_version(),
    pkgaudit_rules_version = tryCatch(rules_version(), error = function(e) NA_character_),
    pkgaudit_rules_sha256  = .rules_db_sha256(),
    scanned                = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
}

# Read Package and Version from a package's DESCRIPTION. Returns NA_character_
# for either field when DESCRIPTION is missing, unparseable, or lacks it -- a
# malformed package must not abort the scan.
.read_description <- function(pkg) {
  out  <- list(name = NA_character_, version = NA_character_)
  desc <- file.path(pkg, "DESCRIPTION")
  if (!file.exists(desc) || dir.exists(desc)) return(out)

  dcf <- tryCatch(suppressWarnings(read.dcf(desc)), error = function(e) NULL)
  if (is.null(dcf) || nrow(dcf) == 0L) return(out)

  pick <- function(fieldname) {
    if (!fieldname %in% colnames(dcf)) return(NA_character_)
    v <- unname(dcf[1L, fieldname])
    if (is.na(v) || !nzchar(trimws(v))) NA_character_ else trimws(v)
  }
  out$name    <- pick("Package")
  out$version <- pick("Version")
  out
}

# Installed pkgaudit version, or NA if it cannot be determined.
.pkgaudit_version <- function() {
  tryCatch(as.character(utils::packageVersion("pkgaudit")),
           error = function(e) NA_character_)
}

# The published SHA-256 of the bundled rules database, read from its sidecar
# (the value load_rules() verifies the database against). NA if unavailable.
.rules_db_sha256 <- function(db_path = .db_path()) {
  sidecar <- paste0(db_path, ".sha256")
  tryCatch(trimws(readLines(sidecar, warn = FALSE)[[1L]]),
           error = function(e) NA_character_)
}
