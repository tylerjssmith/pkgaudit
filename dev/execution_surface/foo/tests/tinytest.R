# Runner for the tinytest layout, which keeps its tests under inst/tinytest/.
# Guarded for the same reason as tests/testthat.R.
if (requireNamespace("tinytest", quietly = TRUE)) {
  tinytest::test_package("foo")
}
