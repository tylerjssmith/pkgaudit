rules <- load_rules()

tree_from_text <- function(text) {
  f <- tempfile(fileext = ".R")
  writeLines(text, f)
  on.exit(unlink(f), add = TRUE)
  parse_script(f)$tree
}

# happy path -------------------------------------------------------------------
test_that("find_patterns() returns findings with the documented columns", {
  tree <- tree_from_text("system('id')")
  res  <- find_patterns(tree, rules$patterns, "R/zzz.R")
  expect_named(res$patterns,
               c("rule", "file_context", "line_number", "column_number",
                 "message", "attck"))
  expect_equal(nrow(res$patterns), 1L)
  expect_equal(res$patterns$rule, "system")
  expect_equal(res$patterns$file_context, "R/zzz.R")
  expect_equal(nrow(res$errors), 0L)
})

test_that("find_patterns() attaches matched nodes aligned to rows", {
  tree  <- tree_from_text(c("system('a')", "system('b')"))
  res   <- find_patterns(tree, rule_row(rules$patterns, "system"), "R/zzz.R")
  nodes <- attr(res$patterns, "nodes")
  expect_equal(nrow(res$patterns), 2L)
  expect_length(nodes, 2L)
  expect_true(all(vapply(nodes, inherits, logical(1L), "xml_node")))
})

test_that("find_patterns() returns empty (with nodes attr) when nothing matches", {
  tree <- tree_from_text("x <- 1")
  res  <- find_patterns(tree, rules$patterns, "R/zzz.R")
  expect_equal(nrow(res$patterns), 0L)
  expect_length(attr(res$patterns, "nodes"), 0L)
})

# tryCatch path ----------------------------------------------------------------
test_that("find_patterns() records an error for an invalid XPath", {
  tree <- tree_from_text("x <- 1")
  bad  <- rule_row(rules$patterns, "system")
  bad$xpath <- "//["

  res <- find_patterns(tree, bad, "R/zzz.R")
  expect_equal(nrow(res$patterns), 0L)
  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$stage, "find_patterns")
  expect_equal(res$errors$rule, "system")
})
