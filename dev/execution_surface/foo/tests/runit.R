# Runner for the RUnit layout, which keeps its tests under inst/unitTests/ and
# needs a runner in tests/ to define and execute the suite. Guarded for the same
# reason as tests/testthat.R.
if (requireNamespace("RUnit", quietly = TRUE)) {
  dir <- system.file("unitTests", package = "foo")
  if (nzchar(dir)) {
    suite <- RUnit::defineTestSuite("foo", dirs = dir,
                                    testFileRegexp = "^runit.+\\.R$")
    RUnit::runTestSuite(suite)
  }
}
