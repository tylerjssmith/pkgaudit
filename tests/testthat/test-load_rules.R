# load_rules() -----------------------------------------------------------------
test_that("load_rules() returns four rule data frames with expected columns", {
  rules <- load_rules()
  expect_named(rules, c("file_contexts", "code_contexts", "patterns", "phases"))

  expect_named(rules$file_contexts,
               c("name", "version", "type", "message", "path", "recursive", "pattern"))
  expect_named(rules$code_contexts,
               c("name", "version", "type", "message", "xpath"))
  expect_named(rules$patterns,
               c("name", "version", "type", "message", "attck", "xpath"))
  expect_named(rules$phases, c("context", "version", .phase_columns))

  expect_type(rules$file_contexts$recursive, "logical")
  expect_gt(nrow(rules$file_contexts), 0L)
  expect_gt(nrow(rules$code_contexts), 0L)
  expect_gt(nrow(rules$patterns), 0L)
})

test_that("load_rules() returns phases as logicals for every context", {
  rules <- load_rules()

  for (phase in .phase_columns) expect_type(rules$phases[[phase]], "logical")

  # Every context a finding can be attributed to has a row: each file- and
  # code-context rule, plus the computed contexts.
  expect_setequal(
    rules$phases$context,
    c(rules$file_contexts$name, rules$code_contexts$name, .sentinel_contexts)
  )

  # The computed contexts carry the phases established for them: top-level code
  # runs when the package is installed, built, or checked but not when it is
  # loaded; code in an ordinary function runs at no phase at all.
  top <- rules$phases[rules$phases$context == "Top-level", ]
  expect_true(top$at_install_src && top$at_build && top$at_check)
  expect_false(top$at_load)

  other <- rules$phases[rules$phases$context == "Other", ]
  expect_false(any(unlist(other[, .phase_columns])))
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
