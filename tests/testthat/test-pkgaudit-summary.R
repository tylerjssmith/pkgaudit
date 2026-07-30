# good_metadata() and make_obj() are defined in helper-pkgaudit.R.

# A pkgaudit object with repeated and out-of-order findings, so the summary has
# something to de-duplicate, count, and sort.
rich_obj <- function(errors = .empty_errors(), metadata = good_metadata()) {
  # The phases each finding would carry after resolution: the file and code
  # contexts from their rules, the patterns from the code context they sit in.
  installed <- phase_values("at_build", "at_check", "at_install_src")
  loaded    <- phase_values("at_build", "at_check", "at_install_src", "on_load")
  attached  <- phase_values("at_build", "at_check", "at_install_src",
                            "on_attach")
  uncalled  <- phase_values()

  fc <- .empty_file_contexts()
  fc[1L, ] <- c(list("src_makevars_file", "src/Makevars", "m"), installed)
  fc[2L, ] <- c(list("configure_file",    "configure",    "m"), installed)
  fc[3L, ] <- c(list("src_makevars_file", "src/Makevars", "m"), installed)

  cc <- .empty_code_contexts()
  cc[1L, ] <- c(list("onload_code",   "R/zzz.R", 1L, 1L, "m"), loaded)
  cc[2L, ] <- c(list("onattach_code", "R/zzz.R", 9L, 1L, "m"), attached)
  cc[3L, ] <- c(list("onload_code",   "R/aaa.R", 4L, 1L, "m"), loaded)

  pt <- .empty_patterns()
  pt[1L, ] <- c(list("source_pattern", "R/zzz.R", 1L, 1L, "m",
                     "T1059 T1195.002", "onload_code"), loaded)
  pt[2L, ] <- c(list("rcurl_pattern",  "R/zzz.R", 2L, 1L, "m",
                     "T1041 T1195.002", "onload_code"), loaded)
  pt[3L, ] <- c(list("source_pattern", "R/aaa.R", 3L, 1L, "m",
                     "T1059 T1195.002", "Top-level"), installed)
  pt[4L, ] <- c(list("source_pattern", "R/aaa.R", 7L, 1L, "m",
                     "T1059 T1195.002", "Other"), uncalled)

  new_pkgaudit(fc, cc, pt, errors, metadata)
}

# Errors for the given stages, one row each, with the fields that stage sets.
errors_for <- function(...) {
  rows <- list(...)
  do.call(rbind, c(list(.empty_errors()), rows))
}

# summary.pkgaudit() -----------------------------------------------------------
test_that("summary.pkgaudit() returns a summary.pkgaudit object", {
  s <- summary(rich_obj())
  expect_s3_class(s, "summary.pkgaudit")
  expect_named(s, c("phases", "file_contexts", "code_contexts", "patterns",
                    "errors", "metadata", "path"))
  expect_identical(s$metadata, good_metadata())
})

test_that("summary.pkgaudit() lists each context once, in the order first seen", {
  s <- summary(rich_obj())
  expect_named(s$file_contexts, "file_context")
  expect_named(s$code_contexts, "rule")
  expect_equal(s$file_contexts$file_context, c("src/Makevars", "configure"))
  expect_equal(s$code_contexts$rule, c("onload_code", "onattach_code"))
})

test_that("summary.pkgaudit() counts patterns by name and carries their attck", {
  s <- summary(rich_obj())
  expect_named(s$patterns, c("rule", "occurrences", "attck"))
  # Sorted by rule name, not by the order encountered.
  expect_equal(s$patterns$rule,        c("rcurl_pattern", "source_pattern"))
  expect_equal(s$patterns$occurrences, c(1L, 3L))
  expect_equal(s$patterns$attck, c("T1041 T1195.002", "T1059 T1195.002"))
  expect_equal(sum(s$patterns$occurrences), nrow(rich_obj()$patterns))
})

# Phases section ---------------------------------------------------------------
test_that("summary.pkgaudit() counts findings by phase, one row per phase", {
  s <- summary(rich_obj())
  expect_named(s$phases,
               c("phase", "file_contexts", "code_contexts", "patterns"))
  expect_equal(s$phases$phase, c(.phase_columns, "none"))

  count <- function(frame, phase) s$phases[[frame]][match(phase, s$phases$phase)]
  expect_equal(count("file_contexts", "at_install_src"), 3L)
  expect_equal(count("code_contexts", "on_load"),        2L)
  expect_equal(count("code_contexts", "on_attach"),      1L)
  expect_equal(count("patterns",      "at_build"),       3L)
  expect_equal(count("patterns",      "on_load"),        2L)
  # A phase nothing runs in is still reported, as zero.
  expect_equal(count("file_contexts", "at_autoconf"),    0L)
})

test_that("summary.pkgaudit() counts findings that run in no phase under 'none'", {
  s <- summary(rich_obj())
  none <- function(frame) s$phases[[frame]][match("none", s$phases$phase)]
  # The one pattern inside an ordinary function; nothing else.
  expect_equal(none("patterns"),      1L)
  expect_equal(none("file_contexts"), 0L)
  expect_equal(none("code_contexts"), 0L)
})

test_that("summary.pkgaudit() reports zero for every phase of an empty object", {
  s <- summary(make_obj())
  expect_equal(nrow(s$phases), length(.phase_columns) + 1L)
  expect_true(all(s$phases$file_contexts == 0L))
  expect_true(all(s$phases$code_contexts == 0L))
  expect_true(all(s$phases$patterns      == 0L))
})

test_that("summary.pkgaudit() renames the errors columns and keeps all four", {
  obj <- rich_obj(errors = errors_for(
    .error_row("find_file_contexts", NA_character_, "file_configure", "bad glob"),
    .error_row("parse_script", "R/bad.R", NA_character_, "unexpected ')'")
  ))
  s <- summary(obj)
  expect_named(s$errors, c("stage", "script", "rule", "error"))
  expect_equal(s$errors$stage,  c("find_file_contexts", "parse_script"))
  expect_equal(s$errors$script, c(NA, "R/bad.R"))
  expect_equal(s$errors$rule,   c("file_configure", NA))
  expect_equal(s$errors$error,  c("bad glob", "unexpected ')'"))
})

test_that("summary.pkgaudit() summarizes an object with no findings", {
  s <- summary(make_obj())
  expect_equal(nrow(s$file_contexts), 0L)
  expect_equal(nrow(s$code_contexts), 0L)
  expect_equal(nrow(s$patterns),      0L)
  expect_equal(nrow(s$errors),        0L)
  expect_named(s$patterns, c("rule", "occurrences", "attck"))
})

test_that("summary.pkgaudit() records the path choice", {
  expect_true(summary(rich_obj())$path)
  expect_false(summary(rich_obj(), path = FALSE)$path)
})

# print.summary.pkgaudit() -----------------------------------------------------
test_that("print.summary.pkgaudit() writes every section in order", {
  lines <- capture.output(print(summary(rich_obj())))
  headers <- grep("^--- ", lines, value = TRUE)
  expect_match(headers, "^--- .+ -+$")
  expect_equal(sub(" -+$", "", headers),
               c("--- pkgaudit Summary", "--- Findings by Phase",
                 "--- File Contexts", "--- Code Contexts",
                 "--- Patterns", "--- Errors", "--- Notes"))
  expect_true(all(nchar(headers) == 80L))
  expect_true(any(grepl(
    "^pkgaudit is intended to assist with manual review, not replace it\\.$",
    lines
  )))
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

test_that("print.summary.pkgaudit() renders the finding tables", {
  lines <- capture.output(print(summary(rich_obj())))
  expect_true(any(grepl("^file_context$", lines)))
  expect_true(any(grepl("^src/Makevars$", lines)))
  expect_true(any(grepl("^rule$", lines)))
  expect_true(any(grepl("^onattach_code$", lines)))
  # Character columns are left-aligned, the count right-aligned under its header.
  expect_true(any(grepl("^rule +occurrences attck$", lines)))
  expect_true(any(grepl("^source_pattern +3 T1059 T1195\\.002$", lines)))
})

test_that("print.summary.pkgaudit() renders the phase table", {
  lines <- capture.output(print(summary(rich_obj())))
  expect_true(any(grepl("^phase +file_contexts code_contexts patterns$", lines)))
  expect_true(any(grepl("^at_install_src +3 +3 +3$", lines)))
  expect_true(any(grepl("^none +0 +0 +1$", lines)))
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
  expect_true(any(grepl("^No file contexts were found\\.$", lines)))
  expect_true(any(grepl("^No code contexts were found\\.$", lines)))
  expect_true(any(grepl("^No patterns were found\\.$", lines)))
})

# Errors section ---------------------------------------------------------------
test_that("the Errors section reports the all-clear when there are no errors", {
  lines <- capture.output(print(summary(rich_obj())))
  expect_true(any(grepl("^All R scripts were successfully parsed\\.$", lines)))
  expect_false(any(grepl("could not be", lines)))
})

test_that("the Errors section lists every error row with its stage", {
  obj <- rich_obj(errors = errors_for(
    .error_row("find_file_contexts", NA_character_, "file_configure", "bad glob"),
    .error_row("parse_script", "R/bad.R", NA_character_, "unexpected ')'"),
    .error_row("find_patterns", "R/a.R", "system_pattern", "invalid xpath")
  ))
  lines <- capture.output(print(summary(obj)))
  expect_true(any(grepl("^stage +script +rule +error$", lines)))
  # NA renders blank: the file-context rule names no script, the parse failure
  # names no rule.
  expect_true(any(grepl("^find_file_contexts +file_configure bad glob$", lines)))
  expect_true(any(grepl("^parse_script +R/bad\\.R +unexpected", lines)))
  expect_true(any(grepl("^find_patterns +R/a\\.R +system_pattern invalid xpath$",
                        lines)))
})

test_that("the Errors section notes what each stage's failures cost the scan", {
  obj <- rich_obj(errors = errors_for(
    .error_row("find_file_contexts", NA_character_, "file_configure", "bad glob"),
    .error_row("parse_script", "R/bad.R",   NA_character_, "unexpected ')'"),
    .error_row("parse_script", "R/worse.R", NA_character_, "invalid multibyte"),
    .error_row("find_code_contexts", "R/a.R", "onload_code",    "invalid xpath"),
    .error_row("find_patterns",      "R/a.R", "system_pattern", "invalid xpath")
  ))
  notes <- paste(capture.output(print(summary(obj))), collapse = " ")
  expect_match(notes, "1 file-context rule could not be evaluated\\.")
  expect_match(notes,
    "2 R scripts could not be parsed for code contexts or patterns, and were not scanned\\.")
  expect_match(notes, "1 code-context rule could not be evaluated in 1 R script\\.")
  expect_match(notes, "1 pattern rule could not be evaluated in 1 R script\\.")
})

test_that("the Errors notes count distinct scripts and rules, and agree in number", {
  # One script failing two pattern rules is 2 rules in 1 script, not 2 scripts.
  two_rules <- rich_obj(errors = errors_for(
    .error_row("find_patterns", "R/a.R", "system_pattern", "invalid xpath"),
    .error_row("find_patterns", "R/a.R", "source_pattern", "invalid xpath")
  ))
  expect_match(
    paste(capture.output(print(summary(two_rules))), collapse = " "),
    "2 pattern rules could not be evaluated in 1 R script\\. .*in that script\\."
  )

  one_script <- rich_obj(errors = errors_for(
    .error_row("parse_script", "R/bad.R", NA_character_, "unexpected ')'")
  ))
  expect_match(
    paste(capture.output(print(summary(one_script))), collapse = " "),
    "1 R script could not be parsed .* and was not scanned\\. .*contents of that script\\."
  )
})

test_that("the Errors section counts an unrecognized stage rather than dropping it", {
  obj <- rich_obj(errors = errors_for(
    .error_row("some_new_stage", "R/a.R", NA_character_, "boom")
  ))
  notes <- paste(capture.output(print(summary(obj))), collapse = " ")
  expect_match(notes, "1 error occurred during some_new_stage\\.")
})
