# audit_dir(): error paths -----------------------------------------------------
test_that("audit_dir() returns a pkgaudit_result with no findings when no R files found", {
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
  expect_s3_class(result, "pkgaudit_result")
  expect_equal(nrow(result$findings), 0L)
  expect_length(result$errors, 0L)
})
