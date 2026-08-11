test_that("parse_code() returns an xml tree for valid R", {
  res <- parse_code("system('id')")
  expect_null(res$error)
  expect_s3_class(res$tree, "xml_document")
  expect_gt(length(xml2::xml_find_all(res$tree, "//SYMBOL_FUNCTION_CALL")), 0L)
})

test_that("parse_code() returns an error for a syntax error", {
  res <- parse_code("this is not { valid R )(")
  expect_null(res$tree)
  expect_type(res$error, "character")
})

test_that("parse_code() accepts an empty program", {
  for (empty in list(character(0L), "", c("", ""))) {
    res <- parse_code(empty)
    expect_null(res$error)
    expect_s3_class(res$tree, "xml_document")
  }
})

test_that("parse_code() rejects a non-character argument", {
  expect_error(parse_code(42L), "is.character")
})

# Line fidelity is what lets a finding point back into the file the code came
# from, so it is pinned here rather than left to the callers that rely on it.
test_that("parse_code() numbers lines from the start of what it is given", {
  res  <- parse_code(c("", "", "system('id')"))
  node <- xml2::xml_find_first(res$tree, "//SYMBOL_FUNCTION_CALL")
  expect_equal(as.integer(xml2::xml_attr(node, "line1")), 3L)
})

test_that("parse_code() on a file's lines matches parsing the same code inline", {
  f <- tempfile(fileext = ".R")
  on.exit(unlink(f), add = TRUE)
  code <- c("# comment", ".onLoad <- function(libname, pkgname) {",
            "  system('id')", "}")
  writeLines(code, f)

  from_file <- parse_code(read_code(f)$lines)
  inline    <- parse_code(code)
  expect_equal(as.character(from_file$tree), as.character(inline$tree))
})

test_that("parse_code() of an empty file is an empty program, not an error", {
  res <- parse_code(character(0L))
  expect_null(res$error)
  expect_s3_class(res$tree, "xml_document")
})
