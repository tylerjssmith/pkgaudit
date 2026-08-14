# Analysis of R code, whatever file it came out of. Dispatch is on the segment's
# language; what produced the segment is test-type_*.R.

rules <- load_rules()

r_segment <- function(lines, ...) {
  analyze_segment(new_segment("R", lines, "R/zzz.R", ...), rules)
}

test_that("code that will not parse is an error, not an empty result", {
  found <- r_segment("f <- function( {")

  expect_equal(nrow(found$patterns), 0L)
  expect_equal(found$errors$step, "parse_code")
  expect_equal(found$errors$file_context, "R/zzz.R")
})

test_that("a finding carries a preview of the line it sits on", {
  found <- r_segment(c("x <- 1", "system('id')"), code_contexts = .hook_rules)

  expect_equal(found$patterns$line_number, 2L)
  expect_equal(found$patterns$preview, "system('id')")
})

test_that("a preview says when the construct carries on past its first line", {
  # Most pattern rules match a single token, which never spans lines. A rule
  # matching a whole expression can, and eval_parse is one.
  found <- r_segment(c("eval(parse(text =", "  readLines(con)", "))"))
  expect_equal(found$patterns$rule, "eval_parse")
  expect_match(found$patterns$preview, "\\.\\.\\.$")
})

test_that("guarded lines are marked and everything else is not", {
  found <- analyze_segment(
    new_segment("R", c("system('a')", "system('b')"), "man/f.Rd",
                context = .context_rd_examples, guarded_lines = 2L),
    rules)
  guarded <- setNames(found$patterns$guarded, found$patterns$line_number)

  expect_false(guarded[["1"]])
  expect_true(guarded[["2"]])
})

test_that("direct and indirect findings arrive as one frame", {
  found <- r_segment(c("system('id')", "do.call('system', list('id'))"),
                     code_contexts = .hook_rules)

  expect_equal(nrow(found$patterns), 2L)
  expect_setequal(found$patterns$indirect, c(FALSE, TRUE))
  # Both are system findings: a reviewer filtering on rule sees the pair.
  expect_equal(unique(found$patterns$rule), "system")
})

test_that("a preview is right for an indirect finding too", {
  # rbind() drops attributes, so the matched nodes have to be carried across
  # the join by hand; a wrong preview is how that would show up.
  found <- r_segment(c("x <- 1", "do.call('system', list('id'))"),
                     code_contexts = .hook_rules)
  expect_match(found$patterns$preview, "do.call", fixed = TRUE)
})

test_that("a segment's label replaces top_level, and only that", {
  found <- analyze_segment(
    new_segment("R", c("system('a')", "f <- function() system('b')"),
                "man/f.Rd", context = .context_rd_examples),
    rules)
  ctx <- setNames(found$patterns$code_context, found$patterns$line_number)

  expect_equal(ctx[["1"]], .context_rd_examples)
  # Code inside a function keeps in_function, so the fact that it sits in one
  # is not lost; it inherits the segment's phases when they are resolved.
  expect_equal(ctx[["2"]], .context_in_function)
})

test_that("a broken code-context rule is reported rather than matching nothing", {
  # determine_code_contexts() evaluates the same XPaths and skips one that
  # fails, so without find_code_contexts() running this would be silent.
  broken <- rules
  broken$code_contexts$xpath[[1L]] <- "//["

  found <- analyze_segment(
    new_segment("R", "system('id')", "R/zzz.R", code_contexts = .hook_rules), broken)
  expect_equal(found$errors$step, "find_code_contexts")
})

test_that(".node_continues() over no nodes is an empty logical", {
  expect_equal(.node_continues(list()), logical(0L))
})
