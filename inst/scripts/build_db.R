# ------------------------------------------------------------------------------
# WARNING: RUNNING THIS SCRIPT WILL OVERWRITE AND RE-HASH THE RULES DATABASE.
# It is provided for transparency so users can see how inst/db/rules.db is
# generated from the YAML files in inst/rules/. pkgaudit itself should be run
# against the database bundled with the package.
# ------------------------------------------------------------------------------
# Reads the file-context, code-context, pattern, and match rule YAML files,
# validates them, writes them to a fresh SQLite database, records a SHA-256
# sidecar, and regenerates the test fixtures from the examples.
#
# Run from the package root with:  Rscript inst/scripts/build_db.R
#
# Dependencies: DBI, RSQLite, xml2, digest, and yaml. yaml is declared only in
# Suggests because it is not needed to use the package.

# --- Rule schemas -------------------------------------------------------------
# Scalar (single-string) fields required in each rule class, plus the example
# fields. attck (patterns) and recursive (file contexts) are handled specially.
.file_context_scalars <- c("name", "version", "type", "message", "path",
                           "filename")
.code_context_scalars <- c("name", "version", "language", "message", "kind")
.pattern_scalars      <- c("name", "version", "language", "message", "xpath")
.match_scalars        <- c("name", "version", "language", "message", "regex")

.example_fields <- c("positive_examples", "negative_examples")

# Lifecycle phases. Every file- and code-context rule declares all nine, hoisted
# out of the rule into the phases table. Pattern rules do not declare them: a
# pattern inherits its phases from the file context it was found in and the code
# context it sits in.
.phase_fields <- c(
  "at_autoconf", "at_build", "at_check", "at_install_src", "at_install_bin",
  "at_load", "at_attach", "at_unload", "at_detach"
)

# How a code-context rule decides whether it applies.
#
# "xpath" evaluates an XPath against the R parse tree, which is how the
# lifecycle hooks are found. "segment" matches a label the extractor stamped on
# the segment, which is the only way to reach a distinction the parse tree
# cannot see: by the time an .Rd file has yielded R code, nothing in that code
# says whether it came from \examples or from a \Sexpr.
.code_context_kinds <- c("xpath", "segment")

# The segment labels the extractors stamp, and therefore the only values a
# kind: segment rule can match on. A rule naming anything else could never fire,
# so it is refused here rather than shipped inert.
.segment_labels <- c("Rd_examples", "Rd_Sexpr_build", "Rd_Sexpr_install",
                     "Rd_Sexpr_render")

# The computed code contexts, which no rule defines.
#
# They need no phases of their own. Top-level code carries the phases of the
# file context it sits in, and code inside a function definition carries the
# phases of whatever encloses it -- unless that file context sets
# `assume_called: FALSE`, in which case it carries none. Both readings are
# measured; see the execution_surface probe.
.context_top_level <- "top_level"
.context_in_function <- "in_function"

# The two axes a rule can name, and neither is a severity: severity is a
# property of a pattern together with the context it was found in, which a rule
# is in no position to know.
#
# A file context declares a `type`, the format of the file, which selects how
# the file is read. "R" is read verbatim and parsed; "Rd" has its \examples and
# \Sexpr code extracted first; "Rmd", "qmd", "Rnw" and "rsp" have their chunks,
# inline code or templated code extracted; "shell" and "make" are matched line
# by line; "other" is reported but never read.
#
# Every other class declares a `language`, the language of the code it is
# evaluated against. One file can yield code in more than one language, so this
# is a separate axis from the file's type rather than a restatement of it.
.valid_values <- list(
  file_context = list(field = "type",
                      values = c("R", "Rd", "Rmd", "qmd", "Rnw", "rsp",
                                 "shell", "make", "other")),
  code_context = list(field = "language", values = c("R")),
  pattern      = list(field = "language", values = c("R")),
  match        = list(field = "language", values = c("shell"))
)

# A generous cap. This is not a style limit -- it exists so a malicious or
# malformed rule file cannot make the build allocate without bound.
.max_examples <- 50L


# --- Validation ---------------------------------------------------------------

# Shared checks: name safety, scalar non-emptiness, the class's type or language
# field, and examples.
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

  if (class %in% names(.valid_values)) {
    spec <- .valid_values[[class]]
    if (!rule[[spec$field]] %in% spec$values) {
      stop(
        "Field '", spec$field, "' must be one of: ",
        paste(spec$values, collapse = ", "), " in: ", path
      )
    }
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
    warning = function(w) stop("Invalid XPath in: ", path, "\n  ",
      conditionMessage(w)),
    error   = function(e) stop("Invalid XPath in: ", path, "\n  ",
      conditionMessage(e))
  )
  invisible(TRUE)
}

# Validate a pattern rule's `functions`: the names it matches as a bare call.
#
# Each name is accepted only if calling it bare would have matched this rule's
# own XPath. That makes the field a checked restatement of the XPath rather than
# a second source of truth, so find_indirect() can never attribute
# do.call("x", ...) to a rule that would not have matched a direct call to x.
#
# The list may be empty, and for three rules it must be: do.call() carries the
# callee's name and nothing else, so a rule matching on argument structure or a
# package qualifier has no name it can claim. Empty is written out rather than
# left off, so a deliberate omission is distinguishable from a forgotten one.
.validate_functions <- function(rule, path) {
  names_declared <- trimws(unlist(rule$functions))
  if (length(names_declared) == 0L) return(character(0L))
  if (any(nchar(names_declared) == 0L)) {
    stop("Field 'functions' must not contain empty names in: ", path)
  }

  for (name in names_declared) {
    tree <- tryCatch(
      xml2::read_xml(xmlparsedata::xml_parse_data(
        parse(text = paste0(name, "()"), keep.source = TRUE)
      )),
      error = function(e) e
    )
    if (inherits(tree, "condition")) {
      stop("Field 'functions' has a name that is not a valid call, '", name,
           "', in: ", path)
    }
    if (length(xml2::xml_find_all(tree, trimws(rule$xpath))) == 0L) {
      stop("Field 'functions' names '", name, "', which this rule's own XPath ",
           "does not match as a bare call, in: ", path)
    }
  }
  names_declared
}

# Validate that every phase field is present as TRUE or FALSE.
.validate_phases <- function(rule, path) {
  for (field in .phase_fields) {
    value <- rule[[field]]
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      stop("Field '", field, "' must be TRUE or FALSE in: ", path)
    }
  }
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

# Validate a match rule's regex under the engine find_matches() uses. A
# regex is also refused if it matches the empty string: such an expression
# matches at every position of every line, so one rule would bury a scan in
# findings.
.validate_regex_expression <- function(regex, path) {
  ok <- tryCatch(
    regexpr(regex, "", perl = TRUE, useBytes = FALSE),
    warning = function(w) stop("Invalid regex in: ", path, "\n  ",
                               conditionMessage(w)),
    error   = function(e) stop("Invalid regex in: ", path, "\n  ",
                               conditionMessage(e))
  )
  if (as.integer(ok) > 0L) {
    stop("Field 'regex' must not match the empty string in: ", path)
  }
  invisible(TRUE)
}

# Validate a file-context rule's `code_context`, which says which code contexts
# can apply inside the files this rule claims. One of three forms:
#
#   null        no code contexts apply. Either the type carries no R at all, as
#               shell and make do, or it is never read, as "other" is.
#   "computed"  only the computed contexts: top level, or inside a function.
#   a list      those code-context rules are tried first, then the computed
#               ones. This is what confines the lifecycle hooks to the
#               directories whose code becomes the namespace -- a .onLoad in
#               data/ ships as an ordinary object and is never called.
#
# The field is required even when it is null, so that "no code contexts apply"
# is a decision on the record rather than an omission, the same reason a pattern
# rule writes out an empty `functions`.
.validate_code_context_spec <- function(rule, path) {
  spec <- rule$code_context
  if (is.null(spec)) return(NULL)

  spec <- unlist(spec)
  if (!is.character(spec) || length(spec) == 0L || any(is.na(spec))) {
    stop("Field 'code_context' must be null, \"computed\", or a sequence of ",
         "code-context rule names in: ", path)
  }
  spec <- trimws(spec)
  if (identical(spec, "computed")) return("computed")

  if (any(!nzchar(spec))) {
    stop("Field 'code_context' must not contain empty names in: ", path)
  }
  if ("computed" %in% spec) {
    stop("Field 'code_context' must not mix \"computed\" with rule names in: ",
         path, "\n  The computed contexts are always tried after the named ",
         "ones, so listing both says nothing extra.")
  }
  spec
}

# Validate a file-context rule's `assume_called`: whether code inside a function
# definition in these files is taken to run when the code around it runs.
#
# There are exactly two measured answers, so this is a flag rather than a set of
# phases. The probe package establishes both: a function called from top level
# fires wherever that top-level code does, and one nothing calls fires nowhere.
# A rule choosing between them is choosing which measurement to report; it
# cannot invent a third, which a free-form block of phases would allow.
#
# Null exactly where `code_context` is null. A shell script or a file that is
# never read has no function bodies to decide about, and saying something about
# them anyway would be noise the reader has to dismiss.
.validate_assume_called <- function(rule, path) {
  value    <- rule$assume_called
  needs_it <- !is.null(rule$code_context)

  if (!needs_it) {
    if (!is.null(value)) {
      stop("Field 'assume_called' must be null where 'code_context' is, in: ",
           path, "\n  No code contexts apply here, so there are no function ",
           "bodies to decide about.")
    }
    return(NULL)
  }
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    stop("Field 'assume_called' must be TRUE or FALSE in: ", path)
  }
  value
}


`%||%` <- function(a, b) if (is.null(a)) b else a


# read_*_yaml() ---------------------------------------------------------------
# Each reads one YAML file, validates it, and returns a normalized rule list.

read_file_context_yaml <- function(path) {
  stopifnot(file.exists(path))
  rule <- yaml::read_yaml(path)

  expected <- c(.file_context_scalars, "recursive", "report", "code_context",
                "assume_called", .phase_fields, .example_fields)
  .check_fields(rule, expected, path)
  .validate_common(rule, path, .file_context_scalars, "file_context")
  .validate_phases(rule, path)

  for (field in c("recursive", "report")) {
    value <- rule[[field]]
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      stop("Field '", field, "' must be TRUE or FALSE in: ", path)
    }
  }
  if (grepl("\\.\\.", rule$path)) {
    stop("Field 'path' must not contain '..' in: ", path)
  }
  .validate_regex(rule$filename, path)

  rule$code_context  <- .validate_code_context_spec(rule, path)
  rule$assume_called <- .validate_assume_called(rule, path)

  rule$positive_examples <- unlist(rule$positive_examples)
  rule$negative_examples <- unlist(rule$negative_examples)
  rule
}

read_code_context_yaml <- function(path) {
  stopifnot(file.exists(path))
  rule <- yaml::read_yaml(path)

  expected <- c(.code_context_scalars, .phase_fields, .example_fields)
  .check_fields(rule, expected, path, optional = c("xpath", "segment"))
  .validate_common(rule, path, .code_context_scalars, "code_context")
  .validate_phases(rule, path)

  if (!rule$kind %in% .code_context_kinds) {
    stop("Field 'kind' must be one of: ",
         paste(.code_context_kinds, collapse = ", "), " in: ", path)
  }

  # Exactly one discriminator, so a rule cannot carry a second one that is
  # silently never consulted.
  if (identical(rule$kind, "xpath")) {
    if (!is.null(rule$segment)) {
      stop("Field 'segment' must not be set on a kind: xpath rule in: ", path)
    }
    if (!is.character(rule$xpath) || length(rule$xpath) != 1L ||
        !nzchar(trimws(rule$xpath))) {
      stop("Field 'xpath' must be a single string on a kind: xpath rule in: ",
           path)
    }
    .validate_xpath(rule$xpath, path)
  } else {
    if (!is.null(rule$xpath)) {
      stop("Field 'xpath' must not be set on a kind: segment rule in: ", path)
    }
    if (!is.character(rule$segment) || length(rule$segment) != 1L) {
      stop("Field 'segment' must be a single string on a kind: segment rule ",
           "in: ", path)
    }
    if (!rule$segment %in% .segment_labels) {
      stop("Field 'segment' names '", rule$segment, "', which no extractor ",
           "stamps, in: ", path, "\n  Must be one of: ",
           paste(.segment_labels, collapse = ", "))
    }
  }

  rule$positive_examples <- unlist(rule$positive_examples)
  rule$negative_examples <- unlist(rule$negative_examples)
  rule
}

read_pattern_yaml <- function(path) {
  stopifnot(file.exists(path))
  rule <- yaml::read_yaml(path)

  expected <- c(.pattern_scalars, "attck", "functions", .example_fields)
  .check_fields(rule, expected, path)
  .validate_common(rule, path, .pattern_scalars, "pattern")
  .validate_xpath(rule$xpath, path)

  attck <- trimws(unlist(rule$attck))
  if (length(attck) == 0L || any(nchar(attck) == 0L)) {
    stop("Field 'attck' must be a non-empty sequence of labels in: ", path)
  }
  rule$attck <- paste(attck, collapse = " ")

  rule$functions <- paste(.validate_functions(rule, path), collapse = " ")

  rule$positive_examples <- unlist(rule$positive_examples)
  rule$negative_examples <- unlist(rule$negative_examples)
  rule
}

read_match_yaml <- function(path) {
  stopifnot(file.exists(path))
  rule <- yaml::read_yaml(path)

  expected <- c(.match_scalars, "attck", .example_fields)
  .check_fields(rule, expected, path)
  .validate_common(rule, path, .match_scalars, "match")
  .validate_regex_expression(rule$regex, path)

  attck <- trimws(unlist(rule$attck))
  if (length(attck) == 0L || any(nchar(attck) == 0L)) {
    stop("Field 'attck' must be a non-empty sequence of labels in: ", path)
  }
  rule$attck <- paste(attck, collapse = " ")

  rule$positive_examples <- unlist(rule$positive_examples)
  rule$negative_examples <- unlist(rule$negative_examples)
  rule
}

# Reject missing required fields; warn on unexpected extras. `optional` names
# fields a rule may carry but need not, and which are therefore neither required
# nor unexpected.
.check_fields <- function(rule, expected, path, optional = character(0L)) {
  missing_fields <- setdiff(expected, names(rule))
  if (length(missing_fields) > 0L) {
    stop("Missing required fields in: ", path, "\n  ",
         paste(missing_fields, collapse = ", "))
  }
  extra_fields <- setdiff(names(rule), c(expected, optional))
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
#
# Each entry carries its release date rather than reading the build clock:
# rebuilding from unchanged sources must reproduce the shipped database
# byte-for-byte, or the published SHA-256 would churn with every rebuild.
init_db <- function(
  db_path  = file.path("inst", "db", "rules.db"),
  versions = list(
    c("0.1.0", "2026-06-26", "Initial release"),
    c("0.2.0", "2026-07-15", "Expanded pattern rule coverage"),
    c("0.3.0", "2026-08-02", "Phase metadata and corrected context messages"),
    c("0.4.0", "2026-08-19", "Regex rules for shell scripts and Make-like files"),
    c("0.5.0", "2026-09-02", "Split credentials by target; jsonlite and lazyload rules")
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
      report    INTEGER NOT NULL,
      filename  TEXT NOT NULL,
      -- Which code contexts can apply inside the files this rule claims: NULL
      -- for none, 'computed' for the computed ones only, or a space-separated
      -- list of code-context rule names tried before them.
      code_context TEXT,
      -- Whether code inside a function definition here is taken to run when the
      -- top-level code around it runs.
      assume_called INTEGER
    )")

  DBI::dbExecute(con, "
    CREATE TABLE code_contexts (
      name     TEXT PRIMARY KEY,
      version  TEXT NOT NULL REFERENCES rule_versions(version),
      language TEXT NOT NULL,
      message  TEXT NOT NULL,
      -- How the rule decides it applies: 'xpath' against the R parse tree, or
      -- 'segment' against the label the extractor stamped. Exactly one of the
      -- two columns below it (xpath or segment) is set, according to this.
      kind     TEXT NOT NULL,
      xpath    TEXT,
      segment  TEXT
    )")

  DBI::dbExecute(con, "
    CREATE TABLE patterns (
      name     TEXT PRIMARY KEY,
      version  TEXT NOT NULL REFERENCES rule_versions(version),
      language TEXT NOT NULL,
      message TEXT NOT NULL,
      attck   TEXT NOT NULL,
      -- Space-separated names this rule matches as a bare call, which is what
      -- lets find_indirect() attribute do.call(\"name\", ...) back to it. May
      -- be empty, unlike attck: a rule matching on more than the callee has
      -- no name it can claim.
      functions TEXT NOT NULL,
      xpath   TEXT NOT NULL
    )")

  DBI::dbExecute(con, "
    CREATE TABLE matches (
      name     TEXT PRIMARY KEY,
      version  TEXT NOT NULL REFERENCES rule_versions(version),
      language TEXT NOT NULL,
      message  TEXT NOT NULL,
      attck    TEXT NOT NULL,
      regex    TEXT NOT NULL
    )")

  DBI::dbExecute(con, sprintf("
    CREATE TABLE phases (
      context TEXT PRIMARY KEY,
      version TEXT NOT NULL REFERENCES rule_versions(version),
      %s
    )", paste(sprintf("%s INTEGER NOT NULL", .phase_fields),
              collapse = ",\n      ")))

  for (v in versions) {
    DBI::dbExecute(
      con,
      "INSERT INTO rule_versions (version, released_at, notes) VALUES (?, ?, ?)",
      params = list(v[[1L]], v[[2L]], v[[3L]])
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
    "INSERT INTO file_contexts (name, version, type, message, path, recursive, report, filename, code_context, assume_called)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(rule$name, rule$version, rule$type, trimws(rule$message),
                  trimws(rule$path), as.integer(rule$recursive),
                  as.integer(rule$report), trimws(rule$filename),
                  # Stored space-separated, as `functions` and `attck` are.
                  if (is.null(rule$code_context)) NA_character_
                  else paste(rule$code_context, collapse = " "),
                  if (is.null(rule$assume_called)) NA_integer_
                  else as.integer(rule$assume_called))
  )
  invisible(rule$name)
}

load_code_context <- function(rule, con, path) {
  .assert_version(con, rule$version, path)
  DBI::dbExecute(
    con,
    "INSERT INTO code_contexts (name, version, language, message, kind, xpath, segment)
     VALUES (?, ?, ?, ?, ?, ?, ?)",
    params = list(rule$name, rule$version, rule$language, trimws(rule$message),
                  rule$kind,
                  if (is.null(rule$xpath)) NA_character_ else trimws(rule$xpath),
                  if (is.null(rule$segment)) NA_character_ else rule$segment)
  )
  invisible(rule$name)
}

# Insert one phases row, hoisted out of a file- or code-context rule.
load_phases <- function(context, version, values, con, path) {
  .assert_version(con, version, path)
  sql <- sprintf(
    "INSERT INTO phases (context, version, %s) VALUES (%s)",
    paste(.phase_fields, collapse = ", "),
    paste(rep("?", length(.phase_fields) + 2L), collapse = ", ")
  )
  DBI::dbExecute(con, sql, params = c(
    list(context, version),
    lapply(.phase_fields, function(field) as.integer(values[[field]]))
  ))
  invisible(context)
}

load_pattern <- function(rule, con, path) {
  .assert_version(con, rule$version, path)
  DBI::dbExecute(
    con,
    "INSERT INTO patterns (name, version, language, message, attck, functions,
                           xpath)
     VALUES (?, ?, ?, ?, ?, ?, ?)",
    params = list(rule$name, rule$version, rule$language, trimws(rule$message),
                  rule$attck, rule$functions, trimws(rule$xpath))
  )
  invisible(rule$name)
}

# The regex is stored verbatim. Unlike an XPath, leading and trailing
# whitespace in a regular expression is significant, so trimming it here could
# silently change what a rule matches.
load_match <- function(rule, con, path) {
  .assert_version(con, rule$version, path)
  DBI::dbExecute(
    con,
    "INSERT INTO matches (name, version, language, message, attck, regex)
     VALUES (?, ?, ?, ?, ?, ?)",
    params = list(rule$name, rule$version, rule$language, trimws(rule$message),
                  rule$attck, rule$regex)
  )
  invisible(rule$name)
}


# build_rules_db() -------------------------------------------------------------
# Validate and load every YAML file under rules_root/{file_contexts,
# code_contexts,patterns,matches} into db_path, then write the SHA-256 sidecar.
# All writes run in one transaction: any validation failure rolls back the DB.
build_rules_db <- function(
  rules_root = file.path("inst", "rules"),
  db_path    = file.path("inst", "db", "rules.db")
) {
  classes <- list(
    file_contexts = list(reader = read_file_context_yaml,
                         loader = load_file_context, has_phases = TRUE),
    code_contexts = list(reader = read_code_context_yaml,
                         loader = load_code_context, has_phases = TRUE),
    patterns      = list(reader = read_pattern_yaml,
                         loader = load_pattern,      has_phases = FALSE),
    matches       = list(reader = read_match_yaml,
                         loader = load_match,        has_phases = FALSE)
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
        if (isTRUE(classes[[cls]]$has_phases)) {
          load_phases(rule$name, rule$version, rule, con, f)
        }
        message("  Loaded [", cls, "]: ", rule$name)
        names_loaded <- c(names_loaded, rule$name)
      }
    }

    # Every code-context rule a file-context rule names must exist, or that
    # rule's files would be scanned for a context nothing can supply.
    declared <- DBI::dbGetQuery(
      con, "SELECT name, code_context FROM file_contexts
             WHERE code_context IS NOT NULL AND code_context != 'computed'")
    known <- DBI::dbGetQuery(con, "SELECT name FROM code_contexts")$name
    for (i in seq_len(nrow(declared))) {
      named   <- strsplit(declared$code_context[[i]], "[[:space:]]+")[[1L]]
      missing <- setdiff(named[nzchar(named)], known)
      if (length(missing) > 0L) {
        stop("File-context rule '", declared$name[[i]], "' names code contexts ",
             "that do not exist: ", paste(missing, collapse = ", "))
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
# (written as .txt); code-context and pattern examples are R code (.R); match
# examples are lines of shell or make, which are neither, and are written as
# .txt too.
build_fixtures <- function(
  rules_root   = file.path("inst", "rules"),
  fixtures_dir = file.path("tests", "testthat", "fixtures")
) {
  # A code-context rule's examples are R code where it matches on an XPath, and
  # a help file where it matches on a segment label -- because what a segment
  # rule claims is not a shape in the R, it is where the R came from.
  classes <- list(
    file_contexts = list(reader = read_file_context_yaml,
                         ext = function(rule) "txt"),
    code_contexts = list(reader = read_code_context_yaml,
                         ext = function(rule)
                           if (identical(rule$kind, "segment")) "Rd" else "R"),
    patterns      = list(reader = read_pattern_yaml,
                         ext = function(rule) "R"),
    matches       = list(reader = read_match_yaml,
                         ext = function(rule) "txt")
  )

  for (cls in names(classes)) {
    src_dir <- file.path(rules_root, cls)
    if (!dir.exists(src_dir)) stop("Rules directory not found: ", src_dir)
    yaml_files <- list.files(src_dir, pattern = "\\.ya?ml$", full.names = TRUE)

    for (f in yaml_files) {
      rule     <- classes[[cls]]$reader(f)
      ext      <- classes[[cls]]$ext(rule)
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
