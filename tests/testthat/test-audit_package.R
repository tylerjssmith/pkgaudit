# Helper: create a minimal package directory structure with a single R file
# in R/, simulating a real package root for audit_package().
make_test_pkg <- function(r_content, dir_name) {
  pkg_dir <- file.path(tempdir(), dir_name)
  r_dir   <- file.path(pkg_dir, "R")
  dir.create(r_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines("Package: testpkg\nVersion: 0.1.0", file.path(pkg_dir, "DESCRIPTION"))
  writeLines(r_content, file.path(r_dir, "zzz.R"))
  pkg_dir
}


# audit_package(): error paths -------------------------------------------------
test_that("audit_package() stops if no DESCRIPTION file found", {
  tmp <- file.path(tempdir(), "notapkg")
  dir.create(tmp, showWarnings = FALSE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  expect_error(
    audit_package(tmp, rules = load_rules()),
    "No DESCRIPTION file found"
  )
})


# audit_package(): happy path --------------------------------------------------
# For each rule in the database, verify that the positive fixture produces a
# finding and the negative fixture does not. Fixture files are generated from
# the YAML rule files by inst/scripts/build_rules.R.
test_that("each rule detects positive cases and ignores negative cases", {
  rules    <- load_rules()
  fix_root <- testthat::test_path("fixtures", "rules")

  for (rule_name in names(rules)) {
    rule_dir  <- file.path(fix_root, rule_name)
    positives <- sort(list.files(rule_dir, pattern = "^positive_[0-9]+\\.R$", full.names = TRUE))
    negatives <- sort(list.files(rule_dir, pattern = "^negative_[0-9]+\\.R$", full.names = TRUE))

    # At least one fixture of each kind must exist for every rule in the database
    expect_true(
      length(positives) > 0L,
      label = paste0(rule_name, ": at least one positive fixture exists")
    )
    expect_true(
      length(negatives) > 0L,
      label = paste0(rule_name, ": at least one negative fixture exists")
    )

    if (length(positives) == 0L || length(negatives) == 0L) next

    single_rule <- rules[rule_name]

    for (j in seq_along(positives)) {
      pkg_pos <- make_test_pkg(
        readLines(positives[[j]]),
        paste0(rule_name, "_pos_", j)
      )
      on.exit(unlink(pkg_pos, recursive = TRUE), add = TRUE)

      pos_result <- audit_package(pkg_pos, rules = single_rule)
      expect_s3_class(pos_result, "pkgaudit_result")
      expect_true(
        nrow(pos_result$findings) > 0L,
        label = paste0(rule_name, "/positive_", j, ": positive case detected")
      )
    }

    for (j in seq_along(negatives)) {
      pkg_neg <- make_test_pkg(
        readLines(negatives[[j]]),
        paste0(rule_name, "_neg_", j)
      )
      on.exit(unlink(pkg_neg, recursive = TRUE), add = TRUE)

      expect_message(
        neg_result <- audit_package(pkg_neg, rules = single_rule),
        "No security findings"
      )
      expect_s3_class(neg_result, "pkgaudit_result")
      expect_equal(
        nrow(neg_result$findings), 0L,
        label = paste0(rule_name, "/negative_", j, ": negative case not flagged")
      )
      expect_equal(
        length(neg_result$errors), 0L,
        label = paste0(rule_name, "/negative_", j, ": negative case has no parse errors")
      )
    }
  }
})


# audit_package(): scan scope --------------------------------------------------

test_that("audit_package() detects findings in R/unix/", {
  pkg_dir <- file.path(tempdir(), "testpkg_unix")
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)
  dir.create(file.path(pkg_dir, "R", "unix"), recursive = TRUE, showWarnings = FALSE)
  writeLines("Package: testpkg\nVersion: 0.1.0", file.path(pkg_dir, "DESCRIPTION"))
  writeLines(".onLoad <- function(l, p) system('id')", file.path(pkg_dir, "R", "unix", "zzz.R"))

  result <- audit_package(pkg_dir, rules = load_rules())
  expect_gt(nrow(result$findings), 0L)
  expect_true(all(startsWith(result$findings$file, "R/unix/")))
})

test_that("audit_package() detects findings in R/windows/", {
  pkg_dir <- file.path(tempdir(), "testpkg_windows")
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)
  dir.create(file.path(pkg_dir, "R", "windows"), recursive = TRUE, showWarnings = FALSE)
  writeLines("Package: testpkg\nVersion: 0.1.0", file.path(pkg_dir, "DESCRIPTION"))
  writeLines(".onLoad <- function(l, p) system('id')", file.path(pkg_dir, "R", "windows", "zzz.R"))

  result <- audit_package(pkg_dir, rules = load_rules())
  expect_gt(nrow(result$findings), 0L)
  expect_true(all(startsWith(result$findings$file, "R/windows/")))
})

test_that("audit_package() detects findings in src/install.libs.R", {
  pkg_dir <- file.path(tempdir(), "testpkg_src")
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)
  dir.create(file.path(pkg_dir, "R"),   recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(pkg_dir, "src"), recursive = TRUE, showWarnings = FALSE)
  writeLines("Package: testpkg\nVersion: 0.1.0", file.path(pkg_dir, "DESCRIPTION"))
  writeLines(".onLoad <- function(l, p) system('id')", file.path(pkg_dir, "src", "install.libs.R"))

  result <- audit_package(pkg_dir, rules = load_rules())
  expect_gt(nrow(result$findings), 0L)
  expect_true(any(result$findings$file == "src/install.libs.R"))
})

test_that("audit_package() returns relative paths in $errors", {
  pkg_dir <- file.path(tempdir(), "testpkg_errs")
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)
  dir.create(file.path(pkg_dir, "R"), recursive = TRUE, showWarnings = FALSE)
  writeLines("Package: testpkg\nVersion: 0.1.0", file.path(pkg_dir, "DESCRIPTION"))
  writeLines(")invalid R syntax", file.path(pkg_dir, "R", "bad.R"))

  result <- audit_package(pkg_dir, rules = load_rules())
  expect_gt(length(result$errors), 0L)
  expect_false(any(startsWith(names(result$errors), tempdir())))
  expect_true(all(startsWith(names(result$errors), "R/")))
})
