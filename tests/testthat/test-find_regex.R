rules <- load_rules()

# A one-row regex rules frame with the given expression, so tests can exercise
# find_regex() without depending on what the shipped rules happen to match.
regex_rule <- function(regex, name = "probe", message = "m", attck = "T1041") {
  data.frame(name = name, version = "0.1.0", message = message,
             attck = attck, regex = regex, stringsAsFactors = FALSE)
}

# structure --------------------------------------------------------------------
test_that("find_regex() returns expressions and errors frames with fixed columns", {
  res <- find_regex("curl https://evil.test/x", rules$regex, "configure")
  expect_named(res, c("expressions", "errors"))
  expect_named(res$expressions,
               c("rule", "file_context", "line_number", "column_number",
                 "message", "attck"))
  expect_named(res$errors, c("stage", "file_context", "rule", "message"))
})

test_that("find_regex() reports the rule, message, and ATT&CK labels of the match", {
  res <- find_regex("curl https://evil.test/x", rules$regex, "configure")
  expect_equal(res$expressions$rule, "curl")
  expect_equal(res$expressions$file_context, "configure")
  expect_equal(res$expressions$attck,
               rules$regex$attck[rules$regex$name == "curl"])
  expect_equal(res$expressions$message,
               rules$regex$message[rules$regex$name == "curl"])
})

test_that("find_regex() with no rules finds nothing and raises nothing", {
  for (empty in list(NULL, rules$regex[0L, , drop = FALSE])) {
    res <- find_regex("curl https://evil.test/x", empty, "configure")
    expect_equal(nrow(res$expressions), 0L)
    expect_equal(nrow(res$errors), 0L)
  }
})

test_that("find_regex() rejects a non-character argument", {
  expect_error(find_regex(42L, rules$regex, "configure"), "is.character")
})

# positions --------------------------------------------------------------------
test_that("find_regex() reports the line and starting column of each match", {
  res <- find_regex(c("#!/bin/sh", "echo hi", "  curl -s https://evil.test/x"),
                    regex_rule("curl"), "configure")
  expect_equal(res$expressions$line_number,   3L)
  expect_equal(res$expressions$column_number, 3L)
})

test_that("find_regex() reports every match on a line, not just the first", {
  res <- find_regex("curl a && curl b", regex_rule("curl"), "configure")
  expect_equal(nrow(res$expressions), 2L)
  expect_equal(res$expressions$line_number,   c(1L, 1L))
  expect_equal(res$expressions$column_number, c(1L, 11L))
})

test_that("find_regex() counts columns in characters, not bytes", {
  # Two multi-byte characters precede the match, so a byte offset would be 7.
  res <- find_regex("éé && curl x", regex_rule("curl"), "configure")
  expect_equal(res$expressions$column_number, 7L)
})

test_that("find_regex() matches case-sensitively", {
  res <- find_regex(c("CURL x", "Curl x", "curl x"), regex_rule("curl"),
                    "configure")
  expect_equal(res$expressions$line_number, 3L)
})

test_that("find_regex() applies every rule to the lines", {
  res <- find_regex(c("curl https://evil.test/a", "wget https://evil.test/b"),
                    rules$regex, "configure")
  expect_setequal(res$expressions$rule, c("curl", "wget"))
  expect_equal(nrow(res$errors), 0L)
})

test_that("find_regex() uses PCRE, so lookaround in a rule is honoured", {
  res <- find_regex(c("curl x", "libcurl x"),
                    regex_rule("(?<=^|[^[:alnum:]_-])curl"), "configure")
  expect_equal(res$expressions$line_number, 1L)
})

# empty and unmatched input ----------------------------------------------------
test_that("find_regex() finds nothing in lines with no match", {
  res <- find_regex(c("#!/bin/sh", "echo configuring"), rules$regex, "configure")
  expect_equal(nrow(res$expressions), 0L)
  expect_equal(nrow(res$errors), 0L)
})

test_that("find_regex() handles an empty file's lines", {
  for (empty in list(character(0L), "")) {
    res <- find_regex(empty, rules$regex, "configure")
    expect_equal(nrow(res$expressions), 0L)
    expect_equal(nrow(res$errors), 0L)
  }
})

# errors -----------------------------------------------------------------------
test_that("find_regex() records an invalid regex against its rule and continues", {
  both <- rbind(regex_rule("(unclosed", name = "broken"), regex_rule("curl"))
  res  <- find_regex("curl https://evil.test/x", both, "configure")

  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$stage, "find_regex")
  expect_equal(res$errors$rule,  "broken")
  expect_equal(res$errors$file_context, "configure")
  # The sound rule was still evaluated after the broken one failed.
  expect_equal(res$expressions$rule, "probe")
})
