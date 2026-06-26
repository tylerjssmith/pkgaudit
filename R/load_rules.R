#' Load security rules from the pkgaudit rules database
#'
#' Verifies the database signature then loads rules as a named list suitable
#' for passing to [lint_file()], [lint_dir()], and [audit_package()].
#'
#' @param tier Which rules to load. One of `"stable"` (default) or
#'   `"experimental"`. Experimental rules have higher false positive rates
#'   and are subject to change without notice.
#' @param db_path Path to the SQLite rules database.
#' @param sig_path Path to the signature file.
#' @param pub_path Path to the public key.
#'
#' @return A named list of rule objects. Each element is a list with fields:
#'   \describe{
#'     \item{xpath}{XPath expression to match against the R parse tree XML.}
#'     \item{message}{Human-readable description of the dangerous pattern.}
#'     \item{type}{Severity: `"warning"` or `"message"`.}
#'     \item{attck}{MITRE ATT&CK technique identifier(s).}
#'   }
#'
#' @details
#' The database signature is verified before any rules are returned. If
#' verification fails the function stops with an informative error. See
#' [verify_db()] for details on the signature scheme.
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
  db_path  = .db_path(),
  sig_path = .sig_path(),
  pub_path = .pub_path()
) {
  tier <- match.arg(tier)

  verify_db(db_path = db_path, sig_path = sig_path, pub_path = pub_path)

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


#' Verify the integrity of the pkgaudit rules database
#'
#' Verifies the cryptographic signature of the rules database against the
#' bundled public key. Called automatically by [load_rules()] before any
#' rules are returned.
#'
#' @param db_path  Path to the SQLite rules database. Defaults to the bundled
#'   database shipped with the package.
#' @param sig_path Path to the base64-encoded signature file. Defaults to the
#'   bundled signature.
#' @param pub_path Path to the PEM-encoded public key. Defaults to the bundled
#'   public key.
#'
#' @return `TRUE` invisibly if verification succeeds. Stops with an error if
#'   verification fails.
#'
#' @details
#' The rules database is the primary attack surface of pkgaudit: an adversary
#' who can modify the database can silently remove detection for specific
#' patterns. Signature verification using a public key bundled at package
#' installation time ensures that a modified database is detected before any
#' analysis runs. The public key is a static file in `inst/db/` that is itself
#' part of the signed CRAN package.
#'
#' @examples
#' \dontrun{
#' verify_db()
#' }
#'
#' @export
verify_db <- function(
  db_path  = .db_path(),
  sig_path = .sig_path(),
  pub_path = .pub_path()
) {
  if (!file.exists(db_path)) {
    stop(
      "Rules database not found at: ", db_path, "\n",
      "Reinstall pkgaudit from a trusted source."
    )
  }
  if (!file.exists(sig_path)) {
    stop(
      "Rules database signature not found at: ", sig_path, "\n",
      "Reinstall pkgaudit from a trusted source."
    )
  }
  if (!file.exists(pub_path)) {
    stop(
      "Public key not found at: ", pub_path, "\n",
      "Reinstall pkgaudit from a trusted source."
    )
  }

  db_bytes  <- readBin(db_path, what = "raw", n = file.size(db_path))
  pubkey    <- openssl::read_pubkey(pub_path)
  signature <- openssl::base64_decode(paste(readLines(sig_path), collapse = ""))

  verified <- tryCatch(
    {
      openssl::signature_verify(db_bytes, signature, pubkey = pubkey)
      TRUE
    },
    error = function(e) FALSE
  )

  if (!verified) {
    stop(
      "Rules database signature verification FAILED.\n",
      "The rules database may have been tampered with.\n",
      "Reinstall pkgaudit from a trusted source.\n",
      "Database path: ", db_path
    )
  }

  invisible(TRUE)
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
.sig_path <- function() system.file("db", "rules.db.sig", package = "pkgaudit")
.pub_path <- function() system.file("db", "pkgaudit.pub", package = "pkgaudit")
