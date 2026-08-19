# find_indirect() reports a call made through a function's name under the rule
# that owns the name, so a reviewer filtering on `rule` sees it alongside the
# direct calls.

rules <- load_rules()

found <- function(code) {
  res <- find_indirect(tree_from_lines(code), rules$patterns, "test.R")
  expect_equal(nrow(res$errors), 0L)
  res$patterns
}

test_that("a string-literal target is attributed to the rule owning the name", {
  pat <- found('do.call("system", list("id"))')

  expect_equal(nrow(pat), 1L)
  expect_equal(pat$rule, "system")
  expect_true(pat$indirect)
  expect_equal(pat$message, rule_row(rules$patterns, "system")$message)
  expect_equal(pat$attck, rule_row(rules$patterns, "system")$attck)
})

test_that("all three accessors are read, named or positional", {
  for (code in c('do.call("system", list("id"))',
                 'do.call(what = "system", args = list("id"))',
                 'base::do.call("system", list("id"))',
                 'match.fun("system")',
                 'match.fun(FUN = "system")',
                 'getFunction("system")')) {
    expect_equal(nrow(found(code)), 1L, info = code)
  }
})

test_that("argument order does not decide whether a target is read", {
  # R binds these to `what` regardless of where they sit in the call, so a
  # one-token rearrangement must not become an evasion.
  for (code in c('do.call(args = list("id"), what = "system")',
                 'do.call(args = list("id"), "system")',
                 'do.call( # comment\n  "system", list("id"))',
                 'getFunction(name = "system")')) {
    pat <- found(code)
    expect_equal(nrow(pat), 1L, info = code)
    expect_equal(pat$rule, "system", info = code)
  }
})

test_that("a literal named for some other parameter is not reported", {
  # do.call has no FUN and match.fun has no what; these never resolve a
  # function, so reporting them would attribute a call that cannot happen.
  for (code in c('do.call(FUN = "system", args = list())',
                 'match.fun(what = "system")',
                 'getFunction(FUN = "system")')) {
    expect_equal(nrow(found(code)), 0L, info = code)
  }
})

test_that("the position points at the literal, not at the accessor", {
  pat <- found('do.call("system", list("id"))')

  # Column 9 is the opening quote of "system"; the accessor starts at 1.
  expect_equal(pat$line_number, 1L)
  expect_equal(pat$column_number, 9L)
})

test_that("a name no rule declares is not reported", {
  # rbind is the single most common do.call target in CRAN and belongs to no
  # rule; reporting it is what made the old indirection rule unusable.
  for (code in c('do.call("rbind", parts)',
                 'do.call("cbind", parts)',
                 'do.call("paste", bits)')) {
    expect_equal(nrow(found(code)), 0L, info = code)
  }
})

test_that("a target that is not a first-position literal is not reported", {
  for (code in c('do.call(fn, args)',            # not a literal
                 'do.call(fn, "system")',        # literal, wrong position
                 'match.fun(handler)',
                 'do.call(paste0("sys", "tem"), list())',
                 'foo$do.call("system", list())',
                 'foo@match.fun("system")')) {
    expect_equal(nrow(found(code)), 0L, info = code)
  }
})

test_that("a rule declaring no functions claims nothing", {
  # options_repos matches options(repos = ...); the named argument is gone
  # once the call goes through do.call, so the rule must not claim "options".
  expect_equal(nrow(found('do.call("options", list(repos = u))')), 0L)
  expect_equal(nrow(found('do.call("eval", list(parse(text = x)))')), 0L)
})

test_that("an escaped or raw literal is skipped rather than guessed at", {
  # Comparing these would mean unescaping, and getting that subtly wrong would
  # attribute a finding to the wrong rule.
  expect_equal(nrow(found('do.call("sys\\x74em", list())')), 0L)
  expect_equal(nrow(found('do.call(r"(system)", list())')), 0L)
})

test_that("the matched node is returned for code-context assignment", {
  pat   <- found('f <- function() do.call("system", list("id"))')
  nodes <- attr(pat, "nodes")

  expect_length(nodes, 1L)
  expect_equal(nrow(pat), 1L)
  # The node is the whole call, so containment tests see it inside the function.
  expect_true(grepl("do.call", xml2::xml_text(nodes[[1L]]), fixed = TRUE))
})

test_that("rules without a functions column yield nothing rather than erroring", {
  bare <- rules$patterns
  bare$functions <- NULL

  res <- find_indirect(tree_from_lines('do.call("system", list())'), bare, "t.R")
  expect_equal(nrow(res$patterns), 0L)
  expect_equal(nrow(res$errors), 0L)
})

test_that("an indirect finding reaches the audit alongside the direct ones", {
  pkg <- make_pkg(files = list("R/hooks.R" = c(
    '.onLoad <- function(...) {',
    '  system("id")',
    '  do.call("system", list("id"))',
    '}'
  )))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules = rules)
  sys <- res$patterns[res$patterns$rule == "system", ]

  expect_equal(nrow(sys), 2L)
  expect_equal(sort(sys$indirect), c(FALSE, TRUE))
  # Both sit in the same hook and therefore carry the same phases.
  expect_equal(unique(sys$code_context), "onLoad_base")
  expect_true(all(sys$at_load))
})

test_that("find_indirect() with no rules claiming a name finds nothing", {
  tree <- tree_from_lines('do.call("system", list("id"))')
  bare <- rules$patterns
  bare$functions <- ""

  res <- find_indirect(tree, bare, "R/f.R")
  expect_equal(nrow(res$patterns), 0L)
  expect_equal(nrow(res$errors), 0L)

  expect_equal(nrow(find_indirect(tree, NULL, "R/f.R")$patterns), 0L)
})

test_that("find_indirect() records a failed search rather than aborting", {
  # A tree the XPath cannot be evaluated against: the failure becomes a row.
  res <- find_indirect(NULL, rules$patterns, "R/f.R")
  expect_equal(nrow(res$patterns), 0L)
  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$step, "find_indirect")
  expect_equal(res$errors$file_context, "R/f.R")
})

test_that(".string_value() reads only a plain quoted literal", {
  expect_equal(.string_value('"system"'), "system")
  expect_equal(.string_value("'system'"), "system")
  # Not a literal the parser recorded whole, so nothing is claimed about it.
  expect_true(is.na(.string_value(NA_character_)))
  expect_true(is.na(.string_value(character(0L))))
  expect_true(is.na(.string_value(c("a", "b"))))
  expect_true(is.na(.string_value("system")))
  expect_true(is.na(.string_value('"sys\\x74em"')))
})
