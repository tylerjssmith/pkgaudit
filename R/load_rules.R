# This script contains functions for verifying and reading the pkgaudit rules
# database and obtaining the database version.

#' Load security rules from the pkgaudit rules database
#'
#' Loads the file-context, code-context, pattern, and regex rules, and the
#' lifecycle phases of every context, from the bundled SQLite database as a
#' named list suitable for passing to [audit_package()] or [audit_tarball()].
#'
#' @param db_path Path to the rules database. Defaults to the database bundled
#'   with the installed package.
#'
#' @return A named list with five data frames:
#'   \describe{
#'     \item{file_contexts}{Data frame with columns `name`, `version`, `type`,
#'       `message`, `path`, `recursive`, `pattern`.}
#'     \item{code_contexts}{Data frame with columns `name`, `version`, `type`,
#'       `message`, `xpath`.}
#'     \item{patterns}{Data frame with columns `name`, `version`, `type`,
#'       `message`, `attck`, `xpath`.}
#'     \item{regex}{Data frame with columns `name`, `version`, `message`,
#'       `attck`, `regex`. Regex rules declare no `type`: they are applied to
#'       every file context whose type is `shell` or `make`.}
#'     \item{phases}{Data frame with columns `context`, `version`, and one
#'       logical column per lifecycle phase. One row per context code can
#'       execute in: every file- and code-context rule, plus the computed
#'       contexts `"Top-level"` and `"Other"`.}
#'   }
#'   The list carries a `"provenance"` attribute recording the database the
#'   rules were read from -- a list of `db_path`, `version`, and `sha256` --
#'   which [audit_package()] reports in a scan's `metadata`. The `sha256` is the
#'   hash computed from the database during verification, not a value re-read
#'   from the sidecar afterwards, so it records what this call measured.
#'
#' @details
#' Before reading, the database is verified against its SHA-256 sidecar so that
#' a tampered or corrupted rules file is rejected rather than silently trusted.
#'
#' @section Security considerations:
#' Verification is time-of-check to time-of-use (TOCTOU): the database is hashed
#' and then re-opened by path to query it, so a file swapped in the interval
#' between the two is not detected. This does not weaken the bundled default --
#' an attacker able to win that race already has write access to the installed
#' package and could replace the sidecar or this package's code outright. If
#' loading rules from a path other parties can write, treat the SHA-256 check as
#' protection against accidental corruption or a substituted database given an
#' authentic sidecar -- not against an attacker who can modify the file
#' concurrently. Load from a path only trusted writers control.
#'
#' @examples
#' \dontrun{
#' rules <- load_rules()
#' }
#'
#' @export
load_rules <- function(db_path = .db_path()) {
  .with_db(db_path, function(con, sha256) {
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

    regex <- DBI::dbGetQuery(
      con,
      "SELECT name, version, message, attck, regex
         FROM regex
        ORDER BY name"
    )

    phases <- DBI::dbGetQuery(
      con,
      sprintf("SELECT context, version, %s
                 FROM phases
                ORDER BY context",
              paste(.phase_columns, collapse = ", "))
    )
    for (phase in .phase_columns) {
      phases[[phase]] <- as.logical(phases[[phase]])
    }

    if (nrow(file_contexts) == 0L &&
        nrow(code_contexts) == 0L &&
        nrow(patterns) == 0L &&
        nrow(regex) == 0L) {
      stop("No rules found in rules database: ", db_path, call. = FALSE)
    }

    .validate_phase_coverage(file_contexts, code_contexts, phases, db_path)

    # Record which database these rules came from. A scan reports the rules it
    # actually used, and without this it could only report whichever database
    # happens to be bundled -- a different one whenever db_path is not default.
    structure(
      list(
        file_contexts = file_contexts,
        code_contexts = code_contexts,
        patterns      = patterns,
        regex         = regex,
        phases        = phases
      ),
      provenance = list(
        db_path = db_path,
        version = .query_version(con, db_path),
        sha256  = sha256
      )
    )
  })
}


# Every context a finding can be attributed to must have a phases row, or that
# finding would silently report no phases at all. The contexts are the file- and
# code-context rules plus the computed contexts assigned by
# determine_code_contexts(). A gap is a malformed database, not a runtime
# condition, so it is refused here rather than papered over downstream.
.validate_phase_coverage <- function(file_contexts, code_contexts, phases,
                                     db_path) {
  needed  <- c(file_contexts$name, code_contexts$name, .sentinel_contexts)
  missing <- setdiff(needed, phases$context)
  if (length(missing) > 0L) {
    stop(
      "Rules database is missing phases for: ",
      paste(missing, collapse = ", "), "\n  Database: ", db_path,
      call. = FALSE
    )
  }
  invisible(TRUE)
}


#' Return the current rules database version
#'
#' Returns the version string of the rules database currently shipped with the
#' package. Findings reports should always record the rules version to ensure
#' reproducibility across audit cycles.
#'
#' @param db_path Path to the SQLite rules database. Defaults to the database
#'   bundled with the installed package.
#'
#' @return A character string giving the rules database version (e.g.,
#'   `"0.1.0"`).
#'
#' @details
#' Like [load_rules()], this verifies the database against its SHA-256 sidecar
#' before reading; see its Security considerations.
#'
#' @examples
#' \dontrun{
#' rules_version()
#' }
#'
#' @export
rules_version <- function(db_path = .db_path()) {
  .with_db(db_path, function(con, sha256) .query_version(con, db_path))
}


# --- Helpers ------------------------------------------------------------------

# Return the path to the bundled database.
.db_path <- function() system.file("db", "rules.db", package = "pkgaudit")


# The latest version recorded in an open database. Shared by rules_version()
# and load_rules(), which reads it on the connection it already holds rather
# than re-opening and re-verifying the file.
.query_version <- function(con, db_path) {
  version <- DBI::dbGetQuery(
    con,
    "SELECT version
       FROM rule_versions
      ORDER BY released_at DESC, rowid DESC
      LIMIT 1"
  )

  if (nrow(version) == 0L) {
    stop("No version found in rules database: ", db_path, call. = FALSE)
  }

  version$version[[1L]]
}


# Open the rules database, verify its integrity, run fn(con), and always
# disconnect. Verification happens before any query so a tampered database is
# never queried.
.with_db <- function(db_path, fn) {
  if (!nzchar(db_path) || !file.exists(db_path)) {
    stop(
      "Rules database not found: ",
      if (nzchar(db_path)) db_path else "(empty path--is pkgaudit installed?)",
      call. = FALSE
    )
  }
  sha256 <- .verify_db(db_path)

  # Verification is time-of-check to time-of-use: the hash is computed above and
  # dbConnect() below re-opens the path, so a file swapped between the two is
  # not caught. Accepted deliberately (see ?load_rules, Security considerations) --
  # closing it would require staging a private copy, adding a filesystem write
  # to this otherwise read-only path.
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  # The verified hash is handed to fn rather than left to be re-read later. It
  # is a measurement this call took of the file's bytes; re-reading the sidecar
  # afterwards would instead record whatever that file says at that later
  # moment, which is the very thing verification exists to distrust.
  fn(con, sha256)
}


# Verify the database against its SHA-256 sidecar. A missing sidecar or a hash
# mismatch is fatal: this is a security tool, and silently loading unverified
# rules would undermine its guarantees.
#
# Returns the hash computed from the database, so a caller that needs to record
# what it loaded can use the value measured here rather than reading the
# sidecar again.
.verify_db <- function(db_path) {
  hash_path <- paste0(db_path, ".sha256")
  if (!file.exists(hash_path)) {
    stop(
      "Rules database hash sidecar not found: ", hash_path, "\n",
      "Refusing to load unverified rules database.",
      call. = FALSE
    )
  }
  lines <- readLines(hash_path, warn = FALSE)
  if (length(lines) == 0L || !nzchar(trimws(lines[[1L]]))) {
    stop(
      "Rules database hash sidecar is empty: ", hash_path, "\n",
      "Refusing to load unverified rules database.",
      call. = FALSE
    )
  }
  expected <- trimws(lines[[1L]])
  actual   <- digest::digest(db_path, algo = "sha256", file = TRUE)
  if (!identical(tolower(expected), tolower(actual))) {
    stop(
      "Rules database failed SHA-256 verification.\n",
      "  expected: ", expected, "\n",
      "  actual:   ", actual, "\n",
      "Refusing to load a modified rules database.",
      call. = FALSE
    )
  }
  invisible(actual)
}
