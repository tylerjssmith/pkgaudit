rules <- load_rules()

tree_from_text <- function(text) {
  f <- tempfile(fileext = ".R")
  writeLines(text, f)
  on.exit(unlink(f), add = TRUE)
  parse_code(read_code(f)$lines)$tree
}

# Run find_patterns then determine_code_contexts on one script; return the
# augmented patterns data frame.
contexts_for <- function(text) {
  tree <- tree_from_text(text)
  fp   <- find_patterns(tree, rules$patterns, "R/zzz.R")
  determine_code_contexts(tree, fp$patterns, rules)
}

test_that("a pattern in a named hook is labeled with that context", {
  pat <- contexts_for(".onLoad <- function(a, b) system('x')")
  expect_equal(pat$rule, "system")
  expect_equal(pat$code_context, "onLoad_base")
})

test_that("a top-level pattern is labeled Top-level", {
  pat <- contexts_for("system('x')")
  expect_equal(pat$code_context, "R")
})

test_that("a pattern in an ordinary function is labeled Other", {
  pat <- contexts_for("f <- function() system('x')")
  expect_equal(pat$code_context, "Other")
})

test_that("a pattern in a backslash-lambda function is labeled Other", {
  pat <- contexts_for("f <- \\(a) system('x')")
  expect_equal(pat$code_context, "Other")
})

test_that("the most-specific (innermost) named context wins", {
  # system() sits inside .onAttach, which is nested inside .onLoad.
  pat <- contexts_for(c(
    ".onLoad <- function(a, b) {",
    "  .onAttach <- function(c, d) {",
    "    system('x')",
    "  }",
    "}"
  ))
  expect_equal(pat$code_context, "onAttach_base")
})

test_that("rlang on_load inside .onLoad wins over the .onLoad hook", {
  pat <- contexts_for(c(
    ".onLoad <- function(a, b) {",
    "  on_load(system('x'))",
    "}"
  ))
  expect_equal(pat$code_context, "on_load_rlang")
})

test_that("determine_code_contexts() returns unchanged frame for zero patterns", {
  tree <- tree_from_text("x <- 1")
  fp   <- find_patterns(tree, rules$patterns, "R/zzz.R")
  out  <- determine_code_contexts(tree, fp$patterns, rules)
  expect_equal(nrow(out), 0L)
  expect_true("code_context" %in% names(out))
})

test_that("determine_code_contexts() falls back cleanly when no code contexts exist", {
  # Empty code-context rules -> only the function-ancestor test is used.
  no_cc <- rules
  no_cc$code_contexts <- rules$code_contexts[0, , drop = FALSE]
  tree  <- tree_from_text(c("system('top')", "g <- function() system('inner')"))
  fp    <- find_patterns(tree, rules$patterns, "R/zzz.R")
  out   <- determine_code_contexts(tree, fp$patterns, no_cc)
  expect_setequal(out$code_context, c("R", "Other"))
})
