rules <- load_rules()

# happy path -------------------------------------------------------------------
test_that("find_file_contexts() finds matching files with relative paths", {
  pkg <- make_pkg(files = list(
    "configure"          = "#!/bin/sh",
    "src/Makevars"       = "all:",
    "src/install.libs.R" = "invisible(NULL)",
    "README.md"          = "hi"           # not a file context
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- find_file_contexts(pkg, rules$file_contexts)
  expect_named(res, c("file_contexts", "errors"))
  # The finder does not set the phase columns; audit_package() attaches them.
  expect_named(res$file_contexts, c("rule", "file_context", "message"))
  expect_equal(nrow(res$errors), 0L)

  # DESCRIPTION and everything under src/ are claimed too, by the rules that
  # exist to account for a file in `coverage` rather than to read it.
  expect_setequal(res$file_contexts$file_context,
                  c("DESCRIPTION", "configure", "src/Makevars", "src/Makevars",
                    "src/install.libs.R", "src/install.libs.R"))
  # rule names the rule that matched, and joins to the rules database.
  expect_equal(
    res$file_contexts$rule[res$file_contexts$file_context == "configure"],
    "configure"
  )
})

test_that("find_file_contexts() returns an empty frame when nothing matches", {
  # Every real package matches something -- DESCRIPTION alone does -- so an
  # empty result needs a directory no rule can reach.
  pkg <- tempfile("bare")
  dir.create(pkg)
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  writeLines("nothing here", file.path(pkg, "NEWS.md"))

  res <- find_file_contexts(pkg, rules$file_contexts)
  expect_equal(nrow(res$file_contexts), 0L)
  expect_equal(nrow(res$errors), 0L)
})

test_that("find_file_contexts() finds R scripts and help pages as contexts", {
  pkg <- make_pkg(files = list("R/zzz.R" = "invisible(NULL)",
                               "man/f.Rd" = "\\name{f}"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- find_file_contexts(pkg, rules$file_contexts)
  expect_true("R/zzz.R"  %in% res$file_contexts$file_context)
  expect_true("man/f.Rd" %in% res$file_contexts$file_context)
  # They are scanned, not reported: both rules carry report = FALSE.
  report <- rules$file_contexts$report[
    match(res$file_contexts$rule, rules$file_contexts$name)]
  expect_false(any(report))
})

test_that("find_file_contexts() handles empty rule set", {
  pkg <- make_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  res <- find_file_contexts(pkg, rules$file_contexts[0, , drop = FALSE])
  expect_equal(nrow(res$file_contexts), 0L)
})

# tryCatch path ----------------------------------------------------------------
test_that("find_file_contexts() records an error for an invalid regex pattern", {
  pkg <- make_pkg(files = list("configure" = "x"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  bad <- rule_row(rules$file_contexts, "configure")
  bad$filename <- "("   # invalid regex -> list.files() errors

  res <- find_file_contexts(pkg, bad)
  expect_equal(nrow(res$file_contexts), 0L)
  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$step, "find_file_contexts")
  expect_equal(res$errors$rule, "configure")
})

test_that("find_file_contexts() does not match directories", {
  pkg <- make_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  dir.create(file.path(pkg, "configure"))  # a *directory* named configure

  res <- find_file_contexts(pkg, rule_row(rules$file_contexts, "configure"))
  expect_equal(nrow(res$file_contexts), 0L)
})

# A missing rule directory is a clean result -- most packages have no R/unix/ --
# so list.files() staying silent there is deliberate. That silence would
# otherwise hide a root that does not exist, which is the opposite conclusion.
test_that("find_file_contexts() never claims a symlinked file", {
  skip_on_os("windows")
  # Following the link would attribute its target's code to the target's path,
  # which no rule claims -- or, outside the package, to a path the scan cannot
  # re-read. build_coverage() reports the skip as unexamined/symlink.
  pkg <- make_pkg(files = list("inst/hidden.R" = "system('id')"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  dir.create(file.path(pkg, "R"))
  file.symlink(file.path(pkg, "inst", "hidden.R"), file.path(pkg, "R", "evil.R"))

  res <- find_file_contexts(pkg, rules$file_contexts)
  expect_false("R/evil.R" %in% res$file_contexts$file_context)
  expect_false("inst/hidden.R" %in% res$file_contexts$file_context)
  expect_equal(nrow(res$errors), 0L)
})

test_that("find_file_contexts() refuses a root that is not a directory", {
  expect_error(find_file_contexts(file.path(tempfile(), "nope"),
                                  rules$file_contexts), "dir.exists")

  f <- tempfile(); writeLines("x", f)
  on.exit(unlink(f), add = TRUE)
  expect_error(find_file_contexts(f, rules$file_contexts), "dir.exists")
})

test_that("a rule whose directory is absent is still a clean result", {
  pkg <- make_pkg(files = list("R/a.R" = "f <- function() 1"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  # The rules cover R/unix/, man/windows/ and others this package does not have.
  res <- find_file_contexts(pkg, rules$file_contexts)
  expect_equal(nrow(res$errors), 0L)
  expect_true(nrow(res$file_contexts) >= 0L)
})
