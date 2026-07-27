# Test helpers ----------------------------------------------------------------

# Parse a fixture .R file into an xml parse tree, failing the test on error.
tree_from_file <- function(path) {
  parsed <- parse_script(path)
  testthat::expect_null(parsed$error, info = path)
  parsed$tree
}

# One-row rule data frame selected by name from a loaded rules class.
rule_row <- function(class_df, name) {
  class_df[class_df$name == name, , drop = FALSE]
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
make_obj <- function(n_file = 0L, n_code = 0L, n_pat = 0L, n_err = 0L,
                     metadata = good_metadata()) {
  fc <- .empty_file_contexts()
  cc <- .empty_code_contexts()
  pt <- .empty_patterns()
  er <- .empty_errors()
  for (i in seq_len(n_file)) fc[i, ] <- list("configure_file", "configure", "m")
  for (i in seq_len(n_code)) cc[i, ] <- list("onload_code", "R/zzz.R", 1L, 1L, "m")
  for (i in seq_len(n_pat))  pt[i, ] <- list("system_pattern", "R/zzz.R", 1L, 1L, "m", "T1059", "Top-level")
  for (i in seq_len(n_err))  er[i, ] <- list("parse_script", "R/bad.R", NA_character_, "boom")
  new_pkgaudit(fc, cc, pt, er, metadata)
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
