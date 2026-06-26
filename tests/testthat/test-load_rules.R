# Full tests require the signed database. These tests cover input validation and
# error paths that can be exercised without a real database.

# load_rules() -----------------------------------------------------------------
test_that("load_rules() accepts valid tier argument", {
  expect_error(
    load_rules(tier = "invalid"),
    "'arg' should be one of"
  )
})


# verify_db() ------------------------------------------------------------------
test_that("verify_db() stops if database file not found", {
  expect_error(
    verify_db(
      db_path  = tempfile(),
      sig_path = tempfile(),
      pub_path = tempfile()
    ),
    "Rules database not found"
  )
})


test_that("verify_db() stops if signature file not found", {
  tmp_db <- tempfile()
  writeLines("not a real db", tmp_db)
  on.exit(unlink(tmp_db), add = TRUE)

  expect_error(
    verify_db(
      db_path  = tmp_db,
      sig_path = tempfile(),
      pub_path = tempfile()
    ),
    "signature not found"
  )
})


test_that("verify_db() stops if public key file not found", {
  tmp_db  <- tempfile()
  tmp_sig <- tempfile()
  writeLines("not a real db",  tmp_db)
  writeLines("not a real sig", tmp_sig)
  on.exit(unlink(c(tmp_db, tmp_sig)), add = TRUE)

  expect_error(
    verify_db(
      db_path  = tmp_db,
      sig_path = tmp_sig,
      pub_path = tempfile()
    ),
    "Public key not found"
  )
})
