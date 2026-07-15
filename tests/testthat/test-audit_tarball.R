# Helper: build a minimal .tar.gz tarball containing one R file.
# Returns the path to the tarball; the caller is responsible for unlink().
make_test_tarball <- function(r_content, pkg_name = "testpkg") {
  base_dir <- tempfile()
  pkg_dir  <- file.path(base_dir, pkg_name)
  r_dir    <- file.path(pkg_dir, "R")
  dir.create(r_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(
    c("Package: testpkg", "Version: 0.1.0"),
    file.path(pkg_dir, "DESCRIPTION")
  )
  writeLines(r_content, file.path(r_dir, "zzz.R"))

  tarball <- tempfile(fileext = ".tar.gz")
  old_wd  <- setwd(base_dir)
  on.exit(setwd(old_wd), add = TRUE)
  utils::tar(tarball, files = pkg_name, compression = "gzip", tar = "internal")
  unlink(base_dir, recursive = TRUE)
  tarball
}


# audit_tarball(): error paths -------------------------------------------------

test_that("audit_tarball() stops if path does not exist", {
  expect_error(
    audit_tarball("/no/such/file.tar.gz", rules = load_rules()),
    "file.exists"
  )
})

test_that("audit_tarball() stops if rules is empty", {
  tb <- make_test_tarball(".onLoad <- function(l, p) invisible(NULL)")
  on.exit(unlink(tb), add = TRUE)

  expect_error(
    audit_tarball(tb, rules = list()),
    "length\\(rules\\)"
  )
})


# audit_tarball(): happy path --------------------------------------------------

test_that("audit_tarball() returns a pkgaudit_result", {
  tb <- make_test_tarball("my_fn <- function(x) x + 1")
  on.exit(unlink(tb), add = TRUE)

  result <- audit_tarball(tb, rules = load_rules())
  expect_s3_class(result, "pkgaudit_result")
})

test_that("audit_tarball() returns no findings for a clean package", {
  tb <- make_test_tarball("my_fn <- function(x) x + 1")
  on.exit(unlink(tb), add = TRUE)

  result <- audit_tarball(tb, rules = load_rules())
  expect_equal(nrow(result$findings), 0L)
  expect_equal(length(result$errors), 0L)
})

test_that("audit_tarball() detects a finding in a malicious hook", {
  tb <- make_test_tarball(
    ".onLoad <- function(libname, pkgname) { system('id') }"
  )
  on.exit(unlink(tb), add = TRUE)

  result <- audit_tarball(tb, rules = load_rules())
  expect_gt(nrow(result$findings), 0L)
  expect_true("onload_calls_system_rule" %in% result$findings$rule)
})

test_that("audit_tarball() returns relative file paths", {
  tb <- make_test_tarball(
    ".onLoad <- function(libname, pkgname) { system('id') }"
  )
  on.exit(unlink(tb), add = TRUE)

  result <- audit_tarball(tb, rules = load_rules())
  expect_false(any(startsWith(result$findings$file, tempdir())))
  expect_true(all(startsWith(result$findings$file, "R/")))
})
