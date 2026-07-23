test_that("parse_script() returns an xml tree for valid R", {
  f <- tempfile(fileext = ".R")
  on.exit(unlink(f), add = TRUE)
  writeLines("system('id')", f)

  res <- parse_script(f)
  expect_null(res$error)
  expect_s3_class(res$tree, "xml_document")
  expect_gt(length(xml2::xml_find_all(res$tree, "//SYMBOL_FUNCTION_CALL")), 0L)
})

test_that("parse_script() returns an error for a syntax error", {
  f <- tempfile(fileext = ".R")
  on.exit(unlink(f), add = TRUE)
  writeLines("this is not { valid R )(", f)

  res <- parse_script(f)
  expect_null(res$tree)
  expect_type(res$error, "character")
})

test_that("parse_script() returns an error for a missing file", {
  res <- parse_script(tempfile(fileext = ".R"))
  expect_null(res$tree)
  expect_type(res$error, "character")
})
