# load_rules() -----------------------------------------------------------------
test_that("load_rules() returns five rule data frames with expected columns", {
  rules <- load_rules()
  expect_named(rules, c("file_contexts", "code_contexts", "patterns", "matches",
                        "phases"))

  expect_named(rules$file_contexts,
               c("name", "version", "type", "message", "path", "recursive",
                 "report", "filename", "code_context", "assume_called"))
  expect_type(rules$file_contexts$assume_called, "logical")
  expect_type(rules$file_contexts$report, "logical")
  # A file context declares a `type`, the format of the file, which selects how
  # it is read. Every other class declares a `language`, the language of the code
  # it is evaluated against -- a separate axis, since one file can yield code in
  # more than one language.
  expect_named(rules$code_contexts,
               c("name", "version", "language", "message", "kind", "xpath",
                 "segment"))
  expect_named(rules$patterns,
               c("name", "version", "language", "message", "attck",
                 "functions", "xpath"))
  expect_named(rules$matches,
               c("name", "version", "language", "message", "attck", "regex"))
  expect_named(rules$phases, c("context", "version", .phase_columns))

  expect_type(rules$file_contexts$recursive, "logical")
  expect_gt(nrow(rules$file_contexts), 0L)
  expect_gt(nrow(rules$code_contexts), 0L)
  expect_gt(nrow(rules$patterns), 0L)
  expect_gt(nrow(rules$matches), 0L)
})

test_that("load_rules() returns regex rules that compile under PCRE", {
  rules <- load_rules()
  for (i in seq_len(nrow(rules$matches))) {
    expect_no_error(
      regexpr(rules$matches$regex[[i]], "x", perl = TRUE, useBytes = FALSE)
    )
  }
})

test_that("load_rules() returns phases as logicals for every context", {
  rules <- load_rules()

  for (phase in .phase_columns) expect_type(rules$phases[[phase]], "logical")

  # One row per rule, and only per rule. The computed contexts have none: they
  # take the phases of the file context they sit in, or an override.
  expect_setequal(
    rules$phases$context,
    c(rules$file_contexts$name, rules$code_contexts$name)
  )
  expect_false(any(.computed_contexts %in% rules$phases$context))

  # R/ carries the phases established for it: top-level code runs when the
  # package is installed, built or checked, but not when it is loaded.
  top <- rules$phases[rules$phases$context == "R_scripts", ]
  expect_true(top$at_install_src && top$at_build && top$at_check)
  expect_false(top$at_load)

  # And R/ is where a function body is reported as running at no phase, which
  # the rule says rather than in_function meaning that everywhere.
  expect_false(rules$file_contexts$assume_called[
    rules$file_contexts$name == "R_scripts"])
})

test_that("only the rules for R/ withhold the assumption that functions run", {
  rules <- load_rules()
  fc     <- rules$file_contexts
  expect_true(all(grepl("^R_scripts", fc$name[which(!fc$assume_called)])))
  # Set exactly where code contexts can arise, and nowhere else: a shell script
  # has no function bodies to decide about.
  expect_equal(is.na(fc$assume_called), is.na(fc$code_context))
})

test_that("every code context a file-context rule names is a rule that exists", {
  rules <- load_rules()
  named <- unlist(strsplit(stats::na.omit(rules$file_contexts$code_context),
                           "[[:space:]]+"))
  named <- setdiff(unique(named[nzchar(named)]), "computed")
  expect_equal(setdiff(named, rules$code_contexts$name), character(0))
  # And the hooks reach only R/, which is what replaced the namespace_source
  # flag. The probe package measures that a .onLoad elsewhere never fires.
  hooks <- rules$code_contexts$name[rules$code_contexts$kind == "xpath"]
  carriers <- rules$file_contexts$name[
    vapply(rules$file_contexts$code_context, function(spec) {
      any(hooks %in% strsplit(if (is.na(spec)) "" else spec, "[[:space:]]+")[[1L]])
    }, logical(1L))]
  expect_true(all(grepl("^R_scripts", carriers)))
})

test_that("load_rules() refuses a database that decides assume_called nowhere it applies", {
  db <- tempfile(fileext = ".db")
  file.copy(pkgaudit:::.db_path(), db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  # R/ has code contexts, so leaving the reading undecided there is a gap.
  DBI::dbExecute(con, "UPDATE file_contexts SET assume_called = NULL
                        WHERE name = 'R_scripts'")
  DBI::dbDisconnect(con)
  writeLines(digest::digest(db, algo = "sha256", file = TRUE),
             paste0(db, ".sha256"))
  on.exit(unlink(c(db, paste0(db, ".sha256"))), add = TRUE)

  expect_error(load_rules(db), "R_scripts")
})

test_that("load_rules() refuses a database that decides assume_called where it cannot apply", {
  db <- tempfile(fileext = ".db")
  file.copy(pkgaudit:::.db_path(), db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  # configure is a shell script: it has no function bodies to decide about.
  DBI::dbExecute(con, "UPDATE file_contexts SET assume_called = 1
                        WHERE name = 'configure'")
  DBI::dbDisconnect(con)
  writeLines(digest::digest(db, algo = "sha256", file = TRUE),
             paste0(db, ".sha256"))
  on.exit(unlink(c(db, paste0(db, ".sha256"))), add = TRUE)

  expect_error(load_rules(db), "configure")
})

test_that("load_rules() refuses a database missing phases for a context", {
  db <- tempfile(fileext = ".db")
  file.copy(pkgaudit:::.db_path(), db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con, "DELETE FROM phases WHERE context = 'onLoad_base'")
  DBI::dbDisconnect(con)
  writeLines(digest::digest(db, algo = "sha256", file = TRUE),
             paste0(db, ".sha256"))
  on.exit(unlink(c(db, paste0(db, ".sha256"))), add = TRUE)

  expect_error(load_rules(db), "missing phases for: onLoad_base")
})

test_that("load_rules() errors when the database is missing", {
  expect_error(load_rules(tempfile()), "Rules database not found")
  expect_error(load_rules(""),         "Rules database not found")
})

# rules_version() --------------------------------------------------------------
test_that("rules_version() returns the newest seeded version string", {
  v <- rules_version()
  expect_type(v, "character")
  expect_length(v, 1L)
  expect_match(v, "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  # The reported version must be at least as new as every rule in the database,
  # so a bumped rule can never ship under a stale version.
  declared <- unlist(lapply(load_rules(), `[[`, "version"), use.names = FALSE)
  expect_true(all(package_version(declared) <= package_version(v)))
})

# .verify_db() -----------------------------------------------------------------
test_that("load_rules() refuses a database with a missing hash sidecar", {
  db <- tempfile(fileext = ".db")
  file.copy(.db_path(), db)
  on.exit(unlink(db), add = TRUE)
  # No sidecar written next to the copy.
  expect_error(load_rules(db), "hash sidecar not found")
})

test_that("load_rules() refuses a database with an empty hash sidecar", {
  db <- tempfile(fileext = ".db")
  file.copy(.db_path(), db)
  writeLines(character(0L), paste0(db, ".sha256"))
  on.exit(unlink(c(db, paste0(db, ".sha256"))), add = TRUE)

  expect_error(load_rules(db), "hash sidecar is empty")
})

test_that("load_rules() refuses a tampered database (hash mismatch)", {
  db <- tempfile(fileext = ".db")
  file.copy(.db_path(), db)
  file.copy(paste0(.db_path(), ".sha256"), paste0(db, ".sha256"))
  on.exit(unlink(c(db, paste0(db, ".sha256"))), add = TRUE)

  # Mutate the copied database so its content no longer matches the sidecar.
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con, "UPDATE patterns SET message = 'tampered'")
  DBI::dbDisconnect(con)

  expect_error(load_rules(db), "failed SHA-256 verification")
})

test_that("load_rules() records the database it read as provenance", {
  rules <- load_rules()
  prov  <- attr(rules, "provenance")

  expect_named(prov, c("db_path", "version", "sha256"))
  expect_equal(prov$db_path, system.file("db", "rules.db", package = "pkgaudit"))
  expect_equal(prov$version, rules_version())
  expect_equal(prov$sha256,
               digest::digest(prov$db_path, algo = "sha256", file = TRUE))
})

test_that(".verify_db() returns the hash it computed from the database", {
  db <- system.file("db", "rules.db", package = "pkgaudit")
  expect_equal(.verify_db(db),
               digest::digest(db, algo = "sha256", file = TRUE))
})

test_that("provenance sha256 is measured from the database, not read back from the sidecar", {
  # The sidecar is written in upper case, which verification accepts because it
  # compares case-insensitively. The recorded hash is therefore distinguishable:
  # the lower-case digest means it was computed here, and the upper-case sidecar
  # text would mean it was re-read from a file an attacker could have rewritten
  # after verification passed.
  db <- tempfile(fileext = ".db")
  file.copy(system.file("db", "rules.db", package = "pkgaudit"), db)
  on.exit(unlink(c(db, paste0(db, ".sha256"))), add = TRUE)

  computed <- digest::digest(db, algo = "sha256", file = TRUE)
  writeLines(toupper(computed), paste0(db, ".sha256"))

  prov <- attr(load_rules(db), "provenance")
  expect_equal(prov$sha256, computed)
  expect_false(identical(prov$sha256, toupper(computed)))
})

# `report` is derivable, so it is asserted rather than left to convention ------
#
# report: TRUE means "this file runs on its own, and pkgaudit can only match its
# text -- read it yourself." Both halves are properties the rules already carry,
# so the field can be checked instead of trusted. Getting it wrong is how
# file_contexts stops being a short list of security-relevant files and becomes
# an inventory of the package.
test_that("report marks the files that run on their own and are only grepped", {
  fc <- load_rules()$file_contexts
  ph <- load_rules()$phases

  # (a) executes automatically during at least one lifecycle phase
  runs <- vapply(fc$name, function(n) {
    row <- ph[ph$context == n, .phase_columns, drop = FALSE]
    nrow(row) == 1L && any(unlist(row))
  }, logical(1), USE.NAMES = FALSE)

  # (b) matched as text rather than parsed. R, Rd and the literate formats are
  # parsed, so a finding in them carries syntax behind it; a shell or Make-like
  # file does not, and a match there cannot be told apart from one in a comment.
  grepped <- fc$type %in% c("shell", "make")

  # One deliberate exception. src/install.libs.R is R and therefore parsed, but
  # its mere presence replaces R's default handling of compiled artifacts -- a
  # structural change to installation that no pattern rule can detect, because
  # it follows from the file existing rather than from anything written in it.
  exceptions <- "src_install_libs_R"

  expect_equal(fc$report, (runs & grepped) | fc$name %in% exceptions)
})

test_that("every reporting rule is one a reviewer has to read themselves", {
  fc <- load_rules()$file_contexts
  # Named explicitly, so adding a rule that reports is a deliberate edit here
  # rather than something that slips in with a new file context.
  expect_setequal(fc$name[fc$report], c(
    "configure", "configure_ac", "configure_in", "configure_ucrt",
    "configure_win", "cleanup", "cleanup_ucrt", "cleanup_win",
    "src_makevars", "src_makevars_in", "src_makevars_ucrt", "src_makevars_win",
    "src_makefile", "src_makefile_ucrt", "src_makefile_win",
    "src_install_libs_R"
  ))
})

test_that("load_rules() refuses a database holding no rules", {
  db <- tempfile(fileext = ".db")
  file.copy(pkgaudit:::.db_path(), db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  for (table in c("file_contexts", "code_contexts", "patterns", "matches")) {
    DBI::dbExecute(con, paste("DELETE FROM", table))
  }
  DBI::dbDisconnect(con)
  writeLines(digest::digest(db, algo = "sha256", file = TRUE),
             paste0(db, ".sha256"))
  on.exit(unlink(c(db, paste0(db, ".sha256"))), add = TRUE)

  expect_error(load_rules(db), "No rules found in rules database")
})

test_that("load_rules() refuses a database recording no version", {
  db <- tempfile(fileext = ".db")
  file.copy(pkgaudit:::.db_path(), db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbExecute(con, "DELETE FROM rule_versions")
  DBI::dbDisconnect(con)
  writeLines(digest::digest(db, algo = "sha256", file = TRUE),
             paste0(db, ".sha256"))
  on.exit(unlink(c(db, paste0(db, ".sha256"))), add = TRUE)

  expect_error(load_rules(db),     "No version found in rules database")
  expect_error(rules_version(db),  "No version found in rules database")
})
