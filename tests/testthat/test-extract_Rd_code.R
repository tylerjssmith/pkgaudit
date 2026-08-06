rd_file <- function(lines, name = "f.Rd") {
  dir <- tempfile("rd")
  dir.create(dir)
  path <- file.path(dir, name)
  writeLines(lines, path)
  path
}

# A help page exercising every construct the extractor has to handle.
probe <- c(
  "\\name{f}",                                                  # 1
  "\\alias{f}",                                                 # 2
  "\\title{T \\Sexpr{format(Sys.time())}}",                     # 3
  "\\description{",                                             # 4
  "  D \\Sexpr[stage=build]{system(\"id\")} here.",             # 5
  "}",                                                          # 6
  "\\examples{",                                                # 7
  "x <- 1  # 50\\% and a brace \\{",                            # 8
  "cat(\"a\\\\nb\")",                                           # 9
  "\\dontrun{",                                                 # 10
  "  system(\"id\")",                                           # 11
  "}",                                                          # 12
  "\\dontshow{ hidden <- TRUE }",                               # 13
  "y <- 2",                                                     # 14
  "}"                                                           # 15
)

test_that("extract_Rd_code() returns two code strings and an error slot", {
  path <- rd_file(probe)
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- extract_Rd_code(path)
  expect_named(res, c("examples", "sexpr", "error"))
  expect_type(res$examples, "character")
  expect_type(res$sexpr, "character")
  expect_null(res$error)
})

test_that("both streams parse as R", {
  path <- rd_file(probe)
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- extract_Rd_code(path)
  expect_no_error(parse(text = res$examples))
  expect_no_error(parse(text = res$sexpr))
})

# Line alignment is the property that lets a finding point into the .Rd, so it
# is asserted directly rather than inferred from downstream behaviour.
test_that("extracted code is aligned to the lines of the .Rd", {
  path <- rd_file(probe)
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- extract_Rd_code(path)
  ex  <- strsplit(res$examples, "\n", fixed = TRUE)[[1L]]
  sx  <- strsplit(res$sexpr,    "\n", fixed = TRUE)[[1L]]

  expect_match(ex[[8L]],  "^x <- 1")
  expect_match(ex[[11L]], "system")
  expect_match(ex[[14L]], "^y <- 2")
  expect_match(sx[[3L]],  "format\\(Sys.time\\(\\)\\)")
  expect_match(sx[[5L]],  "system")
})

test_that("parsing the examples stream yields .Rd line numbers", {
  path <- rd_file(probe)
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  parsed <- parse(text = extract_Rd_code(path)$examples, keep.source = TRUE)
  lines  <- vapply(attr(parsed, "srcref"), function(s) s[[1L]], integer(1L))
  # x <- 1 on line 8, the \dontrun system() on 11, hidden on 13, y <- 2 on 14.
  expect_equal(lines, c(8L, 9L, 11L, 13L, 14L))
})

test_that("all four example wrappers are unwrapped", {
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\examples{",
                    "\\dontrun{  a <- 1 }", "\\donttest{ b <- 2 }",
                    "\\dontshow{ c <- 3 }", "\\testonly{ d <- 4 }", "}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  code <- extract_Rd_code(path)$examples
  for (v in c("a <- 1", "b <- 2", "c <- 3", "d <- 4")) expect_match(code, v)
})

test_that("Rd escapes are resolved and Rd comments dropped", {
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\examples{",
                    "z <- c(1,2) \\%in\\% c(1)",
                    "% an Rd comment",
                    "g(1)  % a trailing Rd comment", "}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  code <- extract_Rd_code(path)$examples
  expect_match(code, "%in%", fixed = TRUE)
  expect_false(grepl("an Rd comment", code))
  expect_no_error(parse(text = code))
})

test_that("\\dots becomes an ellipsis rather than vanishing", {
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\examples{", "f(\\dots)", "}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  code <- extract_Rd_code(path)$examples
  expect_match(code, "f(...", fixed = TRUE)
})

test_that("an inline \\Sexpr goes to the sexpr stream, not the examples one", {
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\examples{",
                    "h(\\Sexpr{2+2})", "}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- extract_Rd_code(path)
  expect_match(res$sexpr, "2+2", fixed = TRUE)
  expect_false(grepl("2+2", res$examples, fixed = TRUE))
  expect_no_error(parse(text = res$examples))
})

test_that("a file with no code yields empty strings and no error", {
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\description{No code.}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- extract_Rd_code(path)
  expect_equal(res$examples, "")
  expect_equal(res$sexpr, "")
  expect_null(res$error)
})

# errors -----------------------------------------------------------------------
test_that("a missing file or a directory is reported, not signalled", {
  expect_match(extract_Rd_code(tempfile())$error, "not a readable file")
  expect_match(extract_Rd_code(tempdir())$error, "not a readable file")
})

test_that("a file parse_Rd() only warns about keeps its code and reports why", {
  # parse_Rd() recovers from this with a warning and a truncated tree. The
  # recovered code is still returned, but error says not to trust it as whole.
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\examples{ a <- 1"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- extract_Rd_code(path)
  expect_type(res$error, "character")
  expect_match(res$examples, "a <- 1")
})

test_that("macros are expanded only when supplied", {
  pkg <- tempfile("mp")
  dir.create(file.path(pkg, "man", "macros"), recursive = TRUE)
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  writeLines("Package: mp", file.path(pkg, "DESCRIPTION"))
  writeLines("\\newcommand{\\bang}{\\Sexpr{system(\"id\")}}",
             file.path(pkg, "man", "macros", "m.Rd"))
  page <- file.path(pkg, "man", "page.Rd")
  writeLines(c("\\name{p}", "\\title{P}", "\\description{Uses \\bang{} here.}"),
             page)

  with_m <- extract_Rd_code(page, macros = tools::loadPkgRdMacros(pkg))
  expect_match(with_m$sexpr, "system")
  expect_null(with_m$error)

  without <- extract_Rd_code(page)
  expect_equal(without$sexpr, "")
  expect_match(without$error, "unknown macro")
})
