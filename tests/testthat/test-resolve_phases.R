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

test_that("a pattern takes the phases of the code context it sits in", {
  pat <- .empty_patterns(with_phases = FALSE)
  pat[1L, ] <- list("system", "R/zzz.R", 1L, 1L, "onLoad_base", FALSE, FALSE,
                    "p", "m", "T1059")
  pat[2L, ] <- list("system", "R/zzz.R", 5L, 1L, "Other", FALSE, FALSE,
                    "p", "m", "T1059")
  out <- .resolve_pattern_phases(pat, rules$phases)

  expect_true(out$at_load[[1L]])
  # "Other" is code inside an ordinary function: it runs only if something
  # calls it, which is no lifecycle phase at all.
  expect_false(any(unlist(out[2L, .phase_columns])))
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
