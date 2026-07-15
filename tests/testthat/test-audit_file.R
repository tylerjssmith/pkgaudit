# audit_file(): happy path -----------------------------------------------------
test_that("audit_file() returns findings with correct columns when a rule matches", {
  stub_rule <- list(
    stub = list(
      xpath   = "//SYMBOL_FUNCTION_CALL[text() = 'system']",
      message = "stub message",
      type    = "warning",
      attck   = "T0000"
    )
  )

  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp), add = TRUE)
  writeLines("system('id')", tmp)

  result <- audit_file(tmp, rules = stub_rule)
  expect_s3_class(result, "pkgaudit_result")
  expect_equal(nrow(result$findings), 1L)
  expect_named(result$findings, c("file", "line", "column", "rule", "message", "type", "attck"))
  expect_equal(result$findings$rule[[1L]], "stub")
  expect_length(result$errors, 0L)
})


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


test_that("audit_file() captures XPath errors in $errors", {
  bad_rule <- list(
    bad = list(
      xpath   = "//[",
      message = "stub",
      type    = "warning",
      attck   = "T0000"
    )
  )

  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp), add = TRUE)
  writeLines("x <- 1", tmp)

  expect_message(
    result <- audit_file(tmp, rules = bad_rule),
    "XPath error"
  )
  expect_equal(nrow(result$findings), 0L)
  expect_length(result$errors, 1L)
  expect_true(grepl("[rule: bad]", names(result$errors), fixed = TRUE))
})
