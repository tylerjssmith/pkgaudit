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
  expect_equal(res$patterns$code_context, .context_top_level)
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

test_that("a hash-pipe eval option guards a chunk, in either document type", {
  for (name in c("v.Rmd", "v.qmd")) {
    pkg <- vignette_pkg(name, c("---", "title: V", "---",
                                "```{r}", "#| label: a", "#| eval: false",
                                "system('id')", "```",
                                "```{r}", "#| eval: true", "system('id')", "```",
                                "```{r}", "system('id')", "```"))
    on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

    res <- audit_package(pkg, rules)
    guarded <- res$patterns$guarded[order(res$patterns$line_number)]
    expect_equal(guarded, c(TRUE, FALSE, FALSE), info = name)
  }
})

test_that("a hash-pipe line below the code is not read as an option", {
  # Options run until the first line that is not one, so a `#|` comment written
  # further down is code, not configuration.
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---",
                                 "```{r}", "system('id')", "#| eval: false",
                                 "```"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  expect_false(audit_package(pkg, rules)$patterns$guarded)
})

test_that("either eval syntax alone is enough to guard a chunk", {
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---",
                                 "```{r, eval=FALSE}", "#| label: a",
                                 "system('id')", "```"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  expect_true(audit_package(pkg, rules)$patterns$guarded)
})

test_that("an eval option computed at render time is left unguarded", {
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---",
                                 "```{r}", "#| eval: !expr nzchar(Sys.getenv('X'))",
                                 "system('id')", "```"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  # Resolving it would mean evaluating the document, so it reports more.
  expect_false(audit_package(pkg, rules)$patterns$guarded)
})

test_that("inline code is extracted at its own line and column", {
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---",   # 1-3
                                 "Inline `r system('id')` here."))  # 4
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$rule, "system")
  expect_equal(res$patterns$line_number, 4L)
  # Column 8 is where the macro opens in the source line, as it is for the
  # \Sexpr the Rnw extractor reads. Padding to it is the point of the rewrite.
  expect_equal(res$patterns$column_number, 8L)
  expect_false(res$patterns$guarded)
})

test_that("the Quarto inline form is extracted too", {
  pkg <- vignette_pkg("v.qmd", c("---", "title: V", "---",
                                 "Inline `{r} system('id')` here."))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$rule, "system")
  expect_equal(res$patterns$line_number, 4L)
  expect_equal(res$patterns$column_number, 8L)
})

test_that("two inline expressions on one line both report", {
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---",
                                 "Two `r system('a')` and `r system('b')` here."))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$patterns), 2L)
  expect_setequal(res$patterns$column_number, c(5L, 25L))
})

test_that("inline code shown verbatim in doubled backticks is not run", {
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---",
                                 "Literal `` `r system('id')` `` shown."))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  expect_equal(nrow(audit_package(pkg, rules)$patterns), 0L)
})

test_that("inline code is not read from inside a chunk", {
  # A chunk's code is a segment already; reading it again would double-count it.
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---",
                                 "```{r}", "x <- \"`r system('chunk')`\"", "```"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  expect_equal(nrow(audit_package(pkg, rules)$patterns), 0L)
})

test_that("inline code in the YAML front matter is read: knitr evaluates it", {
  pkg <- vignette_pkg("v.Rmd", c("---",                          # 1
                                 "title: \"`r system('id')`\"",  # 2
                                 "---"))                         # 3
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$rule, "system")
  expect_equal(res$patterns$line_number, 2L)
  expect_equal(res$patterns$column_number, 9L)
})

test_that("the hash spelling of inline code is read", {
  # knitr accepts `r#expr` as well as `r expr`.
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---",
                                 "Inline `r#system('id')` here."))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$rule, "system")
  expect_equal(res$patterns$line_number, 4L)
})

test_that("a blockquoted chunk is extracted: knitr evaluates it", {
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---",  # 1-3
                                 "> ```{r}",                 # 4
                                 "> system('id')",           # 5
                                 "> ```"))                   # 6
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$rule, "system")
  expect_equal(res$patterns$line_number, 5L)
  # The blockquote marker becomes a space, so the column is the source one.
  expect_equal(res$patterns$column_number, 3L)
  expect_equal(nrow(res$errors), 0L)
})

test_that("a vignette whose only code is inline is still read", {
  pkg <- vignette_pkg("v.Rmd", c("---", "title: V", "---",
                                 "Only `r system('id')` here."))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$patterns), 1L)
  row <- res$coverage[res$coverage$file_context == "vignettes/v.Rmd", ]
  expect_equal(row$status, "parsed")
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
