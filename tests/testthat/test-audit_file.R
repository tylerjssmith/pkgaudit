# audit_file(): error paths ----------------------------------------------------
test_that("audit_file() returns a pkgaudit_result with errors for a parse error", {
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
  expect_s3_class(result, "pkgaudit_result")
  expect_equal(nrow(result$findings), 0L)
  expect_length(result$errors, 1L)
  expect_named(result$errors, tmp)
})
