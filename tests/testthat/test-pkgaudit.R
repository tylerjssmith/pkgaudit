# The constructor and its validators. good_metadata() and make_obj() are
# defined in helper-pkgaudit.R.

# new_pkgaudit() ---------------------------------------------------------------
test_that("new_pkgaudit() accepts a well-formed object", {
  obj <- make_obj()
  expect_s3_class(obj, "pkgaudit")
  expect_named(obj, c("file_contexts", "patterns", "matches", "coverage",
                      "errors", "metadata"))
})

test_that("new_pkgaudit() errors when a data frame is not a data frame", {
  expect_error(
    new_pkgaudit("nope", .empty_patterns(), .empty_matches(),
                 .empty_coverage(), .empty_errors(), good_metadata()),
    "file_contexts.*must be a data frame"
  )
})

test_that("new_pkgaudit() errors on wrong data-frame columns", {
  bad <- .empty_file_contexts()
  bad$message <- NULL
  expect_error(new_pkgaudit(bad, .empty_patterns(), .empty_matches(),
                            .empty_coverage(), .empty_errors(),
                            good_metadata()),
               "file_contexts.*missing: message")
})

test_that("new_pkgaudit() errors on wrong matches columns", {
  # An match carries no code_context: its phases come from its file
  # context, so a frame shaped like patterns is not one.
  expect_error(new_pkgaudit(.empty_file_contexts(), .empty_patterns(),
                            .empty_patterns(), .empty_coverage(),
                            .empty_errors(), good_metadata()),
               "matches.*unexpected: code_context")
})

test_that("new_pkgaudit() errors on a missing metadata field", {
  md <- good_metadata()
  md$scanned <- NULL
  expect_error(make_obj(metadata = md), "missing.*scanned")
})

test_that("new_pkgaudit() errors on an unexpected metadata field", {
  md <- good_metadata()
  md$surprise <- "x"
  expect_error(make_obj(metadata = md), "unexpected.*surprise")
})

test_that("new_pkgaudit() errors on a wrong-typed metadata field", {
  expect_error(make_obj(metadata = good_metadata(pkg_is_tarball = "yes")),
               "pkg_is_tarball.*must be a length-one logical")
  expect_error(make_obj(metadata = good_metadata(pkg_name = 1L)),
               "pkg_name.*must be a length-one character")
  expect_error(make_obj(metadata = good_metadata(pkg_version = c("a", "b"))),
               "pkg_version.*must be a length-one character")
})

test_that("new_pkgaudit() refuses metadata that is not a list", {
  expect_error(
    new_pkgaudit(.empty_file_contexts(), .empty_patterns(), .empty_matches(),
                 .empty_coverage(), .empty_errors(), "not a list"),
    "'metadata' must be a list"
  )
})
