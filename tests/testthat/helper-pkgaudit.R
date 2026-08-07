# Test helpers ----------------------------------------------------------------

# Parse a fixture .R file into an xml parse tree, failing the test on error.
tree_from_file <- function(path) {
  read <- read_code(path)
  testthat::expect_null(read$error, info = path)
  parsed <- parse_code(read$lines)
  testthat::expect_null(parsed$error, info = path)
  parsed$tree
}

# Parse R source given as a character vector of lines, for tests that build
# code inline rather than from a fixture file.
tree_from_lines <- function(lines) {
  parsed <- parse_code(lines)
  testthat::expect_null(parsed$error)
  parsed$tree
}

# One-row rule data frame selected by name from a loaded rules class.
rule_row <- function(class_df, name) {
  class_df[class_df$name == name, , drop = FALSE]
}

# The nine phase values as a list, TRUE for the phases named and FALSE for the
# rest, ready to splice into a row assignment on a findings frame.
phase_values <- function(...) {
  as.list(.phase_columns %in% c(...))
}

# A complete, well-formed metadata list for pkgaudit object tests.
good_metadata <- function(...) {
  utils::modifyList(list(
    pkg_name               = "foo",
    pkg_version            = "0.1.0",
    pkg_path               = "/tmp/foo",
    pkg_is_tarball         = FALSE,
    pkg_sha256             = strrep("a", 64L),
    pkgaudit_version       = "0.3.0",
    pkgaudit_rules_version = "0.1.0",
    pkgaudit_rules_sha256  = strrep("b", 64L),
    scanned                = "2026-07-23T14:02:00Z"
  ), list(...))
}

# A well-formed pkgaudit object with the given per-frame row counts. Every row
# of a frame is identical, so this builds objects for testing counts; tests that
# need distinct findings should build the frames themselves.
make_obj <- function(n_file = 0L, n_code = 0L, n_pat = 0L, n_expr = 0L,
                     n_err = 0L, metadata = good_metadata()) {
  fc <- .empty_file_contexts()
  cc <- .empty_code_contexts()
  pt <- .empty_patterns()
  ex <- .empty_matches()
  er <- .empty_errors()
  install_phases <- phase_values("at_build", "at_check", "at_install_src")

  for (i in seq_len(n_file)) {
    fc[i, ] <- c(list("configure", "configure", "m"), install_phases)
  }
  for (i in seq_len(n_code)) {
    cc[i, ] <- c(list("onLoad_base", "R/zzz.R", 1L, 1L, "m"),
                 phase_values("at_build", "at_check", "at_install_src",
                              "at_load"))
  }
  for (i in seq_len(n_pat)) {
    pt[i, ] <- c(list("system", "R/zzz.R", 1L, 1L, "m", "T1059",
                      "Top-level"), install_phases)
  }
  for (i in seq_len(n_expr)) {
    ex[i, ] <- c(list("curl", "configure", 1L, 1L, "m", "T1041"),
                 install_phases)
  }
  for (i in seq_len(n_err))  er[i, ] <- list("parse_code", "R/bad.R", NA_character_, "boom")
  new_pkgaudit(fc, cc, pt, ex, er, metadata)
}

# Create a minimal source package on disk and return its root path. Extra files
# are given as a named list of path = contents (paths relative to the root).
make_pkg <- function(dir = tempfile("pkg"), files = list()) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines("Package: demo", file.path(dir, "DESCRIPTION"))
  for (rel in names(files)) {
    target <- file.path(dir, rel)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    writeLines(files[[rel]], target)
  }
  dir
}
