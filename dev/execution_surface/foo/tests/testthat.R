# Runner for the testthat layout.
#
# Guarded so a machine without testthat costs these rows rather than the whole
# run: a failed runner would stop R CMD check before the later sites fire.
if (requireNamespace("testthat", quietly = TRUE)) {
  library(testthat)
  library(foo)
  test_check("foo")
}
