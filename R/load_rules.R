# This script contains functions for verifying and reading the pkgaudit rules
# database and obtaining the database version.

#' Load security rules from the pkgaudit rules database
#'
#' Loads the file-context, code-context, pattern, and match rules, and the
#' lifecycle phases of every context, from the bundled SQLite database as a
#' named list suitable for passing to [audit_package()] or [audit_tarball()].
#'
#' @param db_path Path to the rules database. Defaults to the database bundled
#'   with the installed package.
#'
#' @return A named list of five data frames. In the four rule frames each row
#'   is a rule, the common columns are `name` and `version`, and `message` is
#'   what a finding reports; `phases` is keyed by `context` instead.
#'   \describe{
#'     \item{file_contexts}{`name`, `version`, `type`, `message`, `path`,
#'       `recursive`, `report`, `filename`, `code_context`, `assume_called`.
#'       `type` selects how a matched file is read. `report` is `TRUE` for a rule
#'       whose matches are findings in their own right. `code_context` names the
#'       code-context rules that can apply inside these files, space-separated --
#'       `NA` where none can, `"computed"` where only `top_level` and
#'       `in_function` can. `assume_called` says whether code inside a function
#'       definition is taken to run when the code around it runs, and is `NA`
#'       wherever `code_context` is.}
#'     \item{code_contexts}{`name`, `version`, `language`, `message`, `kind`,
#'       `xpath`, `segment`. `kind` is `"xpath"` for a rule matched against the
#'       parse tree and `"segment"` for one matched against a label the extractor
#'       stamped; exactly one of the two columns is set accordingly.}
#'     \item{patterns}{`name`, `version`, `language`, `message`, `attck`,
#'       `functions`, `xpath`. `functions` is the space-separated names the rule
#'       matches as a bare call, which is how [find_indirect()] attributes an
#'       indirect call back to it; empty for a rule matching on more than the
#'       callee.}
#'     \item{matches}{`name`, `version`, `language`, `message`, `attck`, `regex`.
#'       A match rule is evaluated only against code in its `language`.}
#'     \item{phases}{`context`, `version`, and one logical column per lifecycle
#'       phase. One row per file-context or code-context rule -- pattern and
#'       match rules carry no phases of their own. The computed contexts
#'       `top_level` and `in_function` have none, and need none: they inherit.}
#'   }
#'   The list carries a `"provenance"` attribute -- `db_path`, `version` and
#'   `sha256` -- which [audit_package()] reports in a scan's `metadata`. The
#'   `sha256` is the hash computed during verification, not re-read from the
#'   sidecar afterwards, so it records what this call measured.
#'
#' @details
#' Before reading, the database is verified against its SHA-256 sidecar so that a
#' tampered or corrupted rules file is rejected rather than silently trusted.
#'
#' @section Security considerations:
#' The sidecar ships beside the database, so anyone who can rewrite one can
#' rewrite the other. It is an integrity check, not an authenticity check: it
#' catches a corrupted download or a database swapped for another, and it cannot
#' catch a deliberate edit of an installed copy. The out-of-band anchor is the
#' hash published in the README, which is compared against the shipped database
#' on every commit; checking an installed copy against that is what detects a
#' tampered install, and [rules_version()] reports what a scan actually used.
#'
#' Verification is time-of-check to time-of-use: the database is hashed and then
#' re-opened by path to query it, so a file swapped in between is not detected.
#' That does not weaken the bundled default, since an attacker able to win the
#' race already has write access to the installed package. When loading rules
#' from a path other parties can write, treat the check as protection against
#' corruption or a substituted database given an authentic sidecar, not against
#' an attacker modifying the file concurrently.
#'
#' @examples
#' rules <- load_rules()
#' vapply(rules, nrow, integer(1))
#'
#' @export
load_rules <- function(db_path = .db_path()) {
  .with_db(db_path, function(con, sha256) {
    file_contexts <- DBI::dbGetQuery(
      con,
      "SELECT name, version, type, message, path, recursive, report,
              filename, code_context, assume_called
         FROM file_contexts
        ORDER BY name"
    )
    # SQLite has no native logical type; the flags are stored as 0/1.
    file_contexts$recursive     <- as.logical(file_contexts$recursive)
    file_contexts$report        <- as.logical(file_contexts$report)
    file_contexts$assume_called <- as.logical(file_contexts$assume_called)

    code_contexts <- DBI::dbGetQuery(
      con,
      "SELECT name, version, language, message, kind, xpath, segment
         FROM code_contexts
        ORDER BY name"
    )

    patterns <- DBI::dbGetQuery(
      con,
      "SELECT name, version, language, message, attck, functions, xpath
         FROM patterns
        ORDER BY name"
    )

    matches <- DBI::dbGetQuery(
      con,
      "SELECT name, version, language, message, attck, regex
         FROM matches
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
        nrow(matches) == 0L) {
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
        patterns        = patterns,
        matches         = matches,
        phases          = phases
      ),
      provenance = list(
        db_path = db_path,
        version = .query_version(con, db_path),
        sha256  = sha256
      )
    )
  })
}


# Refuse a database whose phase model has a gap. Each of these is a malformed
# database rather than a runtime condition, so it fails here rather than
# resolving to no phases somewhere downstream, where a finding that runs at
# install would be reported as running at nothing.
.validate_phase_coverage <- function(file_contexts, code_contexts, phases,
                                     db_path) {
  # Every rule needs its own phases row. The computed contexts need none: they
  # take the file context's, or none at all.
  missing <- setdiff(c(file_contexts$name, code_contexts$name), phases$context)
  if (length(missing) > 0L) {
    stop("Rules database is missing phases for: ",
         paste(missing, collapse = ", "), "\n  Database: ", db_path,
         call. = FALSE)
  }

  # Every code-context rule a file-context rule names must exist, or that rule's
  # files would be scanned for a context nothing can supply.
  named   <- unlist(strsplit(stats::na.omit(file_contexts$code_context),
                             "[[:space:]]+"))
  named   <- setdiff(unique(named[nzchar(named)]), "computed")
  unknown <- setdiff(named, code_contexts$name)
  if (length(unknown) > 0L) {
    stop("Rules database names code contexts that do not exist: ",
         paste(unknown, collapse = ", "), "\n  Database: ", db_path,
         call. = FALSE)
  }

  # A rule says whether functions defined in its files are assumed called
  # exactly where code contexts can arise there. Saying it elsewhere would be
  # noise; omitting it where it matters would leave the reading undecided.
  decided <- !is.na(file_contexts$assume_called)
  applies <- !is.na(file_contexts$code_context)
  if (any(decided != applies)) {
    bad <- file_contexts$name[decided != applies]
    stop("Rules database sets 'assume_called' where no code contexts apply, ",
         "or omits it where they do: ", paste(bad, collapse = ", "),
         "\n  Database: ", db_path, call. = FALSE)
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
#' rules_version()
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
