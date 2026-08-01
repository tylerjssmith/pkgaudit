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

  expect_setequal(res$file_contexts$file_context,
                  c("configure", "src/Makevars", "src/install.libs.R"))
  # rule names the rule that matched, and joins to the rules database.
  expect_equal(
    res$file_contexts$rule[res$file_contexts$file_context == "configure"],
    "configure"
  )
})

test_that("find_file_contexts() returns empty frame when nothing matches", {
  pkg <- make_pkg(files = list("R/zzz.R" = "invisible(NULL)"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- find_file_contexts(pkg, rules$file_contexts)
  expect_equal(nrow(res$file_contexts), 0L)
  expect_equal(nrow(res$errors), 0L)
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
  bad$pattern <- "("   # invalid regex -> list.files() errors

  res <- find_file_contexts(pkg, bad)
  expect_equal(nrow(res$file_contexts), 0L)
  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$stage, "find_file_contexts")
  expect_equal(res$errors$rule, "configure")
})

test_that("find_file_contexts() does not match directories", {
  pkg <- make_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  dir.create(file.path(pkg, "configure"))  # a *directory* named configure

  res <- find_file_contexts(pkg, rule_row(rules$file_contexts, "configure"))
  expect_equal(nrow(res$file_contexts), 0L)
})
