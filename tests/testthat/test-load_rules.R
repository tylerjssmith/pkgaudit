# load_rules() -----------------------------------------------------------------
test_that("load_rules() returns three rule data frames with expected columns", {
  rules <- load_rules()
  expect_named(rules, c("file_contexts", "code_contexts", "patterns"))

  expect_named(rules$file_contexts,
               c("name", "version", "type", "message", "path", "recursive", "pattern"))
  expect_named(rules$code_contexts,
               c("name", "version", "type", "message", "xpath"))
  expect_named(rules$patterns,
               c("name", "version", "type", "message", "attck", "xpath"))

  expect_type(rules$file_contexts$recursive, "logical")
  expect_gt(nrow(rules$file_contexts), 0L)
  expect_gt(nrow(rules$code_contexts), 0L)
  expect_gt(nrow(rules$patterns), 0L)
})

test_that("load_rules() errors when the database is missing", {
  expect_error(load_rules(tempfile()), "Rules database not found")
  expect_error(load_rules(""),         "Rules database not found")
})

# rules_version() --------------------------------------------------------------
test_that("rules_version() returns the seeded version string", {
  v <- rules_version()
  expect_type(v, "character")
  expect_length(v, 1L)
  expect_equal(v, "0.1.0")
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
