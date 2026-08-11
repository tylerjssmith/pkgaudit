# The shared helpers. Most are small enough that their contract is the whole
# story, and two of them fail closed in ways worth pinning down.

test_that("every empty frame carries its documented columns", {
  for (nm in names(.pkgaudit_columns)) {
    if (nm == "errors") next
    fn <- get(paste0(".empty_", nm))
    expect_named(fn(with_phases = TRUE), .pkgaudit_columns[[nm]], info = nm)
    expect_equal(nrow(fn()), 0L, info = nm)
    # Without phases: the shape a finder builds before they are joined on.
    expect_named(fn(with_phases = FALSE),
                 setdiff(.pkgaudit_columns[[nm]], .phase_columns), info = nm)
  }
  expect_named(.empty_errors(), .pkgaudit_columns$errors)
})

test_that("empty phase columns are logical and of the asked-for length", {
  expect_named(.empty_phase_cols(), .phase_columns)
  expect_equal(nrow(.empty_phase_cols(3L)), 3L)
  expect_true(all(vapply(.empty_phase_cols(2L), is.logical, logical(1L))))
  expect_false(any(unlist(.empty_phase_cols(2L))))
})

test_that(".error_row fills the fields a step does not set", {
  row <- .error_row(step = "parse_code", message = "boom")
  expect_named(row, .pkgaudit_columns$errors)
  # A parse failure names no rule; a file-context failure names no script.
  expect_true(is.na(row$rule))
  expect_true(is.na(row$file_context))
})

test_that("isTRUE_vec fails closed on NA and NULL", {
  # Used where a missing rule field must not propagate NA into a branch.
  expect_equal(isTRUE_vec(c(TRUE, FALSE, NA)), c(TRUE, FALSE, FALSE))
  expect_equal(isTRUE_vec(NULL), logical(0L))
  expect_equal(isTRUE_vec(c(1L, 0L)), c(TRUE, FALSE))
})

test_that(".relativize strips the root and leaves anything outside it alone", {
  root <- tempfile("root"); dir.create(file.path(root, "R"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  file.create(file.path(root, "R", "f.R"))

  expect_equal(.relativize(file.path(root, "R", "f.R"), root), "R/f.R")
  expect_equal(.relativize(character(0L), root), character(0L))
  # A path that does not sit under root comes back normalized but whole, so it
  # can never be mistaken for a package-relative path.
  elsewhere <- file.path(tempdir(), "elsewhere.txt")
  file.create(elsewhere)
  on.exit(unlink(elsewhere), add = TRUE)
  outside <- .relativize(elsewhere, root)
  expect_equal(outside,
               normalizePath(elsewhere, winslash = "/", mustWork = FALSE))
  # Absolute on either platform: "/x" on Unix, "C:/x" or "//host/x" on Windows.
  expect_match(outside, "^(/|[A-Za-z]:/)")
})

test_that(".xml_find_all_safe returns the condition rather than nothing", {
  tree <- tree_from_lines("system('id')")
  expect_gt(length(.xml_find_all_safe(tree, "//SYMBOL_FUNCTION_CALL")), 0L)

  # libxml2 reports an invalid XPath as a warning, which would otherwise look
  # like a rule that simply matched nothing.
  bad <- .xml_find_all_safe(tree, "//[")
  expect_s3_class(bad, "condition")
})

test_that("every empty frame keeps its shape with and without phase columns", {
  builders <- list(
    file_contexts = .empty_file_contexts, code_contexts = .empty_code_contexts,
    patterns      = .empty_patterns,      matches       = .empty_matches,
    coverage      = .empty_coverage
  )
  for (name in names(builders)) {
    bare <- builders[[name]](with_phases = FALSE)
    full <- builders[[name]]()
    expect_equal(nrow(bare), 0L, info = name)
    expect_equal(nrow(full), 0L, info = name)
    # The phase columns are the only difference, and they come last.
    expect_equal(names(full), c(names(bare), .phase_columns), info = name)
  }
})
