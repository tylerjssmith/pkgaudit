# Shared stub rule for audit_dir() tests
.stub_rule <- list(
  stub = list(
    xpath   = "//SYMBOL_FUNCTION_CALL[text() = 'system']",
    message = "stub",
    type    = "warning",
    attck   = "T0000"
  )
)


# audit_dir(): recurse ----------------------------------------------------------
test_that("audit_dir() with recurse = FALSE finds only top-level files", {
  tmp <- file.path(tempdir(), "test_recurse_false")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  dir.create(file.path(tmp, "sub"), recursive = TRUE, showWarnings = FALSE)
  writeLines("x <- 1",        file.path(tmp, "clean.R"))
  writeLines("system('id')",  file.path(tmp, "sub", "bad.R"))

  result <- audit_dir(tmp, rules = .stub_rule, recurse = FALSE)
  expect_equal(nrow(result$findings), 0L)
})


# audit_dir(): exclude_dirs ----------------------------------------------------
test_that("audit_dir() exclude_dirs skips files in matching subdirectories", {
  tmp <- file.path(tempdir(), "test_exclude_dirs")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  dir.create(file.path(tmp, "examples"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(tmp, "R"),        recursive = TRUE, showWarnings = FALSE)
  writeLines("system('id')", file.path(tmp, "examples", "bad.R"))
  writeLines("x <- 1",       file.path(tmp, "R", "clean.R"))

  result <- audit_dir(tmp, rules = .stub_rule, recurse = TRUE, exclude_dirs = "examples")
  expect_equal(nrow(result$findings), 0L)
})


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
