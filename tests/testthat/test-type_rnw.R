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
  expect_true(all(res$patterns$code_context == "vignettes"))
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
