# good_metadata(), make_obj(), rich_obj() and errors_for() are defined in
# helper-pkgaudit.R.

# summary.pkgaudit() -----------------------------------------------------------
test_that("summary.pkgaudit() returns a summary.pkgaudit object", {
  s <- summary(rich_obj())
  expect_s3_class(s, "summary.pkgaudit")
  expect_named(s, c("file_contexts", "patterns", "matches", "coverage",
                    "errors", "metadata", "path", "phase"))
  expect_identical(s$metadata, good_metadata())
})

test_that("summary.pkgaudit() lists each file context once, in the order first seen", {
  s <- summary(rich_obj())
  expect_named(s$file_contexts, "file_context")
  expect_equal(s$file_contexts$file_context, c("src/Makevars", "configure"))
})

# Patterns section -------------------------------------------------------------
test_that("summary.pkgaudit() counts patterns by phase and rule", {
  s <- summary(rich_obj())
  # No code_context: it is how a finding's phases were derived, not a finding.
  expect_named(s$patterns, c("phase", "rule", "n", "attck"))

  at_load <- s$patterns[s$patterns$phase == "at_load", ]
  expect_equal(at_load$rule,  c("rcurl", "source"))
  expect_equal(at_load$n,     c(1L, 1L))
  expect_equal(at_load$attck, c("T1041", "T1059"))
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
  expect_equal(none$rule, "source")
  expect_equal(none$n,    1L)
})

test_that("summary.pkgaudit() orders patterns by phase, then rule", {
  s <- summary(rich_obj())
  # Lifecycle order, "none" last, and phases nothing runs in are omitted.
  expect_equal(unique(s$patterns$phase),
               c("at_build", "at_check", "at_install_src", "at_load", "none"))
  at_build <- s$patterns[s$patterns$phase == "at_build", ]
  expect_equal(at_build$rule, c("rcurl", "source"))
  # Two source() occurrences in different contexts share the phase and are
  # counted together; which contexts they sit in is in the patterns frame.
  expect_equal(at_build$n, c(1L, 2L))
})

# Matches section ----------------------------------------------------------
test_that("summary.pkgaudit() counts matches by phase and rule", {
  s <- summary(rich_obj())
  # Shaped as patterns is: what runs, and when. Which file is on the frame.
  expect_named(s$matches, c("phase", "rule", "n", "attck"))

  at_build <- s$matches[s$matches$phase == "at_build", ]
  expect_equal(at_build$rule,  c("curl", "wget"))
  # Three curl matches -- two in configure, one in src/Makevars -- counted
  # together now that the file is not part of the grouping.
  expect_equal(at_build$n,     c(3L, 1L))
  expect_equal(at_build$attck, c("T1041", "T1041"))
})

test_that("summary.pkgaudit() counts a match once per phase its file runs in", {
  s <- summary(rich_obj())
  # Four occurrences, each in the three phases that install the package.
  expect_equal(sum(s$matches$n), 12L)
  expect_equal(unique(s$matches$phase),
               c("at_build", "at_check", "at_install_src"))
})

test_that("summary.pkgaudit() gathers matches that run in no phase under 'none'", {
  obj <- rich_obj()
  obj$matches[, .phase_columns] <- FALSE
  s <- summary(obj)
  expect_equal(unique(s$matches$phase), "none")
  expect_equal(sum(s$matches$n), 4L)
})

test_that("summary.pkgaudit() renames the errors columns and keeps all four", {
  obj <- rich_obj(errors = errors_for(
    .error_row("find_file_contexts", NA_character_, "file_configure", "bad glob"),
    .error_row("parse_code", "R/bad.R", NA_character_, "unexpected ')'")
  ))
  s <- summary(obj)
  expect_named(s$errors, c("step", "file_context", "rule", "error"))
  expect_equal(s$errors$step,  c("find_file_contexts", "parse_code"))
  expect_equal(s$errors$file_context, c(NA, "R/bad.R"))
  expect_equal(s$errors$rule,   c("file_configure", NA))
  expect_equal(s$errors$error,  c("bad glob", "unexpected ')'"))
})

test_that("summary.pkgaudit() summarizes an object with no findings", {
  s <- summary(make_obj())
  expect_equal(nrow(s$file_contexts), 0L)
  expect_equal(nrow(s$patterns),      0L)
  expect_equal(nrow(s$matches),   0L)
  expect_equal(nrow(s$errors),        0L)
  expect_named(s$patterns,    c("phase", "rule", "n", "attck"))
  expect_named(s$matches, c("phase", "rule", "n", "attck"))
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
