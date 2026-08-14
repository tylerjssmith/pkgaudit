# Every positive example fixture must be flagged by its rule, and no negative
# example fixture may be flagged by its rule. These tests are the ground truth
# that the shipped rules behave as their authors documented.

rules <- load_rules()

# --- Code-context fixtures ----------------------------------------------------
# An xpath rule is matched against the parse tree, so its examples are R code.
test_that("code-context rules match their positive fixtures and reject negatives", {
  base <- test_path("fixtures", "code_contexts")
  xpath_rules <- rules$code_contexts$name[rules$code_contexts$kind == "xpath"]
  expect_gt(length(xpath_rules), 0L)

  for (name in xpath_rules) {
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

# A segment rule claims a whole segment rather than a shape in the R, so it has
# no XPath and its examples are help files. What it asserts is a round trip: the
# extractor stamps the label the rule declares, on a page that carries that kind
# of code and on no other.
#
# This is the only thing that ties a `kind: segment` rule to the extractor. The
# name a rule declares is checked against a fixed vocabulary when the database is
# built, but nothing there confirms that the extractor actually stamps it on the
# page the rule describes.
test_that("segment rules are stamped on their positive fixtures only", {
  base <- test_path("fixtures", "code_contexts")
  segment_rules <- rules$code_contexts[rules$code_contexts$kind == "segment", ]
  expect_gt(nrow(segment_rules), 0L)

  labels_of <- function(path) {
    res <- extract_segments(new_source(path, basename(path), "Rd"))
    expect_equal(nrow(res$errors), 0L, info = path)
    vapply(res$segments, `[[`, character(1L), "context")
  }

  for (i in seq_len(nrow(segment_rules))) {
    name     <- segment_rules$name[[i]]
    label    <- segment_rules$segment[[i]]
    rule_dir <- file.path(base, name)
    expect_true(dir.exists(rule_dir), info = name)

    for (pos in list.files(rule_dir, pattern = "^positive_\\d+\\.Rd$",
                           full.names = TRUE)) {
      expect_true(label %in% labels_of(pos), info = pos)
    }
    for (neg in list.files(rule_dir, pattern = "^negative_\\d+\\.Rd$",
                           full.names = TRUE)) {
      expect_false(label %in% labels_of(neg), info = neg)
    }
  }
})

# Every label a segment rule claims must be one an extractor can produce, or the
# rule would sit in the database never firing.
test_that("every segment rule names a label the extractors stamp", {
  segment_rules <- rules$code_contexts[rules$code_contexts$kind == "segment", ]
  expect_true(all(segment_rules$segment %in% .segment_labels))
  # And the reverse: a label no rule claims would yield findings with no phases.
  expect_setequal(segment_rules$segment, .segment_labels)
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

# --- Regex fixtures -----------------------------------------------------------
# Regex examples are lines of shell or make. find_matches() reads a file, so each
# fixture is scanned where it sits.
test_that("regex rules match their positive fixtures and reject negatives", {
  base <- test_path("fixtures", "matches")
  for (name in rules$matches$name) {
    rule_dir <- file.path(base, name)
    expect_true(dir.exists(rule_dir), info = name)
    rule <- rule_row(rules$matches, name)

    for (pos in list.files(rule_dir, pattern = "^positive_\\d+\\.txt$",
                           full.names = TRUE)) {
      res <- find_matches(read_code(pos)$lines, rule, basename(pos))
      expect_gt(nrow(res$matches), 0L)
      expect_equal(nrow(res$errors), 0L)
      expect_equal(unique(res$matches$rule), name, info = pos)
    }
    for (neg in list.files(rule_dir, pattern = "^negative_\\d+\\.txt$",
                           full.names = TRUE)) {
      res <- find_matches(read_code(neg)$lines, rule, basename(neg))
      expect_equal(nrow(res$matches), 0L, info = neg)
      expect_equal(nrow(res$errors), 0L, info = neg)
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

# --- The functions field ------------------------------------------------------
# `functions` is what lets find_indirect() attribute do.call("x", ...) back to a
# rule. It is only trustworthy if it restates the rule's XPath rather than
# asserting something new, so every declared name is checked against the rule
# that declares it. build_db.R enforces this when the database is written; this
# asserts it of the database that actually ships.
test_that("every declared function name is one its own rule matches", {
  for (name in rules$patterns$name) {
    rule      <- rule_row(rules$patterns, name)
    declared  <- strsplit(rule$functions, "[[:space:]]+")[[1L]]
    declared  <- declared[nzchar(declared)]

    for (fn in declared) {
      tree <- tree_from_lines(paste0(fn, "()"))
      res  <- find_patterns(tree, rule, "test.R")
      expect_gt(nrow(res$patterns), 0L)
      expect_equal(unique(res$patterns$rule), name,
                   info = paste0(name, " declares ", fn))
    }
  }
})

# The three rules that can claim no name each match on something do.call() does
# not carry: a nested call, a named argument, a package qualifier. Empty is a
# decision, so it is asserted rather than left to be noticed.
test_that("rules matching on more than the callee declare no functions", {
  # Each of these matches on something do.call() cannot carry, so there is no
  # name it could claim. Recorded with the reason, since an empty field is
  # otherwise indistinguishable from a forgotten one.
  structural <- c(
    eval_parse      = "needs the parse and decode calls nested inside",
    options_repos   = "needs the repos named argument",
    system_processx = "needs the processx:: qualifier",
    credentials     = "matches a string literal, not a call",
    persistence     = "matches a string literal, not a call"
  )
  for (name in names(structural)) {
    rule <- rule_row(rules$patterns, name)
    expect_equal(trimws(rule$functions), "",
                 info = paste(name, "--", structural[[name]]))
  }
  others <- setdiff(rules$patterns$name, names(structural))
  for (name in others) {
    rule <- rule_row(rules$patterns, name)
    expect_true(nzchar(trimws(rule$functions)), info = name)
  }
})

# --- eval_parse composes its sources from other rules -------------------------
# eval_parse fires on text that came from somewhere pkgaudit cannot read, then
# was parsed and evaluated. Which functions count as "somewhere pkgaudit cannot
# read" is not a judgement it makes on its own: it is every function the rules
# for fetching, decoding, deserializing and running a subprocess already claim,
# plus the file reads no rule covers. Hand-listing that in the XPath is what
# keeps the rule reviewable; this is what keeps the list from falling behind.
test_that("eval_parse covers every source its capability rules declare", {
  sources <- c("curl", "rcurl", "httr", "httr2", "download_file", "socket",
               "decoding", "deserialization", "system", "system_sys",
               "system_callr")
  extra   <- c("readLines", "scan", "readBin", "rawToChar")

  declared <- unlist(strsplit(
    rules$patterns$functions[rules$patterns$name %in% sources],
    "[[:space:]]+"))
  declared <- unique(c(declared[nzchar(declared)], extra))

  xpath <- rule_row(rules$patterns, "eval_parse")$xpath
  named <- unique(regmatches(xpath, gregexpr("(?<=text\\(\\) = ')[^']+",
                                             xpath, perl = TRUE))[[1L]])
  missing <- setdiff(declared, named)
  expect_equal(missing, character(0),
               info = paste("eval_parse does not reach:",
                            paste(missing, collapse = ", ")))
})

test_that("eval_parse fires on a source drawn from another rule", {
  rule <- rule_row(rules$patterns, "eval_parse")
  for (code in c('eval(parse(text = readLines(url("http://x"))))',
                 'eval(parse(text = system("cmd", intern = TRUE)))',
                 'eval(parse(text = unserialize(con)))',
                 'eval(parse(text = httr::content(httr::GET(u), "text")))')) {
    res <- find_patterns(tree_from_lines(code), rule, "test.R")
    expect_equal(nrow(res$patterns), 1L, info = code)
  }
  # Text the package built itself is not a payload from outside.
  for (code in c('eval(parse(text = paste0("x <- ", i)))',
                 'eval(parse(text = deparse(sub)))')) {
    res <- find_patterns(tree_from_lines(code), rule, "test.R")
    expect_equal(nrow(res$patterns), 0L, info = code)
  }
})
