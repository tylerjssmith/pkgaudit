# good_metadata() and make_obj() are defined in helper-pkgaudit.R.

# new_pkgaudit() ---------------------------------------------------------------
test_that("new_pkgaudit() accepts a well-formed object", {
  obj <- make_obj()
  expect_s3_class(obj, "pkgaudit")
  expect_named(obj, c("file_contexts", "code_contexts", "patterns", "errors",
                      "metadata"))
})

test_that("new_pkgaudit() errors when a data frame is not a data frame", {
  expect_error(
    new_pkgaudit("nope", .empty_code_contexts(), .empty_patterns(),
                 .empty_errors(), good_metadata()),
    "file_contexts.*must be a data frame"
  )
})

test_that("new_pkgaudit() errors on wrong data-frame columns", {
  bad <- .empty_file_contexts()
  bad$message <- NULL
  expect_error(new_pkgaudit(bad, .empty_code_contexts(), .empty_patterns(),
                            .empty_errors(), good_metadata()),
               "file_contexts.*missing: message")
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

# format.pkgaudit() ------------------------------------------------------------
test_that("format.pkgaudit() returns a character vector with the expected lines", {
  obj   <- make_obj(n_file = 4L, n_code = 6L, n_pat = 17L, n_err = 0L)
  lines <- format(obj)
  expect_type(lines, "character")
  expect_match(lines[[1L]], "^--- pkgaudit -+$")
  expect_true(any(grepl("^Package:\\s+foo v0.1.0 \\(source directory\\)$", lines)))
  expect_true(any(grepl("^File contexts:\\s+4$", lines)))
  expect_true(any(grepl("^Code contexts:\\s+6$", lines)))
  expect_true(any(grepl("^Patterns:\\s+17$", lines)))
  # Scanned line renders the ISO value as YYYY-MM-DD HH:MM UTC.
  expect_true(any(grepl("^Scanned:\\s+2026-07-23 14:02 UTC with pkgaudit 0.3.0, rules v0.1.0$", lines)))
})

test_that("format.pkgaudit() counts match the data-frame row counts", {
  obj   <- make_obj(n_file = 2L, n_code = 3L, n_pat = 5L, n_err = 1L)
  lines <- format(obj)
  val <- function(label) sub(paste0("^", label, "\\s+"), "",
                             grep(paste0("^", label), lines, value = TRUE))
  expect_equal(val("File contexts:"), as.character(nrow(obj$file_contexts)))
  expect_equal(val("Code contexts:"), as.character(nrow(obj$code_contexts)))
  expect_equal(val("Patterns:"),      as.character(nrow(obj$patterns)))
})

test_that("format.pkgaudit() includes Path only when path = TRUE", {
  obj <- make_obj()
  expect_true(any(grepl("^Path:", format(obj, path = TRUE))))
  expect_false(any(grepl("^Path:", format(obj, path = FALSE))))
})

test_that("format.pkgaudit() marks incomplete coverage only when errors > 0", {
  with_err <- format(make_obj(n_err = 2L))
  no_err   <- format(make_obj(n_err = 0L))
  expect_true(any(grepl("^Errors:\\s+2   \\(coverage incomplete\\)$", with_err)))
  expect_true(any(grepl("^Errors:\\s+0$", no_err)))
  expect_false(any(grepl("coverage incomplete", no_err)))
})

test_that("format.pkgaudit() renders NA metadata values uniformly as <unknown>", {
  obj <- make_obj(metadata = good_metadata(
    pkg_name               = NA_character_,
    pkg_version            = NA_character_,
    pkg_path               = NA_character_,
    pkg_sha256             = NA_character_,
    pkgaudit_version       = NA_character_,
    pkgaudit_rules_version = NA_character_
  ))
  lines <- format(obj)
  expect_true(any(grepl("^Path:\\s+<unknown>$", lines)))
  expect_true(any(grepl("^SHA-256:\\s+<unknown>$", lines)))
  expect_true(any(grepl("^Package:\\s+<unknown> \\(source directory\\)$", lines)))
  expect_true(any(grepl("with pkgaudit <unknown>, rules v<unknown>$", lines)))
})

test_that("format.pkgaudit() shows the tarball/directory kind", {
  expect_true(any(grepl("\\(source tarball\\)",
                        format(make_obj(metadata = good_metadata(pkg_is_tarball = TRUE))))))
  expect_true(any(grepl("\\(source directory\\)",
                        format(make_obj(metadata = good_metadata(pkg_is_tarball = FALSE))))))
})

# print.pkgaudit() -------------------------------------------------------------
test_that("print.pkgaudit() writes the formatted lines and returns input invisibly", {
  obj <- make_obj()
  # expect_output captures stdout (keeping the test run quiet) and confirms the
  # formatted output is written; withVisible confirms the return is invisible.
  expect_output(res <- withVisible(print(obj)), "^--- pkgaudit")
  expect_false(res$visible)
  expect_identical(res$value, obj)
})
