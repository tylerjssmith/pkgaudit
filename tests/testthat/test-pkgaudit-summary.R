# good_metadata() and make_obj() are defined in helper-pkgaudit.R.

# A pkgaudit object with repeated and out-of-order findings, so the summary has
# something to de-duplicate, count, and sort.
rich_obj <- function(errors = .empty_errors(), metadata = good_metadata()) {
  # The phases each finding would carry after resolution: the file and code
  # contexts from their rules, the patterns from the code context they sit in.
  installed <- phase_values("at_build", "at_check", "at_install_src")
  loaded    <- phase_values("at_build", "at_check", "at_install_src", "at_load")
  attached  <- phase_values("at_build", "at_check", "at_install_src",
                            "at_attach")
  uncalled  <- phase_values()

  fc <- .empty_file_contexts()
  fc[1L, ] <- c(list("src_makevars", "src/Makevars", "m"), installed)
  fc[2L, ] <- c(list("configure",    "configure",    "m"), installed)
  fc[3L, ] <- c(list("src_makevars", "src/Makevars", "m"), installed)

  cc <- .empty_code_contexts()
  cc[1L, ] <- c(list("onLoad_base",   "R/zzz.R", 1L, 1L, "m"), loaded)
  cc[2L, ] <- c(list("onAttach_base", "R/zzz.R", 9L, 1L, "m"), attached)
  cc[3L, ] <- c(list("onLoad_base",   "R/aaa.R", 4L, 1L, "m"), loaded)

  pt <- .empty_patterns()
  pt[1L, ] <- c(list("source", "R/zzz.R", 1L, 1L, "m",
                     "T1059", "onLoad_base"), loaded)
  pt[2L, ] <- c(list("rcurl",  "R/zzz.R", 2L, 1L, "m",
                     "T1041", "onLoad_base"), loaded)
  pt[3L, ] <- c(list("source", "R/aaa.R", 3L, 1L, "m",
                     "T1059", "Top-level"), installed)
  pt[4L, ] <- c(list("source", "R/aaa.R", 7L, 1L, "m",
                     "T1059", "Other"), uncalled)

  # An expression takes its phases from the file context it sits in, so all of
  # these are the phases that install the package.
  ex <- .empty_expressions()
  ex[1L, ] <- c(list("curl", "configure",    3L,  1L, "m", "T1041"), installed)
  ex[2L, ] <- c(list("curl", "configure",    3L, 20L, "m", "T1041"), installed)
  ex[3L, ] <- c(list("wget", "configure",    5L,  1L, "m", "T1041"), installed)
  ex[4L, ] <- c(list("curl", "src/Makevars", 2L, 11L, "m", "T1041"), installed)

  new_pkgaudit(fc, cc, pt, ex, errors, metadata)
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
  expect_named(s, c("file_contexts", "code_contexts", "patterns",
                    "expressions", "errors", "metadata", "path"))
  expect_identical(s$metadata, good_metadata())
})

test_that("summary.pkgaudit() lists each context once, in the order first seen", {
  s <- summary(rich_obj())
  expect_named(s$file_contexts, "file_context")
  expect_named(s$code_contexts, "code_context")
  expect_equal(s$file_contexts$file_context, c("src/Makevars", "configure"))
  expect_equal(s$code_contexts$code_context, c("onLoad_base", "onAttach_base"))
})

# Patterns section -------------------------------------------------------------
test_that("summary.pkgaudit() counts patterns by phase, context, and rule", {
  s <- summary(rich_obj())
  expect_named(s$patterns, c("phase", "code_context", "rule", "n", "attck"))

  at_load <- s$patterns[s$patterns$phase == "at_load", ]
  expect_equal(at_load$code_context, c("onLoad_base", "onLoad_base"))
  expect_equal(at_load$rule,         c("rcurl", "source"))
  expect_equal(at_load$n,            c(1L, 1L))
  expect_equal(at_load$attck,        c("T1041", "T1059"))
})

test_that("summary.pkgaudit() counts an occurrence once per phase it runs in", {
  s <- summary(rich_obj())
  # The two .onLoad() patterns run in four phases each and the top-level one in
  # three, so a phase-blind total would be 4 rather than the 11 counted here.
  expect_equal(sum(s$patterns$n[s$patterns$phase != "none"]), 11L)
  expect_equal(sum(s$patterns$n[s$patterns$phase == "at_build"]), 3L)
  expect_equal(sum(s$patterns$n[s$patterns$phase == "at_load"]),  2L)
})

test_that("summary.pkgaudit() gathers patterns that run in no phase under 'none'", {
  s <- summary(rich_obj())
  none <- s$patterns[s$patterns$phase == "none", ]
  # The one pattern inside an ordinary function; nothing else.
  expect_equal(nrow(none), 1L)
  expect_equal(none$code_context, "Other")
  expect_equal(none$rule,         "source")
  expect_equal(none$n,            1L)
})

test_that("summary.pkgaudit() orders patterns by phase, then context, then rule", {
  s <- summary(rich_obj())
  # Lifecycle order, "none" last, and phases nothing runs in are omitted.
  expect_equal(unique(s$patterns$phase),
               c("at_build", "at_check", "at_install_src", "at_load", "none"))
  at_build <- s$patterns[s$patterns$phase == "at_build", ]
  expect_equal(at_build$code_context,
               c("Top-level", "onLoad_base", "onLoad_base"))
  expect_equal(at_build$rule, c("source", "rcurl", "source"))
})

# Expressions section ----------------------------------------------------------
test_that("summary.pkgaudit() counts expressions by phase, file context, and rule", {
  s <- summary(rich_obj())
  expect_named(s$expressions, c("phase", "file_context", "rule", "n", "attck"))

  at_build <- s$expressions[s$expressions$phase == "at_build", ]
  expect_equal(at_build$file_context, c("configure", "configure", "src/Makevars"))
  expect_equal(at_build$rule,         c("curl", "wget", "curl"))
  # Two curl matches on one line of configure are two occurrences.
  expect_equal(at_build$n,            c(2L, 1L, 1L))
  expect_equal(at_build$attck,        c("T1041", "T1041", "T1041"))
})

test_that("summary.pkgaudit() counts an expression once per phase its file runs in", {
  s <- summary(rich_obj())
  # Four occurrences, each in the three phases that install the package.
  expect_equal(sum(s$expressions$n), 12L)
  expect_equal(unique(s$expressions$phase),
               c("at_build", "at_check", "at_install_src"))
})

test_that("summary.pkgaudit() gathers expressions that run in no phase under 'none'", {
  obj <- rich_obj()
  obj$expressions[, .phase_columns] <- FALSE
  s <- summary(obj)
  expect_equal(unique(s$expressions$phase), "none")
  expect_equal(sum(s$expressions$n), 4L)
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
  expect_equal(nrow(s$expressions),   0L)
  expect_equal(nrow(s$errors),        0L)
  expect_named(s$patterns,    c("phase", "code_context", "rule", "n", "attck"))
  expect_named(s$expressions, c("phase", "file_context", "rule", "n", "attck"))
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
               c("--- pkgaudit Summary", "--- R Patterns",
                 "--- Shell / Make Expressions", "--- Errors"))
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
  expect_true(any(grepl("^phase +code_context +rule +n   attck$", lines)))
  expect_true(any(grepl("^at_load +onLoad_base +source +1   T1059$", lines)))
  expect_true(any(grepl("^none +Other +source +1   T1059$", lines)))
})

test_that("print.summary.pkgaudit() renders the expressions table", {
  lines <- capture.output(print(summary(rich_obj())))
  expect_true(any(grepl("^phase +file_context +rule +n   attck$", lines)))
  expect_true(any(grepl("^at_install_src +configure +curl +2   T1041$", lines)))
  expect_true(any(grepl("^at_build +src/Makevars +curl +1   T1041$", lines)))
})

test_that("print.summary.pkgaudit() reports patterns before expressions", {
  lines   <- capture.output(print(summary(rich_obj())))
  headers <- grep("^--- ", lines)
  expect_lt(grep("^--- R Patterns", lines), grep("^--- Shell / Make", lines))
})

test_that("print.summary.pkgaudit() omits the contexts, which stay on the object", {
  s     <- summary(rich_obj())
  lines <- capture.output(print(s))
  # The report has no Contexts section and names no context table.
  expect_false(any(grepl("^--- Contexts", lines)))
  expect_false(any(grepl("^code_context$", lines)))
  expect_false(any(grepl("^onAttach_base$", lines)))
  # They remain available programmatically.
  expect_equal(s$file_contexts$file_context, c("src/Makevars", "configure"))
  expect_equal(s$code_contexts$code_context, c("onLoad_base", "onAttach_base"))
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
  expect_true(any(grepl("^No expressions were found\\.$", lines)))
})

# Errors section ---------------------------------------------------------------
test_that("the Errors section reports the all-clear when there are no errors", {
  lines <- capture.output(print(summary(rich_obj())))
  expect_true(any(grepl("^No exceptions were raised\\.$", lines)))
  expect_false(any(grepl("could not be", lines)))
})

test_that("the Errors section lists every error row with its stage", {
  obj <- rich_obj(errors = errors_for(
    .error_row("find_file_contexts", NA_character_, "file_configure", "bad glob"),
    .error_row("parse_script", "R/bad.R", NA_character_, "unexpected ')'"),
    .error_row("find_patterns", "R/a.R", "system", "invalid xpath")
  ))
  lines <- capture.output(print(summary(obj)))
  expect_true(any(grepl("^stage +script +rule +error$", lines)))
  # NA renders blank: the file-context rule names no script, the parse failure
  # names no rule.
  expect_true(any(grepl("^find_file_contexts +file_configure +bad glob$", lines)))
  expect_true(any(grepl("^parse_script +R/bad\\.R +unexpected", lines)))
  expect_true(any(grepl("^find_patterns +R/a\\.R +system +invalid xpath$",
                        lines)))
})

test_that("the Errors section notes what each stage's failures cost the scan", {
  obj <- rich_obj(errors = errors_for(
    .error_row("find_file_contexts", NA_character_, "file_configure", "bad glob"),
    .error_row("parse_script", "R/bad.R",   NA_character_, "unexpected ')'"),
    .error_row("parse_script", "R/worse.R", NA_character_, "invalid multibyte"),
    .error_row("find_code_contexts", "R/a.R", "onLoad_base", "invalid xpath"),
    .error_row("find_patterns",      "R/a.R", "system",      "invalid xpath")
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
    .error_row("find_patterns", "R/a.R", "system", "invalid xpath"),
    .error_row("find_patterns", "R/a.R", "source", "invalid xpath")
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

test_that("the Errors notes separate an unreadable file from a failed expression rule", {
  # find_regex records both without a rule (the file was never read) and with
  # one (the rule could not be evaluated); each gets its own note.
  obj <- rich_obj(errors = errors_for(
    .error_row("find_regex", "configure",    NA_character_, "too large"),
    .error_row("find_regex", "src/Makevars", "curl",        "invalid regex")
  ))
  notes <- paste(capture.output(print(summary(obj))), collapse = " ")
  expect_match(notes,
    "1 shell or Make-like file could not be read in full and was not completely scanned\\.")
  expect_match(notes,
    "1 expression rule could not be evaluated in 1 shell or Make-like file\\.")
})

test_that("the Errors notes for expressions agree in number", {
  obj <- rich_obj(errors = errors_for(
    .error_row("find_regex", "configure",    "curl", "invalid regex"),
    .error_row("find_regex", "src/Makevars", "curl", "invalid regex"),
    .error_row("find_regex", "src/Makevars", "wget", "invalid regex")
  ))
  expect_match(
    paste(capture.output(print(summary(obj))), collapse = " "),
    "2 expression rules could not be evaluated in 2 shell or Make-like files\\. .*in these files\\."
  )
})

test_that("the Errors section counts an unrecognized stage rather than dropping it", {
  obj <- rich_obj(errors = errors_for(
    .error_row("some_new_stage", "R/a.R", NA_character_, "boom")
  ))
  notes <- paste(capture.output(print(summary(obj))), collapse = " ")
  expect_match(notes, "1 error occurred during some_new_stage\\.")
})
