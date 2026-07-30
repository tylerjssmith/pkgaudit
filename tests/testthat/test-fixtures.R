# Every positive example fixture must be flagged by its rule, and no negative
# example fixture may be flagged by its rule. These tests are the ground truth
# that the shipped rules behave as their authors documented.

rules <- load_rules()

# --- Code-context fixtures ----------------------------------------------------
test_that("code-context rules match their positive fixtures and reject negatives", {
  base <- test_path("fixtures", "code_contexts")
  for (name in rules$code_contexts$name) {
    rule_dir <- file.path(base, name)
    expect_true(dir.exists(rule_dir), info = name)
    rule <- rule_row(rules$code_contexts, name)

    for (pos in list.files(rule_dir, pattern = "^positive_\\d+\\.R$", full.names = TRUE)) {
      tree <- tree_from_file(pos)
      res  <- find_code_contexts(tree, rule, basename(pos))
      expect_gt(nrow(res$code_contexts), 0L)
      expect_equal(nrow(res$errors), 0L)
      expect_equal(unique(res$code_contexts$rule), name, info = pos)
    }
    for (neg in list.files(rule_dir, pattern = "^negative_\\d+\\.R$", full.names = TRUE)) {
      tree <- tree_from_file(neg)
      res  <- find_code_contexts(tree, rule, basename(neg))
      expect_equal(nrow(res$code_contexts), 0L, info = neg)
    }
  }
})

# --- Pattern fixtures ---------------------------------------------------------
test_that("pattern rules match their positive fixtures and reject negatives", {
  base <- test_path("fixtures", "patterns")
  for (name in rules$patterns$name) {
    rule_dir <- file.path(base, name)
    expect_true(dir.exists(rule_dir), info = name)
    rule <- rule_row(rules$patterns, name)

    for (pos in list.files(rule_dir, pattern = "^positive_\\d+\\.R$", full.names = TRUE)) {
      tree <- tree_from_file(pos)
      res  <- find_patterns(tree, rule, basename(pos))
      expect_gt(nrow(res$patterns), 0L)
      expect_equal(nrow(res$errors), 0L)
      expect_equal(unique(res$patterns$rule), name, info = pos)
    }
    for (neg in list.files(rule_dir, pattern = "^negative_\\d+\\.R$", full.names = TRUE)) {
      tree <- tree_from_file(neg)
      res  <- find_patterns(tree, rule, basename(neg))
      expect_equal(nrow(res$patterns), 0L, info = neg)
    }
  }
})

# --- File-context fixtures ----------------------------------------------------
# File-context examples are path strings. For each rule, materialize all of its
# positive and negative example paths in one throwaway package, then confirm the
# rule finds exactly the positives.
test_that("file-context rules find their positive paths and reject negatives", {
  base <- test_path("fixtures", "file_contexts")
  for (name in rules$file_contexts$name) {
    rule_dir <- file.path(base, name)
    expect_true(dir.exists(rule_dir), info = name)
    rule <- rule_row(rules$file_contexts, name)

    read_paths <- function(kind) {
      files <- list.files(rule_dir, pattern = sprintf("^%s_\\d+\\.txt$", kind),
                          full.names = TRUE)
      vapply(files, function(f) trimws(readLines(f, warn = FALSE)[[1L]]),
             character(1L), USE.NAMES = FALSE)
    }
    positives <- read_paths("positive")
    negatives <- read_paths("negative")

    pkg <- tempfile("pkg")
    dir.create(pkg)
    on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
    for (rel in c(positives, negatives)) {
      target <- file.path(pkg, rel)
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      file.create(target)
    }

    res   <- find_file_contexts(pkg, rule)
    found <- sort(res$file_contexts$file_context)
    expect_equal(nrow(res$errors), 0L)
    expect_equal(found, sort(positives), info = name)
    expect_false(any(negatives %in% found), info = name)
  }
})
