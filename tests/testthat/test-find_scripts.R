test_that("find_scripts() finds R/, R/unix/, R/windows/ and src/install.libs.R", {
  pkg <- make_pkg(files = list(
    "R/zzz.R"            = "invisible(NULL)",
    "R/other.r"          = "invisible(NULL)",
    "R/unix/u.R"         = "invisible(NULL)",
    "R/windows/w.R"      = "invisible(NULL)",
    "src/install.libs.R" = "invisible(NULL)"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  scripts <- find_scripts(pkg)
  rel <- sort(.relativize(scripts, pkg))
  expect_equal(rel, sort(c("R/zzz.R", "R/other.r", "R/unix/u.R",
                           "R/windows/w.R", "src/install.libs.R")))
})

test_that("find_scripts() ignores non-R files and unrelated R/ subdirectories", {
  pkg <- make_pkg(files = list(
    "R/zzz.R"      = "invisible(NULL)",
    "R/data.txt"   = "not R",
    "R/nested/x.R" = "invisible(NULL)"  # not unix/ or windows/ -> excluded
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  rel <- .relativize(find_scripts(pkg), pkg)
  expect_equal(rel, "R/zzz.R")
})

test_that("find_scripts() returns empty when there are no scripts", {
  pkg <- make_pkg(files = list("DESCRIPTION" = "Package: demo"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  expect_length(find_scripts(pkg), 0L)
})
