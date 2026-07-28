# ------------------------------------------------------------------------------
# WARNING: RUNNING THIS SCRIPT WILL OVERWRITE AND RE-HASH THE RULES DATABASE.
# It is provided for transparency so users can see how inst/db/rules.db is
# generated from the YAML files in inst/rules/. pkgaudit itself should be run
# against the database bundled with the package.
# ------------------------------------------------------------------------------
# Reads the file-context, code-context, and pattern rule YAML files, validates
# them, writes them to a fresh SQLite database, records a SHA-256 sidecar, and
# regenerates the test fixtures from the positive/negative examples.
#
# Run from the package root with:  Rscript inst/scripts/build_db.R
#
# Dependencies: DBI, RSQLite, xml2, digest, and yaml. yaml is declared only in
# Suggests because it is not needed to use the package.

# --- Rule schemas -------------------------------------------------------------
# Scalar (single-string) fields required in each rule class, plus the example
# fields. attck (patterns) and recursive (file contexts) are handled specially.
.file_context_scalars <- c("name", "version", "type", "message", "path", "pattern")
.code_context_scalars <- c("name", "version", "type", "message", "xpath")
.pattern_scalars      <- c("name", "version", "type", "message", "xpath")

.example_fields <- c("positive_examples", "negative_examples")

.valid_types <- list(
  file_context = c("R", "shell", "make", "other"),
  code_context = c("top-level", "hook", "other"),
  pattern      = c("warning", "note")
)

# A generous cap. This is not a style limit -- it exists so a malicious or
# malformed rule file cannot make the build allocate without bound.
.max_examples <- 50L


# --- Validation ---------------------------------------------------------------

# Shared checks: name safety, scalar non-emptiness, type, and examples.
.validate_common <- function(rule, path, scalars, class) {
  if (!grepl("^[a-zA-Z][a-zA-Z0-9_]{0,63}$", rule$name %||% "")) {
    stop(
      "Field 'name' must start with a letter, contain only letters, digits, ",
      "and underscores, and be at most 64 characters in: ", path
    )
  }

  for (field in scalars) {
    if (!is.character(rule[[field]]) || length(rule[[field]]) != 1L) {
      stop("Field '", field, "' must be a single string in: ", path)
    }
    if (nchar(trimws(rule[[field]])) == 0L) {
      stop("Field '", field, "' must not be empty or whitespace-only in: ", path)
    }
  }

  if (!rule$type %in% .valid_types[[class]]) {
    stop(
      "Field 'type' must be one of: ",
      paste(.valid_types[[class]], collapse = ", "), " in: ", path
    )
  }

  for (field in .example_fields) {
    ex <- unlist(rule[[field]])
    if (!is.character(ex) || length(ex) == 0L) {
      stop("Field '", field, "' must be a non-empty sequence in: ", path)
    }
    if (length(ex) > .max_examples) {
      stop("Field '", field, "' must not exceed ", .max_examples,
           " entries in: ", path)
    }
    if (any(nchar(trimws(ex)) == 0L)) {
      stop("Field '", field, "' must not contain empty entries in: ", path)
    }
  }
}

# Validate that a string compiles as an XPath by evaluating it against an empty
# document. libxml2 signals an invalid XPath as a warning, so both a warning
# and an error must be caught.
.validate_xpath <- function(xpath, path) {
  tryCatch(
    xml2::xml_find_all(xml2::read_xml("<exprlist/>"), trimws(xpath)),
    warning = function(w) stop("Invalid XPath in: ", path, "\n  ", conditionMessage(w)),
    error   = function(e) stop("Invalid XPath in: ", path, "\n  ", conditionMessage(e))
  )
  invisible(TRUE)
}

# Validate that a string compiles as a regular expression.
.validate_regex <- function(pattern, path) {
  ok <- tryCatch({
    grepl(pattern, "x")
    TRUE
  }, error = function(e) stop("Invalid regex 'pattern' in: ", path, "\n  ",
                              conditionMessage(e)))
  invisible(ok)
}

`%||%` <- function(a, b) if (is.null(a)) b else a


# read_file_context_yaml() / read_code_context_yaml() / read_pattern_yaml() ----
# Each reads one YAML file, validates it, and returns a normalized rule list.

read_file_context_yaml <- function(path) {
  stopifnot(file.exists(path))
  rule <- yaml::read_yaml(path)

  expected <- c(.file_context_scalars, "recursive", .example_fields)
  .check_fields(rule, expected, path)
  .validate_common(rule, path, .file_context_scalars, "file_context")

  if (!is.logical(rule$recursive) || length(rule$recursive) != 1L ||
      is.na(rule$recursive)) {
    stop("Field 'recursive' must be TRUE or FALSE in: ", path)
  }
  if (grepl("\\.\\.", rule$path)) {
    stop("Field 'path' must not contain '..' in: ", path)
  }
  .validate_regex(rule$pattern, path)

  rule$positive_examples <- unlist(rule$positive_examples)
  rule$negative_examples <- unlist(rule$negative_examples)
  rule
}

read_code_context_yaml <- function(path) {
  stopifnot(file.exists(path))
  rule <- yaml::read_yaml(path)

  expected <- c(.code_context_scalars, .example_fields)
  .check_fields(rule, expected, path)
  .validate_common(rule, path, .code_context_scalars, "code_context")
  .validate_xpath(rule$xpath, path)

  rule$positive_examples <- unlist(rule$positive_examples)
  rule$negative_examples <- unlist(rule$negative_examples)
  rule
}

read_pattern_yaml <- function(path) {
  stopifnot(file.exists(path))
  rule <- yaml::read_yaml(path)

  expected <- c(.pattern_scalars, "attck", .example_fields)
  .check_fields(rule, expected, path)
  .validate_common(rule, path, .pattern_scalars, "pattern")
  .validate_xpath(rule$xpath, path)

  attck <- trimws(unlist(rule$attck))
  if (length(attck) == 0L || any(nchar(attck) == 0L)) {
    stop("Field 'attck' must be a non-empty sequence of labels in: ", path)
  }
  rule$attck <- paste(attck, collapse = " ")

  rule$positive_examples <- unlist(rule$positive_examples)
  rule$negative_examples <- unlist(rule$negative_examples)
  rule
}

# Reject missing required fields; warn on unexpected extras.
.check_fields <- function(rule, expected, path) {
  missing_fields <- setdiff(expected, names(rule))
  if (length(missing_fields) > 0L) {
    stop("Missing required fields in: ", path, "\n  ",
         paste(missing_fields, collapse = ", "))
  }
  extra_fields <- setdiff(names(rule), expected)
  if (length(extra_fields) > 0L) {
    warning("Unexpected fields in: ", path, "\n  ",
            paste(extra_fields, collapse = ", "))
  }
  invisible(TRUE)
}


# --- Database -----------------------------------------------------------------

# Create a fresh rules database with the three rule tables, a rule_versions
# table, and the seed versions. Overwrites any existing file.
#
# Every version a rule declares must appear here: .assert_version() refuses to
# load a rule whose version has no row, so a bumped rule cannot slip in without
# its release being recorded. Rows are inserted in order, and rules_version()
# reports the last one, so the newest release goes last.
init_db <- function(
  db_path  = file.path("inst", "db", "rules.db"),
  versions = list(
    c("0.1.0", "Initial release"),
    c("0.2.0", "Expanded pattern rule coverage")
  )
) {
  db_dir <- dirname(db_path)
  if (!dir.exists(db_dir)) dir.create(db_dir, recursive = TRUE)
  if (file.exists(db_path)) unlink(db_path)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")

  DBI::dbExecute(con, "
    CREATE TABLE rule_versions (
      version     TEXT PRIMARY KEY,
      released_at TEXT NOT NULL,
      notes       TEXT
    )")

  DBI::dbExecute(con, "
    CREATE TABLE file_contexts (
      name      TEXT PRIMARY KEY,
      version   TEXT NOT NULL REFERENCES rule_versions(version),
      type      TEXT NOT NULL,
      message   TEXT NOT NULL,
      path      TEXT NOT NULL,
      recursive INTEGER NOT NULL,
      pattern   TEXT NOT NULL
    )")

  DBI::dbExecute(con, "
    CREATE TABLE code_contexts (
      name    TEXT PRIMARY KEY,
      version TEXT NOT NULL REFERENCES rule_versions(version),
      type    TEXT NOT NULL,
      message TEXT NOT NULL,
      xpath   TEXT NOT NULL
    )")

  DBI::dbExecute(con, "
    CREATE TABLE patterns (
      name    TEXT PRIMARY KEY,
      version TEXT NOT NULL REFERENCES rule_versions(version),
      type    TEXT NOT NULL,
      message TEXT NOT NULL,
      attck   TEXT NOT NULL,
      xpath   TEXT NOT NULL
    )")

  for (v in versions) {
    DBI::dbExecute(
      con,
      "INSERT INTO rule_versions (version, released_at, notes) VALUES (?, ?, ?)",
      params = list(v[[1L]], as.character(Sys.Date()), v[[2L]])
    )
  }

  message("Initialized database: ", db_path, " (versions ",
          paste(vapply(versions, `[[`, character(1L), 1L), collapse = ", "), ")")
  invisible(db_path)
}

.assert_version <- function(con, version, path) {
  exists <- DBI::dbGetQuery(
    con, "SELECT 1 FROM rule_versions WHERE version = ?", params = list(version)
  )
  if (nrow(exists) == 0L) {
    stop("Version '", version, "' not found in rule_versions. File: ", path)
  }
}

load_file_context <- function(rule, con, path) {
  .assert_version(con, rule$version, path)
  DBI::dbExecute(
    con,
    "INSERT INTO file_contexts (name, version, type, message, path, recursive, pattern)
     VALUES (?, ?, ?, ?, ?, ?, ?)",
    params = list(rule$name, rule$version, rule$type, trimws(rule$message),
                  trimws(rule$path), as.integer(rule$recursive), trimws(rule$pattern))
  )
  invisible(rule$name)
}

load_code_context <- function(rule, con, path) {
  .assert_version(con, rule$version, path)
  DBI::dbExecute(
    con,
    "INSERT INTO code_contexts (name, version, type, message, xpath)
     VALUES (?, ?, ?, ?, ?)",
    params = list(rule$name, rule$version, rule$type, trimws(rule$message),
                  trimws(rule$xpath))
  )
  invisible(rule$name)
}

load_pattern <- function(rule, con, path) {
  .assert_version(con, rule$version, path)
  DBI::dbExecute(
    con,
    "INSERT INTO patterns (name, version, type, message, attck, xpath)
     VALUES (?, ?, ?, ?, ?, ?)",
    params = list(rule$name, rule$version, rule$type, trimws(rule$message),
                  rule$attck, trimws(rule$xpath))
  )
  invisible(rule$name)
}


# build_rules_db() -------------------------------------------------------------
# Validate and load every YAML file under rules_root/{file_contexts,
# code_contexts,patterns} into db_path, then write the SHA-256 sidecar. All
# writes run in one transaction: any validation failure rolls back the DB.
build_rules_db <- function(
  rules_root = file.path("inst", "rules"),
  db_path    = file.path("inst", "db", "rules.db")
) {
  classes <- list(
    file_contexts = list(reader = read_file_context_yaml, loader = load_file_context),
    code_contexts = list(reader = read_code_context_yaml, loader = load_code_context),
    patterns      = list(reader = read_pattern_yaml,      loader = load_pattern)
  )

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  DBI::dbExecute(con, "BEGIN TRANSACTION")

  loaded <- tryCatch({
    names_loaded <- character(0L)
    for (cls in names(classes)) {
      dir <- file.path(rules_root, cls)
      if (!dir.exists(dir)) stop("Rules directory not found: ", dir)
      yaml_files <- list.files(dir, pattern = "\\.ya?ml$", full.names = TRUE)
      if (length(yaml_files) == 0L) stop("No YAML files found in: ", dir)
      for (f in yaml_files) {
        rule <- classes[[cls]]$reader(f)
        classes[[cls]]$loader(rule, con, f)
        message("  Loaded [", cls, "]: ", rule$name)
        names_loaded <- c(names_loaded, rule$name)
      }
    }
    DBI::dbExecute(con, "COMMIT")
    names_loaded
  }, error = function(e) {
    DBI::dbExecute(con, "ROLLBACK")
    stop("Database rolled back due to error:\n  ", conditionMessage(e))
  })

  hash_path <- paste0(db_path, ".sha256")
  hash      <- digest::digest(db_path, algo = "sha256", file = TRUE)
  writeLines(hash, hash_path)

  message("Done. ", length(loaded), " rules written.\n",
          "SHA-256: ", hash, "\nHash written to: ", hash_path)
  invisible(loaded)
}


# build_fixtures() -------------------------------------------------------------
# Regenerate one fixture file per positive/negative example so the fixtures
# stay in sync with the YAML source. File-context examples are path strings
# (written as .txt); code-context and pattern examples are R code (.R).
build_fixtures <- function(
  rules_root   = file.path("inst", "rules"),
  fixtures_dir = file.path("tests", "testthat", "fixtures")
) {
  classes <- list(
    file_contexts = list(reader = read_file_context_yaml, ext = "txt"),
    code_contexts = list(reader = read_code_context_yaml, ext = "R"),
    patterns      = list(reader = read_pattern_yaml,      ext = "R")
  )

  for (cls in names(classes)) {
    src_dir <- file.path(rules_root, cls)
    if (!dir.exists(src_dir)) stop("Rules directory not found: ", src_dir)
    yaml_files <- list.files(src_dir, pattern = "\\.ya?ml$", full.names = TRUE)
    ext        <- classes[[cls]]$ext

    for (f in yaml_files) {
      rule     <- classes[[cls]]$reader(f)
      rule_dir <- file.path(fixtures_dir, cls, rule$name)
      if (!dir.exists(rule_dir)) dir.create(rule_dir, recursive = TRUE)

      old <- list.files(
        rule_dir,
        pattern    = sprintf("^(positive|negative)_[0-9]+\\.%s$", ext),
        full.names = TRUE
      )
      if (length(old) > 0L) file.remove(old)

      for (j in seq_along(rule$positive_examples)) {
        writeLines(trimws(rule$positive_examples[[j]]),
                   file.path(rule_dir, sprintf("positive_%d.%s", j, ext)))
      }
      for (j in seq_along(rule$negative_examples)) {
        writeLines(trimws(rule$negative_examples[[j]]),
                   file.path(rule_dir, sprintf("negative_%d.%s", j, ext)))
      }
      message("  Fixtures [", cls, "]: ", rule$name)
    }
  }

  message("Done. Fixtures regenerated under: ", fixtures_dir)
  invisible(TRUE)
}


# --- Entry point --------------------------------------------------------------
main <- function() {
  db_path <- file.path("inst", "db", "rules.db")
  init_db(db_path)
  build_rules_db(db_path = db_path)
  build_fixtures()
  invisible(TRUE)
}

# Run main() when invoked as `Rscript inst/scripts/build_db.R` (top-level),
# but not when the file is sourced for its function definitions.
if (identical(environment(), globalenv()) && !interactive() &&
    sys.nframe() == 0L) {
  main()
}
