#' Load security rules from the pkgaudit rules database
#'
#' Loads the file-context, code-context, and pattern rules from the bundled
#' SQLite database as a named list suitable for passing to [audit_package()].
#' Before reading, the database is verified against its SHA-256 sidecar so a
#' tampered or corrupted rules file is rejected rather than silently trusted.
#'
#' @param db_path Path to the SQLite rules database. Defaults to the database
#'   bundled with the installed package.
#'
#' @return A named list with three data frames:
#'   \describe{
#'     \item{file_contexts}{Columns `name`, `version`, `type`, `message`,
#'       `path`, `recursive`, `pattern`.}
#'     \item{code_contexts}{Columns `name`, `version`, `type`, `message`,
#'       `xpath`.}
#'     \item{patterns}{Columns `name`, `version`, `type`, `message`, `attck`,
#'       `xpath`.}
#'   }
#'
#' @examples
#' \dontrun{
#' rules <- load_rules()
#' }
#'
#' @export
load_rules <- function(db_path = .db_path()) {
  .with_db(db_path, function(con) {
    file_contexts <- DBI::dbGetQuery(
      con,
      "SELECT name, version, type, message, path, recursive, pattern
         FROM file_contexts
        ORDER BY name"
    )
    # SQLite has no native logical type; recursive is stored as 0/1.
    file_contexts$recursive <- as.logical(file_contexts$recursive)

    code_contexts <- DBI::dbGetQuery(
      con,
      "SELECT name, version, type, message, xpath
         FROM code_contexts
        ORDER BY name"
    )

    patterns <- DBI::dbGetQuery(
      con,
      "SELECT name, version, type, message, attck, xpath
         FROM patterns
        ORDER BY name"
    )

    if (nrow(file_contexts) == 0L &&
        nrow(code_contexts) == 0L &&
        nrow(patterns) == 0L) {
      stop("No rules found in rules database: ", db_path)
    }

    list(
      file_contexts = file_contexts,
      code_contexts = code_contexts,
      patterns      = patterns
    )
  })
}


#' Return the current rules database version
#'
#' Returns the version string of the rules database currently shipped with the
#' package. Findings reports should always record the rules version to ensure
#' reproducibility across audit cycles.
#'
#' @param db_path Path to the SQLite rules database.
#'
#' @return A character string giving the rules database version (e.g.,
#'   `"0.1.0"`).
#'
#' @examples
#' \dontrun{
#' rules_version()
#' }
#'
#' @export
rules_version <- function(db_path = .db_path()) {
  .with_db(db_path, function(con) {
    version <- DBI::dbGetQuery(
      con,
      "SELECT version
         FROM rule_versions
        ORDER BY released_at DESC, rowid DESC
        LIMIT 1"
    )

    if (nrow(version) == 0L) {
      stop("No version found in rules database: ", db_path)
    }

    version$version[[1L]]
  })
}


# --- Helpers ------------------------------------------------------------------
.db_path <- function() system.file("db", "rules.db", package = "pkgaudit")

# Open the rules database, verify its integrity, run fn(con), and always
# disconnect. Verification happens before any query so a tampered database is
# never queried.
.with_db <- function(db_path, fn) {
  if (!nzchar(db_path) || !file.exists(db_path)) {
    stop(
      "Rules database not found: ",
      if (nzchar(db_path)) db_path else "(empty path -- is pkgaudit installed?)"
    )
  }
  .verify_db(db_path)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  fn(con)
}

# Verify the database against its SHA-256 sidecar. A missing sidecar or a hash
# mismatch is fatal: this is a security tool, and silently loading unverified
# rules would undermine its guarantees.
.verify_db <- function(db_path) {
  hash_path <- paste0(db_path, ".sha256")
  if (!file.exists(hash_path)) {
    stop(
      "Rules database hash sidecar not found: ", hash_path, "\n",
      "Refusing to load unverified rules database."
    )
  }
  expected <- trimws(readLines(hash_path, warn = FALSE)[[1L]])
  actual   <- digest::digest(db_path, algo = "sha256", file = TRUE)
  if (!identical(tolower(expected), tolower(actual))) {
    stop(
      "Rules database failed SHA-256 verification.\n",
      "  expected: ", expected, "\n",
      "  actual:   ", actual, "\n",
      "Refusing to load a modified rules database."
    )
  }
  invisible(TRUE)
}
