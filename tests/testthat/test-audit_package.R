# Helper: create a minimal package directory structure with a single R file
# in R/, simulating a real package root for audit_package().
make_test_pkg <- function(r_content, dir_name) {
  pkg_dir <- file.path(tempdir(), dir_name)
  r_dir   <- file.path(pkg_dir, "R")
  dir.create(r_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(r_content, file.path(r_dir, "zzz.R"))
  pkg_dir
}


# audit_package(): error paths -------------------------------------------------
test_that("audit_package() stops if no R/ directory found", {
  tmp <- file.path(tempdir(), "notapkg")
  dir.create(tmp, showWarnings = FALSE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  expect_error(
    audit_package(tmp, rules = load_rules()),
    "No R/ directory found"
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
    rule_dir <- file.path(fix_root, rule_name)
    positive <- file.path(rule_dir, "positive.R")
    negative <- file.path(rule_dir, "negative.R")

    # Fixtures must exist for every rule in the database
    expect_true(
      file.exists(positive),
      label = paste0(rule_name, ": positive.R fixture exists")
    )
    expect_true(
      file.exists(negative),
      label = paste0(rule_name, ": negative.R fixture exists")
    )

    if (!file.exists(positive) || !file.exists(negative)) next

    single_rule <- rules[rule_name]

    # Positive case: copy fixture into a minimal package and expect a finding
    pkg_pos <- make_test_pkg(
      readLines(positive),
      paste0(rule_name, "_pos")
    )
    on.exit(unlink(pkg_pos, recursive = TRUE), add = TRUE)

    pos_result <- audit_package(pkg_pos, rules = single_rule)
    expect_true(
      nrow(pos_result) > 0L,
      label = paste0(rule_name, ": positive case detected")
    )

    # Negative case: copy fixture into a minimal package and expect no finding
    pkg_neg <- make_test_pkg(
      readLines(negative),
      paste0(rule_name, "_neg")
    )
    on.exit(unlink(pkg_neg, recursive = TRUE), add = TRUE)

    expect_message(
      neg_result <- audit_package(pkg_neg, rules = single_rule),
      "No security findings"
    )
    expect_equal(
      nrow(neg_result), 0L,
      label = paste0(rule_name, ": negative case not flagged")
    )
  }
})
