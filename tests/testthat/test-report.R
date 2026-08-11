# Rendering: section order, table layout, and the shared width helpers.
# rich_obj() and errors_for() are defined in helper-pkgaudit.R.

test_that("print.summary.pkgaudit() writes every section in order", {
  lines <- capture.output(print(summary(rich_obj())))
  headers <- grep("^--- ", lines, value = TRUE)
  expect_match(headers, "^--- .+ -+$")
  expect_equal(sub(" -+$", "", headers),
               c("--- pkgaudit Summary", "--- R Patterns",
                 "--- Shell / Make Matches", "--- Coverage", "--- Errors"))
  # Three narrower than a terminal line, so a "#> " prefix still fits in 80.
  expect_true(all(nchar(headers) == 77L))
  expect_true(all(nchar(lines) <= 77L))
})

test_that("print.summary.pkgaudit() opens with the same metadata block as print.pkgaudit()", {
  obj     <- rich_obj()
  counts  <- format(obj)
  report  <- capture.output(print(summary(obj)))
  expect_identical(report[2:5], counts[2:5])
})

test_that("print.summary.pkgaudit() returns its input invisibly", {
  s <- summary(rich_obj())
  expect_output(res <- withVisible(print(s)), "^--- pkgaudit Summary")
  expect_false(res$visible)
  expect_identical(res$value, s)
})

test_that("print.summary.pkgaudit() renders the patterns table", {
  lines <- capture.output(print(summary(rich_obj())))
  # Character columns are left-aligned, the count right-aligned under its
  # header, and columns three spaces apart.
  expect_true(any(grepl("^phase +rule +n   attck$", lines)))
  expect_true(any(grepl("^at_load +source +1   T1059$", lines)))
  expect_true(any(grepl("^none +source +1   T1059$", lines)))
})

test_that("print.summary.pkgaudit() renders the matches table", {
  lines <- capture.output(print(summary(rich_obj())))
  expect_true(any(grepl("^phase +rule +n   attck$", lines)))
  expect_true(any(grepl("^at_install_src +curl +3   T1041$", lines)))
  expect_true(any(grepl("^at_build +wget +1   T1041$", lines)))
})

test_that("the two findings tables are laid out to the same widths", {
  lines <- capture.output(print(summary(rich_obj())))

  # Same columns, same positions: the two are meant to be read together, so a
  # rule name in one lands under a rule name in the other.
  headers <- grep("^phase +rule +n +attck$", lines, value = TRUE)
  expect_length(headers, 2L)
  expect_equal(headers[[1L]], headers[[2L]])

  # The widths come from both tables, not each from its own content: the
  # patterns table alone would set a narrower rule column than "curl" needs
  # once the matches table is taken into account.
  starts <- vapply(headers, function(h) regexpr("attck", h)[[1L]], integer(1L))
  expect_equal(starts[[1L]], starts[[2L]])
})

test_that("print.summary.pkgaudit() reports patterns before matches", {
  lines   <- capture.output(print(summary(rich_obj())))
  headers <- grep("^--- ", lines)
  expect_lt(grep("^--- R Patterns", lines), grep("^--- Shell / Make", lines))
})

test_that("print.summary.pkgaudit() omits the contexts, which stay on the object", {
  s     <- summary(rich_obj())
  lines <- capture.output(print(s))
  # The report has no Contexts section and names no context table.
  expect_false(any(grepl("^--- Contexts", lines)))
  expect_false(any(grepl("^file_context$", lines)))
  # It remains available programmatically.
  expect_equal(s$file_contexts$file_context, c("src/Makevars", "configure"))
})

test_that("print.summary.pkgaudit() honours the recorded path and an override", {
  obj <- rich_obj()
  expect_true(any(grepl("^Path:", capture.output(print(summary(obj))))))
  expect_false(any(grepl("^Path:",
                         capture.output(print(summary(obj, path = FALSE))))))
  # An explicit argument wins over what summary() recorded, either way.
  expect_false(any(grepl("^Path:",
                         capture.output(print(summary(obj), path = FALSE)))))
  expect_true(any(grepl("^Path:",
                        capture.output(print(summary(obj, path = FALSE),
                                             path = TRUE)))))
})

test_that("print.summary.pkgaudit() reports empty sections with a message", {
  lines <- capture.output(print(summary(make_obj())))
  expect_true(any(grepl("^No patterns were found\\.$", lines)))
  expect_true(any(grepl("^No matches were found\\.$", lines)))
})

# Errors section ---------------------------------------------------------------
test_that("the Errors section reports the all-clear when there are no errors", {
  lines <- capture.output(print(summary(rich_obj())))
  expect_true(any(grepl("^No exceptions were raised\\.$", lines)))
  expect_false(any(grepl("could not be", lines)))
})

test_that("the Errors section lists every error row with its step", {
  obj <- rich_obj(errors = errors_for(
    .error_row("find_file_contexts", NA_character_, "file_configure", "bad glob"),
    .error_row("parse_code", "R/bad.R", NA_character_, "unexpected ')'"),
    .error_row("find_patterns", "R/a.R", "system", "invalid xpath")
  ))
  lines <- capture.output(print(summary(obj)))
  # The table says where to look; the rule and the message stay in s$errors.
  expect_true(any(grepl("^step +file_context$", lines)))
  expect_false(any(grepl("invalid xpath", lines, fixed = TRUE)))
  # NA renders blank: a file-context rule names no script.
  expect_true(any(grepl("^find_file_contexts *$", lines)))
  expect_true(any(grepl("^parse_code +R/bad\\.R$", lines)))
  expect_true(any(grepl("^find_patterns +R/a\\.R$", lines)))
})

test_that(".column_width() needs nothing for a column a frame does not have", {
  expect_equal(.column_width("rule", NULL), 0L)
  # Otherwise the header and the widest value, with NA rendered as blank.
  expect_equal(.column_width("rule", c("system", NA)), 6L)
  expect_equal(.column_width("file_context", "R/f.R"), 12L)
})

test_that(".format_scanned() falls back rather than inventing a timestamp", {
  expect_equal(.format_scanned("2026-07-23T14:02:00Z"), "2026-07-23 14:02 UTC")
  expect_equal(.format_scanned(NA_character_), "<unknown>")
  expect_equal(.format_scanned(character(0L)),  "<unknown>")
  # Unparseable: the stored value is shown as-is rather than dropped.
  expect_equal(.format_scanned("last Tuesday"), "last Tuesday")
})
