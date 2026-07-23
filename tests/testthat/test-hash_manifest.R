# A directory with the given files (named list of relative path = contents).
make_dir <- function(files) {
  d <- tempfile("hm")
  for (rel in names(files)) {
    target <- file.path(d, rel)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    writeLines(files[[rel]], target)
  }
  d
}

test_that("hash_manifest() errors on a non-directory", {
  expect_error(hash_manifest(tempfile()), "not an existing directory")
})

test_that("hash_manifest() returns manifest, hash, and file count", {
  d <- make_dir(list("a.txt" = "aaa", "sub/b.txt" = "bbb"))
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  res <- hash_manifest(d)
  expect_named(res, c("hash", "manifest", "n_files", "exclude", "symlinks",
                      "unreadable"))
  expect_match(res$hash, "^[0-9a-f]{64}$")
  expect_equal(res$n_files, 2L)
  # Manifest lines are "<64-hex>  <relative path>", in radix (C-locale) order.
  lines <- strsplit(res$manifest, "\n", fixed = TRUE)[[1L]]
  expect_match(lines, "^[0-9a-f]{64}  .+$")
  expect_equal(sub("^[0-9a-f]{64}  ", "", lines), c("a.txt", "sub/b.txt"))
})

test_that("hash_manifest() is stable across repeated calls", {
  d <- make_dir(list("a.txt" = "aaa", "b.txt" = "bbb"))
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  expect_equal(hash_manifest(d)$hash, hash_manifest(d)$hash)
})

test_that("hash_manifest() is unaffected by file creation order", {
  d1 <- make_dir(list("a.txt" = "aaa", "b.txt" = "bbb"))
  d2 <- make_dir(list("b.txt" = "bbb", "a.txt" = "aaa"))  # written in reverse
  on.exit(unlink(c(d1, d2), recursive = TRUE), add = TRUE)
  expect_equal(hash_manifest(d1)$hash, hash_manifest(d2)$hash)
})

test_that("hash_manifest() changes when a file's contents change", {
  d <- make_dir(list("a.txt" = "aaa", "b.txt" = "bbb"))
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  before <- hash_manifest(d)$hash
  writeLines("CHANGED", file.path(d, "a.txt"))
  expect_false(identical(before, hash_manifest(d)$hash))
})

test_that("hash_manifest() is independent of the directory's location on disk", {
  files <- list("a.txt" = "aaa", "sub/b.txt" = "bbb")
  d1 <- make_dir(files)
  d2 <- make_dir(files)   # identical contents, different location
  on.exit(unlink(c(d1, d2), recursive = TRUE), add = TRUE)
  expect_equal(hash_manifest(d1)$hash, hash_manifest(d2)$hash)
})

test_that("hash_manifest() honors exclusion patterns", {
  d <- make_dir(list("keep.txt" = "x", ".git/config" = "secret"))
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  # Default excludes .git/ ; hashing everything must differ and count more files.
  default_res <- hash_manifest(d)
  all_res     <- hash_manifest(d, exclude = character(0))
  expect_equal(default_res$n_files, 1L)
  expect_equal(all_res$n_files, 2L)
  expect_false(identical(default_res$hash, all_res$hash))
})
