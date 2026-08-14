# format(), print() and summary() -- what they return. How the summary is
# rendered is test-report.R; the error notes under it are test-report_errors.R.

# format.pkgaudit() ------------------------------------------------------------
test_that("format.pkgaudit() returns a character vector with the expected lines", {
  obj   <- make_obj(n_file = 4L, n_pat = 17L, n_expr = 3L, n_err = 0L)
  lines <- format(obj)
  expect_type(lines, "character")
  expect_match(lines[[1L]], "^--- pkgaudit -+$")
  expect_true(any(grepl("^Package:\\s+foo v0.1.0 \\(source directory\\)$", lines)))
  expect_true(any(grepl("^File contexts:\\s+4$", lines)))
  expect_true(any(grepl("^Patterns:\\s+17$", lines)))
  expect_true(any(grepl("^Matches:\\s+3$", lines)))
  # Scanned line renders the ISO value as YYYY-MM-DD HH:MM UTC.
  expect_true(any(grepl("^Scanned:\\s+2026-07-23 14:02 UTC with pkgaudit v0.3.0, rules v0.1.0$", lines)))
})

test_that("format.pkgaudit() counts match the data-frame row counts", {
  obj   <- make_obj(n_file = 2L, n_pat = 5L, n_expr = 4L, n_err = 1L)
  lines <- format(obj)
  val <- function(label) sub(paste0("^", label, "\\s+"), "",
                             grep(paste0("^", label), lines, value = TRUE))
  expect_equal(val("File contexts:"), as.character(nrow(obj$file_contexts)))
  expect_equal(val("Patterns:"),      as.character(nrow(obj$patterns)))
  expect_equal(val("Matches:"),       as.character(nrow(obj$matches)))
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
  expect_true(any(grepl("with pkgaudit v<unknown>, rules v<unknown>$", lines)))
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

test_that(".runs_automatically() over no rows is an empty logical", {
  expect_equal(.runs_automatically(.empty_patterns()), logical(0L))
})

test_that(".in_phase() selects the named phases and 'none'", {
  obj <- rich_obj()

  loaded <- .in_phase(obj$patterns, "at_load")
  expect_true(all(loaded$at_load))
  expect_equal(nrow(loaded), sum(obj$patterns$at_load))

  # "none" is the code that ships but runs at no phase.
  none <- .in_phase(obj$patterns, "none")
  expect_equal(nrow(none), 1L)
  expect_equal(none$code_context, .context_in_function)

  expect_equal(nrow(.in_phase(obj$patterns, c("at_load", "none"))), 3L)
  expect_equal(nrow(.in_phase(obj$patterns, NULL)), nrow(obj$patterns))
  expect_equal(nrow(.in_phase(.empty_patterns(), "at_load")), 0L)
})

test_that(".summarize_findings() without a context column omits it", {
  obj <- rich_obj()

  empty <- .summarize_findings(.empty_patterns())
  expect_named(empty, c("phase", "rule", "n", "attck"))
  expect_equal(nrow(empty), 0L)

  out <- .summarize_findings(obj$patterns)
  expect_named(out, c("phase", "rule", "n", "attck"))
  expect_true(nrow(out) > 0L)
})

test_that(".summarize_findings() returns the same shape for both frames", {
  obj <- rich_obj()
  shape <- c("phase", "rule", "n", "attck")

  # patterns and matches summarise identically: matches carry no code_context,
  # so a summary that distinguished them could not be shared between the two.
  expect_named(.summarize_findings(obj$patterns), shape)
  expect_named(.summarize_findings(obj$matches), shape)
  expect_named(.summarize_findings(.empty_matches()), shape)
})
