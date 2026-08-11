# Extraction from knitr-style literate documents: .Rmd, and .qmd which
# inherits from it because the chunk syntax is the same.

rules <- load_rules()

test_that("the Rmd extractor emits a segment per chunk, tagged by its engine", {
  pkg <- vignette_pkg("v.Rmd", c(
    "---", "title: V", "---",
    "```{r}", "system('id')", "```",
    "```{bash}", "curl https://www.evil.test/x", "```",
    "```{ojs}", "notAnEngineWeHandle = 1", "```"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  # The R chunk is parsed, the bash chunk is matched, and the ojs chunk falls
  # through to the default analyser: no findings, and no error either.
  expect_equal(res$patterns$rule, "system")
  expect_equal(res$matches$rule,  "curl")
  expect_equal(nrow(res$errors),  0L)
})

test_that("a vignette finding points at its line in the source file", {
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---", "", "```{r}",
                            "x <- 1", "system('id')", "```"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$line_number, 7L)
  expect_equal(res$patterns$code_context, "vignettes")
  expect_true(res$patterns$at_build)
  expect_true(res$patterns$at_check)
  expect_false(res$patterns$at_install_src)
})

test_that("an eval=FALSE chunk is scanned and marked guarded", {
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---",
                            "```{r, eval=FALSE}", "system('id')", "```",
                            "```{r}", "system('id')", "```"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_setequal(res$patterns$line_number, c(5L, 8L))
  expect_true(res$patterns$guarded[res$patterns$line_number == 5L])
  expect_false(res$patterns$guarded[res$patterns$line_number == 8L])
})

test_that("qmd is read by the Rmd extractor it inherits from", {
  pkg <- vignette_pkg("v.qmd", c("---", "title: V", "---",
                            "```{r}", "system('id')", "```"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$rule, "system")
  expect_equal(res$patterns$file_context, "vignettes/v.qmd")
})

test_that("an unterminated chunk is read to the end rather than dropped", {
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---", "```{r}", "system('id')"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_equal(audit_package(pkg, rules)$patterns$rule, "system")
})

test_that("prose outside a chunk is not scanned", {
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---",
                            "Write system('id') in a chunk to run it."))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_equal(nrow(audit_package(pkg, rules)$patterns), 0L)
})

test_that("a Pandoc attribute block is displayed code, not a chunk", {
  # ```{.r} marks a block for syntax highlighting in the rendered page; its
  # contents are printed, not run. Treating it as a chunk invented a segment in
  # a language called ".r" and reported it as code pkgaudit had not examined.
  pkg <- make_pkg(files = list("vignettes/intro.Rmd" = c(
    "---", "title: x", "---", "",
    "```{r}", "y <- 1", "```", "",
    "Here is what that prints:", "",
    "```{.r}", "getOption(\"x\")", "```"
  )))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  cv <- audit_package(pkg, rules)$coverage
  rows <- cv[cv$file_context == "vignettes/intro.Rmd", ]
  expect_equal(nrow(rows), 1L)
  expect_equal(rows$status, "parsed")
})

test_that("a vignette that cannot be read yields no segments and one error", {
  res <- extract_segments(new_source(
    file.path(tempfile(), "gone.Rmd"), "vignettes/gone.Rmd", "Rmd"
  ))
  expect_length(res$segments, 0L)
  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$step, "read_code")
})
