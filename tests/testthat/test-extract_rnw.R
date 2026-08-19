# Extraction from Sweave and knitr .Rnw vignettes.

rules <- load_rules()

test_that("the Rnw extractor reads <<>>= chunks and inline \\Sexpr", {
  pkg <- vignette_pkg("v.Rnw", c(
    "\\documentclass{article}",              # 1
    "\\begin{document}",                     # 2
    "<<setup>>=",                            # 3
    "system('id')",                          # 4
    "@",                                     # 5
    "Inline \\Sexpr{download.file(u, t)} here.",  # 6
    "\\end{document}"                        # 7
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_setequal(res$patterns$rule, c("system", "download_file"))
  expect_setequal(res$patterns$line_number, c(4L, 6L))
  expect_true(all(res$patterns$code_context == .context_top_level))
})

test_that("two inline \\Sexpr on one line both report, at their own columns", {
  pkg <- vignette_pkg("v.Rnw", c(
    "\\begin{document}",                                          # 1
    "Two \\Sexpr{system('a')} and \\Sexpr{system('b')} here.",    # 2
    "\\end{document}"                                             # 3
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$patterns), 2L)
  expect_equal(unique(res$patterns$line_number), 2L)
  expect_setequal(res$patterns$column_number, c(5L, 29L))
})

test_that("an @ followed by text still ends a chunk", {
  # Sweave ends a chunk at any line starting with @ and whitespace, and itself
  # emits `@ %def x` lines. Reading past one swallowed every later chunk: the
  # segment stopped parsing and the whole file reported nothing.
  pkg <- vignette_pkg("v.Rnw", c(
    "\\begin{document}",   # 1
    "<<a>>=",              # 2
    "x <- 1",              # 3
    "@ %def x",            # 4
    "Some prose.",         # 5
    "<<b>>=",              # 6
    "system('id')",        # 7
    "@",                   # 8
    "\\end{document}"      # 9
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$rule, "system")
  expect_equal(res$patterns$line_number, 7L)
  expect_equal(nrow(res$errors), 0L)
})

test_that("an Rnw chunk marked eval=FALSE is guarded", {
  pkg <- vignette_pkg("v.Rnw", c("\\begin{document}", "<<a, eval=FALSE>>=",
                            "system('id')", "@", "\\end{document}"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_true(audit_package(pkg, rules)$patterns$guarded)
})

test_that("LaTeX outside a chunk is not scanned", {
  pkg <- vignette_pkg("v.Rnw", c("\\documentclass{article}",
                            "\\begin{document}",
                            "Do not call system('id') at home.",
                            "\\end{document}"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_equal(nrow(audit_package(pkg, rules)$patterns), 0L)
})

test_that("a vignette that cannot be read yields no segments and one error", {
  res <- extract_segments(new_source(
    file.path(tempfile(), "gone.Rnw"), "vignettes/gone.Rnw", "Rnw"
  ))
  expect_length(res$segments, 0L)
  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$step, "read_code")
})
