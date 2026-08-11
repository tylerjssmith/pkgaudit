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
make_obj <- function(n_file = 0L, n_pat = 0L, n_expr = 0L,
                     n_err = 0L, metadata = good_metadata()) {
  fc <- .empty_file_contexts()
  pt <- .empty_patterns()
  ex <- .empty_matches()
  cv <- .empty_coverage()
  er <- .empty_errors()
  install_phases <- phase_values("at_build", "at_check", "at_install_src")

  for (i in seq_len(n_file)) {
    fc[i, ] <- c(list("configure", "configure", "m"), install_phases)
  }
  for (i in seq_len(n_pat)) {
    pt[i, ] <- c(list("system", "R/zzz.R", 1L, 1L, "R", FALSE, FALSE,
                      "p", "m", "T1059"), install_phases)
  }
  for (i in seq_len(n_expr)) {
    ex[i, ] <- c(list("curl", "configure", 1L, 1L, "p", "m", "T1041"),
                 install_phases)
  }
  for (i in seq_len(n_err))  er[i, ] <- list("parse_code", "R/bad.R", NA_character_, "boom")
  new_pkgaudit(fc, pt, ex, cv, er, metadata)
}

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

  pt <- .empty_patterns()
  pt[1L, ] <- c(list("source", "R/zzz.R", 1L, 1L, "onLoad_base",
                     FALSE, FALSE, "p", "m", "T1059"), loaded)
  pt[2L, ] <- c(list("rcurl",  "R/zzz.R", 2L, 1L, "onLoad_base",
                     FALSE, FALSE, "p", "m", "T1041"), loaded)
  pt[3L, ] <- c(list("source", "R/aaa.R", 3L, 1L, "R",
                     FALSE, FALSE, "p", "m", "T1059"), installed)
  pt[4L, ] <- c(list("source", "R/aaa.R", 7L, 1L, "Other",
                     FALSE, FALSE, "p", "m", "T1059"), uncalled)

  # An match takes its phases from the file context it sits in, so all of
  # these are the phases that install the package.
  ex <- .empty_matches()
  ex[1L, ] <- c(list("curl", "configure", 3L,  1L, "p", "m", "T1041"),
                installed)
  ex[2L, ] <- c(list("curl", "configure", 3L, 20L, "p", "m", "T1041"),
                installed)
  ex[3L, ] <- c(list("wget", "configure", 5L,  1L, "p", "m", "T1041"),
                installed)
  ex[4L, ] <- c(list("curl", "src/Makevars", 2L, 11L, "p", "m", "T1041"),
                installed)

  new_pkgaudit(fc, pt, ex, .empty_coverage(), errors, metadata)
}

# Errors for the given steps, one row each, with the fields that step sets.
errors_for <- function(...) {
  rows <- list(...)
  do.call(rbind, c(list(.empty_errors()), rows))
}


# A package carrying one vignette, for the .Rmd / .qmd / .Rnw / .rsp extractors.
vignette_pkg <- function(name, lines) {
  make_pkg(files = stats::setNames(list(lines), file.path("vignettes", name)))
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
