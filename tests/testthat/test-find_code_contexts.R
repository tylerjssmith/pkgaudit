rules <- load_rules()

tree_from_text <- function(text) {
  f <- tempfile(fileext = ".R")
  writeLines(text, f)
  on.exit(unlink(f), add = TRUE)
  parse_code(read_code(f)$lines)$tree
}

# happy path -------------------------------------------------------------------
test_that("find_code_contexts() returns a row per matched context", {
  tree <- tree_from_text(c(
    ".onLoad <- function(libname, pkgname) invisible(NULL)",
    ".onAttach <- function(libname, pkgname) invisible(NULL)"
  ))
  res <- find_code_contexts(tree, rules$code_contexts, "R/zzz.R")
  expect_named(res$code_contexts,
               c("rule", "file_context", "line_number",
                 "column_number", "message"))
  expect_setequal(res$code_contexts$rule, c("onLoad_base", "onAttach_base"))
  expect_true(all(res$code_contexts$file_context == "R/zzz.R"))
  expect_equal(nrow(res$errors), 0L)
})

test_that("find_code_contexts() returns all matches for a repeated context", {
  # Two definitions of the same hook -> two rows for that context.
  tree <- tree_from_text(c(
    ".onLoad <- function(a, b) invisible(NULL)",
    ".onLoad <- function(a, b) invisible(NULL)"
  ))
  res <- find_code_contexts(tree, rule_row(rules$code_contexts, "onLoad_base"), "R/zzz.R")
  expect_equal(nrow(res$code_contexts), 2L)
})

test_that("find_code_contexts() returns empty when no context matches", {
  tree <- tree_from_text("f <- function() invisible(NULL)")
  res  <- find_code_contexts(tree, rules$code_contexts, "R/zzz.R")
  expect_equal(nrow(res$code_contexts), 0L)
  expect_equal(nrow(res$errors), 0L)
})

# tryCatch path ----------------------------------------------------------------
test_that("find_code_contexts() records an error for an invalid XPath", {
  tree <- tree_from_text("x <- 1")
  bad  <- rule_row(rules$code_contexts, "onLoad_base")
  bad$xpath <- "//["   # malformed XPath

  res <- find_code_contexts(tree, bad, "R/zzz.R")
  expect_equal(nrow(res$code_contexts), 0L)
  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$step, "find_code_contexts")
  expect_equal(res$errors$rule, "onLoad_base")
  expect_equal(res$errors$file_context, "R/zzz.R")
})

test_that("find_code_contexts() with no rules returns an empty frame of the right shape", {
  tree <- tree_from_text(".onLoad <- function(...) NULL")

  res <- find_code_contexts(tree, NULL, "R/zzz.R")
  expect_equal(names(res$code_contexts),
               names(.empty_code_contexts(with_phases = FALSE)))
  expect_equal(nrow(res$code_contexts), 0L)
  expect_equal(nrow(res$errors), 0L)
})
