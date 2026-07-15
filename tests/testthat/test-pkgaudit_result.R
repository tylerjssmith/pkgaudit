.stub_rule <- list(
  stub = list(
    xpath   = "//SYMBOL_FUNCTION_CALL[text() = 'system']",
    message = "stub",
    type    = "warning",
    attck   = "T0000"
  )
)


# print.pkgaudit_result() ------------------------------------------------------

test_that("print.pkgaudit_result() shows 'No findings.' when result is clean", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp), add = TRUE)
  writeLines("x <- 1", tmp)

  result <- audit_file(tmp, rules = .stub_rule)
  expect_output(print(result), "No findings\\.")
})

test_that("print.pkgaudit_result() shows finding count and file when findings exist", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp), add = TRUE)
  writeLines("system('id')", tmp)

  result <- audit_file(tmp, rules = .stub_rule)
  expect_output(print(result), "1 finding")
  expect_output(print(result), basename(tmp))
})

test_that("print.pkgaudit_result() shows error count when parse errors exist", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(")invalid", tmp)

  suppressMessages(result <- audit_file(tmp, rules = .stub_rule))
  expect_output(print(result), "1 file\\(s\\) could not be parsed")
  expect_output(print(result), basename(tmp))
})
