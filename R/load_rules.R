#' Load security rules from the pkgaudit rules database
#'
#' Loads rules from database as a named list suitable for passing to
#' [audit_file()], [audit_dir()], and [audit_package()].
#'
#' @param db_path Path to SQLite rules database.
#'
#' @return A named list of rule objects. Each element is a list with fields:
#'   \describe{
#'     \item{xpath}{XPath expression to match against the R parse tree XML.}
#'     \item{message}{Human-readable description of the dangerous pattern.}
#'     \item{type}{Severity: `"warning"` or `"message"`.}
#'     \item{attck}{MITRE ATT&CK technique identifier(s).}
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
    rows <- DBI::dbGetQuery(
      con,
      "SELECT name, xpath, message, type, attck
       FROM rules
       WHERE deprecated_in IS NULL
       ORDER BY name"
    )

    if (nrow(rows) == 0L) {
      stop("No rules found in rules database: ", db_path)
    }

    rules <- lapply(seq_len(nrow(rows)), function(i) {
      list(
        xpath   = rows$xpath[[i]],
        message = rows$message[[i]],
        type    = rows$type[[i]],
        attck   = rows$attck[[i]]
      )
    })
    setNames(rules, rows$name)
  })
}


#' Return the current rules database version
#'
#' Returns the version string of the rules database currently shipped with
#' the package. Findings reports should always record the rules version to
#' ensure reproducibility across audit cycles.
#'
#' @param db_path Path to SQLite rules database.
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

.with_db <- function(db_path, fn) {
  if (!nzchar(db_path) || !file.exists(db_path)) {
    stop(
      "Rules database not found: ",
      if (nzchar(db_path)) db_path else "(empty path -- is pkgaudit installed?)"
    )
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  fn(con)
}
