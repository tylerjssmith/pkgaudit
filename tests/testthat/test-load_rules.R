# Full tests require the signed database. These tests cover input validation and
# error paths that can be exercised without a real database.

# load_rules() -----------------------------------------------------------------
test_that("load_rules() accepts valid tier argument", {
  expect_error(
    load_rules(tier = "invalid"),
    "'arg' should be one of"
  )
})
