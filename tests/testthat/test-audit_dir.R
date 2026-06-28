# audit_dir(): error paths -----------------------------------------------------
test_that("audit_dir() returns empty data frame when no R files found", {
  # A minimal rule is needed to call audit_dir(); the rule content is
  # irrelevant since the no-files path returns before any XPath evaluation.
  stub_rule <- list(
    stub = list(
      xpath   = "//expr",
      message = "stub",
      type    = "warning",
      attck   = "T0000"
    )
  )

  empty <- file.path(tempdir(), "empty_test_dir")
  dir.create(empty, showWarnings = FALSE)
  on.exit(unlink(empty, recursive = TRUE), add = TRUE)

  expect_message(
    result <- audit_dir(empty, rules = stub_rule),
    "No R source files found"
  )
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0L)
})
