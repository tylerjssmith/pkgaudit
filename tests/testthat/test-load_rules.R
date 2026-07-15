# load_rules() -----------------------------------------------------------------
test_that("load_rules() stops with an informative message for a missing database", {
  expect_error(load_rules("nonexistent.db"), "Rules database not found")
  expect_error(load_rules(""),               "Rules database not found")
})


test_that("load_rules() returns a named list with well-formed rule objects", {
  rules <- load_rules()

  expect_type(rules, "list")
  expect_true(length(rules) > 0L)

  # All top-level elements must be named
  expect_true(!is.null(names(rules)))
  expect_true(all(nchar(names(rules)) > 0L))

  # Each top-level element must be a list with the required named fields
  required_fields <- c("xpath", "message", "type", "attck")
  for (rule_name in names(rules)) {
    rule <- rules[[rule_name]]
    expect_type(rule, "list")
    expect_true(
      all(required_fields %in% names(rule)),
      label = paste0("rule '", rule_name, "' has all required fields")
    )
  }
})


# hook_defined_rule ------------------------------------------------------------
test_that("hook_defined_rule has type 'message', not 'warning'", {
  rules <- load_rules()
  expect_true("hook_defined_rule" %in% names(rules))
  expect_equal(rules[["hook_defined_rule"]]$type, "message")
})


# rules_version() --------------------------------------------------------------
test_that("rules_version() returns a version string", {
  v <- rules_version()
  expect_type(v, "character")
  expect_length(v, 1L)
  expect_match(v, "^[0-9]+\\.[0-9]+\\.[0-9]+$")
})
