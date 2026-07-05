# ------------------------------------------------------------------------------
# WARNING: RUNNING THIS SCRIPT WILL INVALIDATE THE RULES DATABASE.
# This script is provided for transparency so that users can see how the rules
# database in inst/db/ is generated from the YAML files in inst/rules/. However,
# pkgaudit should be run using the database bundled with the package.
# ------------------------------------------------------------------------------
# Reads rule YAML files and writes them to the pkgaudit rules database.
#
# Dependencies:
# This script requires the DBI, RSQLite, and yaml packages. yaml is not declared
# in DESCRIPTION because it is unnecessary for using the package. If necessary,
# you can install it by running install.packages("yaml").
#
# Required YAML fields and their expected types. Used for validation in
# read_rule_yaml() before any database writes or fixture writes are attempted.
.required_fields <- list(
  name             = "character",
  version          = "character",
  type             = "character",
  attck            = "character",
  message          = "character",
  description      = "character",
  xpath            = "character",
  example_positive = "character",
  example_negative = "character"
)

.valid_types <- c("warning", "message")


# read_rule_yaml() -------------------------------------------------------------
# Reads a single YAML rule file, validates its structure and field types, and
# returns the rule as a list. Shared by load_rule_yaml() and build_fixtures()
# so that both functions reject the same invalid inputs.
#
# Arguments:
#   path    Path to a single .yaml rule file.
#
# Returns the validated rule list on success. Stops on any validation error.
read_rule_yaml <- function(path) {
  stopifnot(is.character(path), length(path) == 1L)
  stopifnot(file.exists(path))

  rule <- yaml::read_yaml(path)

  # --- Structural validation --------------------------------------------------
  missing_fields <- setdiff(names(.required_fields), names(rule))
  if (length(missing_fields) > 0L) {
    stop(
      "Missing required fields in: ", path, "\n  ",
      paste(missing_fields, collapse = ", ")
    )
  }

  extra_fields <- setdiff(names(rule), names(.required_fields))
  if (length(extra_fields) > 0L) {
    warning(
      "Unexpected fields in: ", path, "\n  ",
      paste(extra_fields, collapse = ", ")
    )
  }

  # --- Normalize sequence fields ----------------------------------------------
  # yaml::read_yaml returns a list for YAML sequences; unlist() normalises both
  # scalar strings and sequences to a plain character vector. attck is collapsed
  # immediately to a single space-separated string for DB storage.
  rule$attck            <- paste(trimws(unlist(rule$attck)), collapse = " ")
  rule$example_positive <- unlist(rule$example_positive)
  rule$example_negative <- unlist(rule$example_negative)

  # --- Type validation --------------------------------------------------------
  .example_fields <- c("example_positive", "example_negative")
  scalar_fields   <- setdiff(names(.required_fields), .example_fields)

  for (field in scalar_fields) {
    if (!is.character(rule[[field]]) || length(rule[[field]]) != 1L) {
      stop("Field '", field, "' must be a single string in: ", path)
    }
    if (nchar(trimws(rule[[field]])) == 0L) {
      stop("Field '", field, "' must not be empty or whitespace-only in: ", path)
    }
  }

  # name is used as a filesystem directory component, so restrict it to
  # characters that are safe on all platforms and cannot traverse paths.
  if (!grepl("^[a-zA-Z][a-zA-Z0-9_]{0,63}$", rule$name)) {
    stop(
      "Field 'name' must start with a letter, contain only letters, digits, ",
      "and underscores, and be at most 64 characters in: ", path
    )
  }

  .max_examples <- 20L

  for (field in .example_fields) {
    if (!is.character(rule[[field]]) || length(rule[[field]]) == 0L) {
      stop("Field '", field, "' must be a non-empty character vector in: ", path)
    }
    if (length(rule[[field]]) > .max_examples) {
      stop(
        "Field '", field, "' must not exceed ", .max_examples,
        " entries in: ", path
      )
    }
    if (any(nchar(trimws(rule[[field]])) == 0L)) {
      stop(
        "Field '", field, "' must not contain empty or whitespace-only entries in: ", path
      )
    }
  }

  if (!rule$type %in% .valid_types) {
    stop(
      "Field 'type' must be one of: ",
      paste(.valid_types, collapse = ", "),
      " in: ", path
    )
  }

  # Validate XPath syntax by evaluating against an empty document. An invalid
  # XPath would otherwise be stored silently and fail with no findings at
  # audit time. libxml2 signals invalid XPath as a warning, not an error,
  # so both conditions must be caught.
  tryCatch(
    xml2::xml_find_all(xml2::read_xml("<exprlist/>"), trimws(rule$xpath)),
    warning = function(w) stop("Invalid XPath in: ", path, "\n  ", conditionMessage(w)),
    error   = function(e) stop("Invalid XPath in: ", path, "\n  ", conditionMessage(e))
  )

  rule
}


# init_db() -------------------------------------------------------------------
# Creates a new rules database with the correct schema and an initial version
# row. Run once before the first build_rules_db() call.
#
# Arguments:
#   db_path   Path where the SQLite database should be created.
#             Defaults to inst/db/rules.db relative to the working directory.
#   version   Version string for the initial rule_versions entry.
#   notes     Optional notes for the initial version row.
#
# Will stop if the database already exists to prevent accidental overwrites.
init_db <- function(
  db_path = file.path("inst", "db", "rules.db"),
  version = "0.1.0",
  notes   = "Initial release"
) {
  stopifnot(is.character(db_path), length(db_path) == 1L)
  stopifnot(is.character(version), length(version) == 1L)

  if (file.exists(db_path)) {
    stop(
      "Database already exists: ", db_path, "\n",
      "Delete it manually before reinitializing."
    )
  }

  db_dir <- dirname(db_path)
  if (!dir.exists(db_dir)) {
    dir.create(db_dir, recursive = TRUE)
    message("Created directory: ", db_dir)
  }

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")

  DBI::dbExecute(con, "
    CREATE TABLE rule_versions (
      version     TEXT PRIMARY KEY,
      released_at TEXT NOT NULL,
      notes       TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE rules (
      name             TEXT PRIMARY KEY,
      rule_version     TEXT NOT NULL REFERENCES rule_versions(version),
      xpath            TEXT NOT NULL,
      message          TEXT NOT NULL,
      type             TEXT NOT NULL DEFAULT 'warning',
      attck            TEXT,
      description      TEXT,
      added_in         TEXT NOT NULL REFERENCES rule_versions(version),
      deprecated_in    TEXT,
      example_positive TEXT,
      example_negative TEXT
    )
  ")

  DBI::dbExecute(
    con,
    "INSERT INTO rule_versions (version, released_at, notes) VALUES (?, ?, ?)",
    params = list(version, as.character(Sys.Date()), notes)
  )

  message("Initialized database: ", db_path)
  message("Initial version: ", version)
  invisible(db_path)
}


# load_rule_yaml() -------------------------------------------------------------
# Validates a YAML rule file via read_rule_yaml(), then writes it to the
# database. Stops on any validation or write error so that build_rules_db()
# can catch and report the offending file.
#
# Arguments:
#   path    Path to a single .yaml rule file.
#   con     An open DBI connection to the rules database.
#
# Returns the rule name invisibly on success.
load_rule_yaml <- function(path, con) {
  rule <- read_rule_yaml(path)

  # --- Verify version exists in rule_versions ---------------------------------
  version_exists <- DBI::dbGetQuery(
    con,
    "SELECT 1 FROM rule_versions WHERE version = ?",
    params = list(rule$version)
  )
  if (nrow(version_exists) == 0L) {
    stop(
      "Version '", rule$version, "' not found in rule_versions table. ",
      "Add it before loading rules that reference it. File: ", path
    )
  }

  # --- Upsert -----------------------------------------------------------------
  # ON CONFLICT ... DO UPDATE preserves added_in on updates so the original
  # introduction version is never overwritten when a rule is revised.
  DBI::dbExecute(
    con,
    "INSERT INTO rules
       (name, rule_version, xpath, message, type, attck, description,
        added_in, example_positive, example_negative)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(name) DO UPDATE SET
       rule_version     = excluded.rule_version,
       xpath            = excluded.xpath,
       message          = excluded.message,
       type             = excluded.type,
       attck            = excluded.attck,
       description      = excluded.description,
       example_positive = excluded.example_positive,
       example_negative = excluded.example_negative",
    params = list(
      rule$name,
      rule$version,
      trimws(rule$xpath),
      trimws(rule$message),
      rule$type,
      rule$attck,
      trimws(rule$description),
      rule$version,
      paste(trimws(rule$example_positive), collapse = "\n\n"),
      paste(trimws(rule$example_negative), collapse = "\n\n")
    )
  )

  message("  Loaded: ", rule$name)
  invisible(rule$name)
}


# build_rules_db() -------------------------------------------------------------
# Applies load_rule_yaml() to every .yaml file in a directory and writes a
# SHA-256 hash of the resulting database to a sidecar file.
#
# Arguments:
#   rules_dir  Path to directory containing .yaml rule files.
#              Defaults to inst/rules/ relative to the working directory.
#   db_path    Path to the SQLite rules database.
#              Defaults to inst/db/rules.db relative to the working directory.
#
# Returns a named character vector of rule names on success, invisibly.
build_rules_db <- function(
  rules_dir = file.path("inst", "rules"),
  db_path   = file.path("inst", "db", "rules.db")
) {
  stopifnot(is.character(rules_dir), length(rules_dir) == 1L)
  stopifnot(is.character(db_path),   length(db_path)   == 1L)

  if (!dir.exists(rules_dir)) {
    stop("Rules directory not found: ", rules_dir)
  }
  if (!file.exists(db_path)) {
    stop("Database not found: ", db_path)
  }

  yaml_files <- list.files(rules_dir, pattern = "\\.ya?ml$", full.names = TRUE)
  if (length(yaml_files) == 0L) {
    stop("No YAML files found in: ", rules_dir)
  }

  message("Building rules database from ", length(yaml_files), " YAML files...")

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")

  # Wrap all writes in a single transaction so that a validation failure in any
  # file leaves the database unchanged rather than partially updated.
  DBI::dbExecute(con, "BEGIN TRANSACTION")

  loaded <- tryCatch({
    rule_names <- character(length(yaml_files))
    for (i in seq_along(yaml_files)) {
      rule_names[[i]] <- load_rule_yaml(yaml_files[[i]], con)
    }
    DBI::dbExecute(con, "COMMIT")
    rule_names
  }, error = function(e) {
    DBI::dbExecute(con, "ROLLBACK")
    stop("Database rolled back due to error:\n  ", conditionMessage(e))
  })

  # --- Write SHA-256 hash -----------------------------------------------------
  hash_path <- paste0(db_path, ".sha256")
  hash      <- digest::digest(db_path, algo = "sha256", file = TRUE)
  writeLines(hash, hash_path)

  message(
    "Done. ", length(loaded), " rules written.\n",
    "SHA-256: ", hash, "\n",
    "Hash written to: ", hash_path
  )

  invisible(setNames(loaded, loaded))
}


# build_fixtures() -------------------------------------------------------------
# Generates test fixture files from the example_positive and example_negative
# fields in each YAML rule file. Creates one subdirectory per rule under the
# fixtures directory, containing positive.R and negative.R.
#
# Fixtures are regenerated from YAML on every call, so they stay in sync with
# the YAML source. Run this alongside build_rules_db() whenever rules change.
#
# Arguments:
#   rules_dir    Path to directory containing .yaml rule files.
#                Defaults to inst/rules/ relative to the working directory.
#   fixtures_dir Path to the fixtures root directory.
#                Defaults to tests/testthat/fixtures/rules/ relative to the
#                working directory.
#
# Returns a named character vector of rule names on success, invisibly.
build_fixtures <- function(
  rules_dir    = file.path("inst", "rules"),
  fixtures_dir = file.path("tests", "testthat", "fixtures", "rules")
) {
  stopifnot(is.character(rules_dir),    length(rules_dir)    == 1L)
  stopifnot(is.character(fixtures_dir), length(fixtures_dir) == 1L)

  if (!dir.exists(rules_dir)) {
    stop("Rules directory not found: ", rules_dir)
  }

  yaml_files <- list.files(rules_dir, pattern = "\\.ya?ml$", full.names = TRUE)
  if (length(yaml_files) == 0L) {
    stop("No YAML files found in: ", rules_dir)
  }

  if (!dir.exists(fixtures_dir)) {
    dir.create(fixtures_dir, recursive = TRUE)
    message("Created fixtures directory: ", fixtures_dir)
  }

  message(
    "Building fixtures from ", length(yaml_files), " YAML files..."
  )

  rule_names <- character(length(yaml_files))

  for (i in seq_along(yaml_files)) {
    path <- yaml_files[[i]]
    rule <- read_rule_yaml(path)

    rule_dir <- file.path(fixtures_dir, rule$name)
    if (!dir.exists(rule_dir)) {
      dir.create(rule_dir, recursive = TRUE)
    }

    # Remove all existing fixture files to stay in sync with current YAML
    old_files <- list.files(
      rule_dir, pattern = "^(positive|negative)(_[0-9]+)?\\.R$", full.names = TRUE
    )
    if (length(old_files) > 0L) file.remove(old_files)

    for (j in seq_along(rule$example_positive)) {
      writeLines(
        trimws(rule$example_positive[[j]]),
        file.path(rule_dir, sprintf("positive_%d.R", j))
      )
    }
    for (j in seq_along(rule$example_negative)) {
      writeLines(
        trimws(rule$example_negative[[j]]),
        file.path(rule_dir, sprintf("negative_%d.R", j))
      )
    }

    message("  Fixtures written: ", rule$name)
    rule_names[[i]] <- rule$name
  }

  message("Done. Fixtures written for ", length(rule_names), " rules.")
  invisible(setNames(rule_names, rule_names))
}
