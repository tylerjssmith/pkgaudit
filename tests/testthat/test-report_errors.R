# The notes printed under the Errors table, which say what each step's
# failures cost the scan. rich_obj() and errors_for() are in helper-pkgaudit.R.

test_that("the Errors section notes what each step's failures cost the scan", {
  obj <- rich_obj(errors = errors_for(
    .error_row("find_file_contexts", NA_character_, "file_configure", "bad glob"),
    .error_row("parse_code", "R/bad.R",   NA_character_, "unexpected ')'"),
    .error_row("parse_code", "R/worse.R", NA_character_, "invalid multibyte"),
    .error_row("find_code_contexts", "R/a.R", "onLoad_base", "invalid xpath"),
    .error_row("find_patterns",      "R/a.R", "system",      "invalid xpath")
  ))
  notes <- paste(capture.output(print(summary(obj))), collapse = " ")
  expect_match(notes, "1 file-context rule could not be evaluated\\.")
  expect_match(notes,
    "2 files could not be parsed and were not scanned\\.")
  expect_match(notes, "1 code-context rule could not be evaluated in 1 R script\\.")
  expect_match(notes, "1 pattern rule could not be evaluated in 1 file\\.")
})

test_that("the Errors notes count distinct scripts and rules, and agree in number", {
  # One script failing two pattern rules is 2 rules in 1 script, not 2 scripts.
  two_rules <- rich_obj(errors = errors_for(
    .error_row("find_patterns", "R/a.R", "system", "invalid xpath"),
    .error_row("find_patterns", "R/a.R", "source", "invalid xpath")
  ))
  expect_match(
    paste(capture.output(print(summary(two_rules))), collapse = " "),
    "2 pattern rules could not be evaluated in 1 file\\. .*in that file\\."
  )

  one_script <- rich_obj(errors = errors_for(
    .error_row("parse_code", "R/bad.R", NA_character_, "unexpected ')'")
  ))
  expect_match(
    paste(capture.output(print(summary(one_script))), collapse = " "),
    "1 file could not be parsed and was not scanned\\. .*contents of that file\\."
  )
})

test_that("the Errors notes separate an unreadable file from a failed match rule", {
  # Reading and matching are separate steps, so a file that could not be read
  # is never reported as a rule that failed.
  obj <- rich_obj(errors = errors_for(
    .error_row("read_code",  "configure",    NA_character_, "too large"),
    .error_row("find_matches", "src/Makevars", "curl",        "invalid regex")
  ))
  notes <- paste(capture.output(print(summary(obj))), collapse = " ")
  expect_match(notes,
    "1 file could not be read in full and was not completely scanned\\.")
  expect_match(notes,
    "1 match rule could not be evaluated in 1 shell or Make-like file\\.")
})

test_that("the Errors notes report an incompletely read help file", {
  obj <- rich_obj(errors = errors_for(
    .error_row("extract_Rd_code", "man/f.Rd", NA_character_,
               "unexpected END_OF_INPUT")
  ))
  expect_match(
    paste(capture.output(print(summary(obj))), collapse = " "),
    "1 help file could not be read in full, so the R code in it may be incomplete\\."
  )
})

test_that("the Errors notes for matches agree in number", {
  obj <- rich_obj(errors = errors_for(
    .error_row("find_matches", "configure",    "curl", "invalid regex"),
    .error_row("find_matches", "src/Makevars", "curl", "invalid regex"),
    .error_row("find_matches", "src/Makevars", "wget", "invalid regex")
  ))
  expect_match(
    paste(capture.output(print(summary(obj))), collapse = " "),
    "2 match rules could not be evaluated in 2 shell or Make-like files\\. .*in these files\\."
  )
})

test_that("the Errors section counts an unrecognized step rather than dropping it", {
  obj <- rich_obj(errors = errors_for(
    .error_row("some_new_stage", "R/a.R", NA_character_, "boom")
  ))
  notes <- paste(capture.output(print(summary(obj))), collapse = " ")
  expect_match(notes, "1 error occurred during some_new_stage\\.")
})

# Rd macro guidance ------------------------------------------------------------
# An unexpandable macro is not a file that could not be read: the file was read
# in full, and only the code the macro produces is missing. Every provider named
# below expands to a \Sexpr carrying a real call, so this is lost coverage
# rather than a cosmetic warning.

# .error_notes() returns wrapped lines with a blank between notes, so a note is
# matched against the joined text and counted by the blank separators.
notes_text <- function(errors) paste(.error_notes(errors), collapse = " ")
macro_errors <- function(...) {
  msgs <- c(...)
  data.frame(step = rep("extract_Rd_code", length(msgs)),
             script = paste0("man/", seq_along(msgs), ".Rd"),
             rule = NA_character_, error = msgs, stringsAsFactors = FALSE)
}

test_that("an unexpandable macro is reported as lost coverage, with the fix", {
  note <- notes_text(macro_errors("/p/a.Rd:1: unknown macro '\\insertRef'"))
  expect_match(note, "could not be expanded")
  expect_match(note, "installing Rdpack would recover it", fixed = TRUE)
  # Not the wrong description: the file itself was read fine.
  expect_false(grepl("could not be read in full", note))
})

test_that("providers from several packages are all named", {
  note <- notes_text(macro_errors(
    "/p/a.Rd:1: unknown macro '\\insertRef'",
    "/p/b.Rd:2: unknown macro '\\lifecycle'",
    "/p/c.Rd:3: unknown macro '\\mjseqn'"
  ))
  expect_match(note, "Rdpack, lifecycle and mathjaxr", fixed = TRUE)
})

# The macro provider is looked up by macro name against a fixed list, never
# taken from the audited package's RdMacros field. That field is chosen by the
# package under audit, so echoing it would let a hostile package have pkgaudit
# tell the analyst to install something of its choosing.
test_that("an unrecognised macro is counted but never suggested as an install", {
  note <- notes_text(macro_errors("/p/a.Rd:1: unknown macro '\\evilPayload'"))
  expect_match(note, "1 help file used Rd macros", fixed = TRUE)
  expect_false(grepl("installing", note))
  expect_false(grepl("evilPayload", note))
})

test_that("macro and parse failures are reported as the two different things", {
  notes <- notes_text(macro_errors(
    "/p/a.Rd:1: unknown macro '\\insertRef'",
    "/p/b.Rd:2: unexpected END_OF_INPUT"
  ))
  expect_match(notes, "1 help file used Rd macros that could not be expanded")
  expect_match(notes, "1 help file could not be read in full")
})

# phase filtering --------------------------------------------------------------
# The summary is expanded by phase before it is returned, so it cannot be subset
# afterwards -- filtering has to happen here or not at all.

test_that("summary() reports every phase by default", {
  s <- summary(rich_obj())
  expect_null(s$phase)
  expect_true(all(c("at_build", "at_load", "none") %in% s$patterns$phase))
})

test_that("phase restricts the report to the phases named", {
  s <- summary(rich_obj(), phase = "at_load")
  expect_equal(unique(s$patterns$phase), "at_load")
  expect_equal(unique(s$matches$phase), character(0))

  two <- summary(rich_obj(), phase = c("at_load", "at_build"))
  expect_setequal(unique(two$patterns$phase), c("at_load", "at_build"))
})

test_that("phase accepts none, for code that ships but runs at no phase", {
  s <- summary(rich_obj(), phase = "none")
  expect_equal(unique(s$patterns$phase), "none")
  expect_true(all(s$patterns$code_context == "Other"))
})

# An unknown phase matching nothing would render as a clean scan.
test_that("an unrecognised phase is refused, not silently empty", {
  expect_error(summary(rich_obj(), phase = "at_lod"), "unknown phase")
  expect_error(summary(rich_obj(), phase = 1L), "character vector")
  expect_error(summary(rich_obj(), phase = character(0)), "character vector")
  expect_error(summary(rich_obj(), phase = NA_character_), "character vector")
})

# A filtered report that looked unfiltered could be read as a clean scan of a
# package whose findings are simply in a phase nobody asked for.
test_that("a filtered report names its phases in the header", {
  filtered <- paste(capture.output(print(summary(rich_obj(), phase = "at_load"))),
                    collapse = " ")
  expect_match(filtered, "Phases:\\s+at_load")

  full <- paste(capture.output(print(summary(rich_obj()))), collapse = " ")
  expect_false(grepl("Phases:", full))
})
