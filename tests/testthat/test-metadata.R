rules <- load_rules()

# Build a source tarball named <pkg>_<version>.tar.gz; return its path.
build_tarball <- function(pkg_name, version, r_content = "invisible(NULL)") {
  base <- tempfile()
  pd   <- file.path(base, pkg_name)
  dir.create(file.path(pd, "R"), recursive = TRUE, showWarnings = FALSE)
  writeLines(c(paste("Package:", pkg_name), paste("Version:", version)),
             file.path(pd, "DESCRIPTION"))
  writeLines(r_content, file.path(pd, "R", "zzz.R"))
  out <- tempfile("tb"); dir.create(out)
  tb  <- file.path(out, sprintf("%s_%s.tar.gz", pkg_name, version))
  owd <- setwd(base); on.exit(setwd(owd), add = TRUE)
  utils::tar(tb, files = pkg_name, compression = "gzip", tar = "internal")
  tb
}

expected_meta_fields <- c("pkg_name", "pkg_version", "pkg_path",
  "pkg_is_tarball", "pkg_sha256", "pkgaudit_version",
  "pkgaudit_rules_version", "pkgaudit_rules_sha256", "scanned")

# Directory scan ---------------------------------------------------------------
test_that("audit_package() reads pkg_name/pkg_version from DESCRIPTION", {
  pkg <- tempfile("pkg"); dir.create(file.path(pkg, "R"), recursive = TRUE)
  writeLines(c("Package: mypkg", "Version: 1.2.3"),
             file.path(pkg, "DESCRIPTION"))
  writeLines("invisible(NULL)", file.path(pkg, "R", "zzz.R"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  m <- audit_package(pkg, rules)$metadata
  expect_named(m, expected_meta_fields)
  expect_equal(m$pkg_name, "mypkg")
  expect_equal(m$pkg_version, "1.2.3")
  expect_false(m$pkg_is_tarball)
  expect_equal(m$pkg_path, pkg)
  expect_match(m$pkg_sha256, "^[0-9a-f]{64}$")
  expect_match(m$scanned, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
  expect_false(is.na(m$pkgaudit_version))
  expect_equal(m$pkgaudit_rules_version, rules_version())
})

test_that("audit_package() directory hash matches hash_manifest()", {
  pkg <- tempfile("pkg"); dir.create(file.path(pkg, "R"), recursive = TRUE)
  writeLines(c("Package: mypkg", "Version: 1.0"), file.path(pkg, "DESCRIPTION"))
  writeLines("invisible(NULL)", file.path(pkg, "R", "zzz.R"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  m <- audit_package(pkg, rules)$metadata
  expect_equal(m$pkg_sha256, hash_manifest(pkg)$hash)
})

test_that("audit_package() sets NA names (no error) when DESCRIPTION is missing", {
  pkg <- tempfile("pkg"); dir.create(file.path(pkg, "R"), recursive = TRUE)
  writeLines("invisible(NULL)", file.path(pkg, "R", "zzz.R"))  # no DESCRIPTION
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_s3_class(res, "pkgaudit")
  expect_true(is.na(res$metadata$pkg_name))
  expect_true(is.na(res$metadata$pkg_version))
})

test_that("audit_package() sets NA names (no error) when DESCRIPTION is malformed", {
  pkg <- tempfile("pkg"); dir.create(file.path(pkg, "R"), recursive = TRUE)
  writeLines("this is not a valid DCF file", file.path(pkg, "DESCRIPTION"))
  writeLines("invisible(NULL)", file.path(pkg, "R", "zzz.R"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_s3_class(res, "pkgaudit")
  expect_true(is.na(res$metadata$pkg_name))
  expect_true(is.na(res$metadata$pkg_version))
})

test_that("audit_package() sets NA version when DESCRIPTION lacks the field", {
  pkg <- tempfile("pkg"); dir.create(file.path(pkg, "R"), recursive = TRUE)
  writeLines("Package: onlyname", file.path(pkg, "DESCRIPTION"))  # no Version
  writeLines("invisible(NULL)", file.path(pkg, "R", "zzz.R"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  m <- audit_package(pkg, rules)$metadata
  expect_equal(m$pkg_name, "onlyname")
  expect_true(is.na(m$pkg_version))
})

# Tarball scan -----------------------------------------------------------------
test_that("audit_tarball() sets tarball provenance in metadata", {
  tb <- build_tarball("tarpkg", "4.5.6")
  on.exit(unlink(dirname(tb), recursive = TRUE), add = TRUE)

  m <- audit_tarball(tb, rules)$metadata
  expect_true(m$pkg_is_tarball)
  expect_equal(m$pkg_path, tb)
  expect_equal(m$pkg_name, "tarpkg")
  expect_equal(m$pkg_version, "4.5.6")
  # pkg_sha256 is the hash of the tarball as received, before extraction.
  expect_equal(m$pkg_sha256, digest::digest(tb, algo = "sha256", file = TRUE))
})
