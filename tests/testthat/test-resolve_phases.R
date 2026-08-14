# Phases are a property of a context, not of an individual finding. Each frame
# resolves them from a different key, which is what these pin down.

rules <- load_rules()

test_that(".phase_lookup resolves a known context and floors an unknown one", {
  known <- .phase_lookup("onLoad_base", rules$phases)
  expect_named(known, .phase_columns)
  expect_true(known$at_load)

  # A context with no row is a broken database, which load_rules() refuses up
  # front; all-FALSE here is a floor, not the mechanism relied upon.
  expect_false(any(unlist(.phase_lookup("no_such_context", rules$phases))))
  expect_equal(nrow(.phase_lookup(character(0L), rules$phases)), 0L)
})

test_that("a file or code context takes the phases of the rule that matched", {
  fc <- data.frame(rule = c("configure", "R_scripts"),
                   file_context = c("configure", "R/f.R"),
                   message = c("m", "m"), stringsAsFactors = FALSE)
  out <- .attach_phases(fc, rules$phases)

  expect_true(out$at_install_src[[1L]])
  expect_false(out$at_load[[1L]])
  expect_true(out$at_build[[2L]])
})

# A pattern row as the scan builds it, carrying the two columns that say where
# the file sat and where the segment did.
scan_pattern <- function(code_context, file_rule = "R_scripts",
                         segment_context = NA_character_) {
  pat <- .empty_patterns(with_phases = FALSE)
  pat[1L, ] <- list("system", "R/zzz.R", 1L, 1L, code_context, FALSE, FALSE,
                    "p", "m", "T1059", file_rule, segment_context)
  pat
}

test_that("a pattern in a named code context takes that rule's phases", {
  out <- .resolve_pattern_phases(scan_pattern("onLoad_base"), rules)
  expect_true(out$at_load[[1L]])
})

test_that("top-level code takes the phases of the file context it sits in", {
  # R/ is built and checked and installed, but not loaded: the lazy-load
  # database holds the resulting values rather than re-evaluating the source.
  out <- .resolve_pattern_phases(scan_pattern(.context_top_level), rules)
  expect_true(out$at_build[[1L]] && out$at_check[[1L]] &&
              out$at_install_src[[1L]])
  expect_false(out$at_load[[1L]])

  # Under tests/, the same code carries that directory's phases instead.
  out <- .resolve_pattern_phases(
    scan_pattern(.context_top_level, file_rule = "tests_testthat"), rules)
  expect_true(out$at_check[[1L]])
  expect_false(out$at_build[[1L]])
})

test_that("a function body inherits, except where its file context overrides", {
  # In R/, reported as running at no phase. Both readings are measured; the
  # rule for R/ says which one it reports, because R/ is dominated by exported
  # functions the lifecycle never calls.
  out <- .resolve_pattern_phases(scan_pattern(.context_in_function), rules)
  expect_false(any(unlist(out[1L, .phase_columns])))

  # Under tests/ there is no override, so it inherits: the probe package
  # measures that a function called from a test file runs when check does.
  out <- .resolve_pattern_phases(
    scan_pattern(.context_in_function, file_rule = "tests_testthat"), rules)
  expect_true(out$at_check[[1L]])
})

test_that("a function body in a help file inherits from its segment", {
  # Not from the file: man/ is processed at build and install, but an example
  # is evaluated only by R CMD check, so the segment is what it takes.
  out <- .resolve_pattern_phases(
    scan_pattern(.context_in_function, file_rule = "man_pages",
                 segment_context = .context_rd_examples), rules)
  expect_true(out$at_check[[1L]])
  expect_false(out$at_build[[1L]] || out$at_install_src[[1L]])
})

test_that("a match takes the union of phases of every rule matching its file", {
  # One path can match more than one file-context rule, and the file executes
  # whenever any of them says it does.
  fc <- .attach_phases(
    data.frame(rule = c("configure", "configure_ac"),
               file_context = c("configure", "configure"),
               message = c("m", "m"), stringsAsFactors = FALSE),
    rules$phases)
  mt <- .empty_matches(with_phases = FALSE)
  mt[1L, ] <- list("curl", "configure", 1L, 1L, "p", "m", "T1041")

  out <- .resolve_match_phases(mt, fc)
  expect_true(out$at_install_src)   # from configure
  expect_true(out$at_autoconf)      # from configure.ac
})

test_that("a match in a file no context covers resolves to no phases", {
  mt <- .empty_matches(with_phases = FALSE)
  mt[1L, ] <- list("curl", "nowhere", 1L, 1L, "p", "m", "T1041")

  out <- .resolve_match_phases(mt, .empty_file_contexts())
  expect_false(any(unlist(out[, .phase_columns])))
})
