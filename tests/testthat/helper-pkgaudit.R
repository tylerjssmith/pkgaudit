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
