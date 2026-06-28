# audit_file(): error paths ----------------------------------------------------
test_that("audit_file() returns NULL for a parse error", {
  # A minimal rule is needed to call audit_file(); the rule content is
  # irrelevant since a parse error is caught before XPath evaluation.
  stub_rule <- list(
    stub = list(
      xpath   = "//expr",
      message = "stub",
      type    = "warning",
      attck   = "T0000"
    )
  )

  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp), add = TRUE)
  writeLines("this is not { valid R code )(", tmp)

  expect_message(
    result <- audit_file(tmp, rules = stub_rule),
    "Parse error"
  )
  expect_null(result)
})
