# Extraction from R.rsp vignettes. Syntax taken from real vignettes in the
# CRAN snapshot: R.rsp's own example.txt.rsp and babel's babel.tex.rsp.

rules <- load_rules()

test_that("the rsp extractor reads <% %> and <%= %>, skipping directives", {
  pkg <- vignette_pkg("v.md.rsp", c(
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
  expect_true(all(res$patterns$code_context == .context_top_level))
  expect_true(all(res$patterns$at_build & res$patterns$at_check))
})

test_that("an rsp region spanning lines stays aligned to the source", {
  pkg <- vignette_pkg("v.tex.rsp", c(
    "\\begin{verbatim}<%=withCapture({",   # 1
    "  system('id')",                       # 2
    "})%>\\end{verbatim}"                   # 3
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_equal(audit_package(pkg, rules)$patterns$line_number, 2L)
})

test_that("an rsp file with no code yields no segment and no error", {
  pkg <- vignette_pkg("v.md.rsp", c('<%@meta title="T"%>', "Just prose."))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$patterns), 0L)
  expect_equal(nrow(res$errors),   0L)
})

test_that("an unterminated rsp region is read to the end rather than dropped", {
  pkg <- vignette_pkg("v.md.rsp", c("Text", "<% system('id')"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_equal(audit_package(pkg, rules)$patterns$line_number, 2L)
})

# Regressions from the CRAN snapshot. Each of these cost coverage on a real
# vignette: a directive whose quoted content contains "<%" spliced itself into
# the code; two regions sharing a line concatenated into unparseable R; and the
# "<%%" escape and "<%:" echo marker were read as code and as text respectively.
test_that("a directive's quoted content is not spliced into the code", {
  pkg <- vignette_pkg("v.md.rsp", c(
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
  pkg <- vignette_pkg("v.tex.rsp", c("v<%=system('a')%> by <%=system('b')%>"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, rules)
  expect_equal(nrow(res$patterns), 2L)
  expect_equal(nrow(res$errors),   0L)
})

test_that("the <%% escape is not code and the <%: marker is stripped", {
  pkg <- vignette_pkg("v.md.rsp", c(
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

test_that("a vignette that cannot be read yields no segments and one error", {
  res <- extract_segments(new_source(
    file.path(tempfile(), "gone.Rmd.rsp"), "vignettes/gone.Rmd.rsp", "rsp"
  ))
  expect_length(res$segments, 0L)
  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$step, "read_code")
})

test_that("an R.rsp region carrying no code is skipped, not extracted", {
  pkg <- vignette_pkg("intro.Rmd.rsp", c(
    "<%%>",                  # empty region
    "<%-%>",                 # a trim marker and nothing else
    "<%=%>",                 # a write marker and nothing else
    "<%   %>",               # whitespace only
    "<%= %>",                # a write marker and blank
    "<% system('id') %>"     # the one that does carry code
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  res <- audit_package(pkg, load_rules())
  found <- res$patterns[res$patterns$file_context == "vignettes/intro.Rmd.rsp", ]
  expect_equal(found$rule, "system")
  expect_equal(found$line_number, 6L)
})
