#' Load security rules from the pkgaudit rules database
#'
#' Loads rules from database as a named list suitable for passing to
#' [lint_file()], [lint_dir()], and [audit_package()].
#'
#' @param tier Which rules to load. One of `"stable"` (default) or
#'   `"experimental"`. Experimental rules have higher false positive rates
#'   and are subject to change without notice.
#' @param db_path Path to the SQLite rules database.
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
#' rules <- load_rules(tier = "experimental")
#' }
#'
#' @export
load_rules <- function(
  tier     = c("stable", "experimental"),
  db_path  = .db_path()
) {
  tier <- match.arg(tier)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  rows <- DBI::dbGetQuery(
    con,
    "SELECT name, xpath, message, type, attck
     FROM linters
     WHERE tier = ? AND deprecated_in IS NULL
     ORDER BY name",
    params = list(tier)
  )

  if (nrow(rows) == 0L) {
    warning("No rules found for tier: ", tier)
    return(list())
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
}


#' Return the current rules database version
#'
#' Returns the version string of the rules database currently shipped with
#' the package. Findings reports should always record the rules version to
#' ensure reproducibility across audit cycles.
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
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  version <- DBI::dbGetQuery(
    con,
    "SELECT version FROM rule_versions ORDER BY released_at DESC LIMIT 1"
  )

  if (nrow(version) == 0L) {
    stop("No version found in rules database. The database may be corrupt.")
  }

  version$version[[1L]]
}


# --- Helpers ------------------------------------------------------------------
# Default paths to bundled database, signature, and public key
.db_path  <- function() system.file("db", "rules.db",     package = "pkgaudit")
