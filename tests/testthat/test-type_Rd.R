# Extraction from help files. An .Rd yields a segment per kind of code that runs
# at its own time. What the extraction itself does is test-extract_Rd_code.R.

rd_pkg <- function(lines) {
  make_pkg(files = stats::setNames(list(lines), "man/f.Rd"))
}

rd_segments <- function(lines) {
  pkg <- rd_pkg(lines)
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  extract_segments(new_source(file.path(pkg, "man/f.Rd"), "man/f.Rd", "Rd"))
}

test_that("examples and each Sexpr stage are separate segments", {
  out <- rd_segments(c(
    "\\name{f}", "\\title{f}",
    "\\examples{", "system('id')", "}",
    "\\Sexpr[stage=build]{system('build')}",
    "\\Sexpr[stage=render]{system('render')}"
  ))
  contexts <- vapply(out$segments, function(s) s$context, character(1L))

  # They do not share a phase profile, so they cannot share a context.
  expect_setequal(contexts, c(.context_rd_examples, "Rd_Sexpr_build",
                              "Rd_Sexpr_render"))
  expect_true(all(vapply(out$segments,
                         function(s) class(s)[[1L]] == "R", logical(1L))))
})

test_that("a help file carries only the code contexts its file rule names", {
  out <- rd_segments(c("\\name{f}", "\\examples{", ".onLoad <- function() 1", "}"))
  # A hook assigned in an example is not a hook: the rule for man/ names the Rd
  # contexts and no others, so the hook rules never reach these segments.
  expect_true(all(vapply(out$segments,
                         function(s) is.null(s$code_contexts), logical(1L))))
})

test_that("dontrun is guarded and dontshow is not", {
  out <- rd_segments(c(
    "\\name{f}", "\\examples{",
    "system('plain')",
    "\\dontrun{system('not run by check')}",
    "\\dontshow{system('run by check, hidden')}",
    "}"
  ))
  ex <- Filter(function(s) identical(s$context, .context_rd_examples),
               out$segments)[[1L]]

  # \dontshow runs under check -- and does not appear on the rendered page.
  expect_gt(length(ex$guarded_lines), 0L)
  expect_lt(length(ex$guarded_lines), sum(nzchar(trimws(ex$lines))))
})

test_that("a help file with no code yields no segment", {
  out <- rd_segments(c("\\name{f}", "\\title{f}", "\\description{Nothing.}"))
  expect_length(out$segments, 0L)
  expect_equal(nrow(out$errors), 0L)
})

test_that("what could be recovered is still scanned when parsing fails", {
  out <- rd_segments(c("\\name{f}", "\\examples{system('id')}", "\\unclosed{"))
  # The error records that the account of the file is incomplete; it does not
  # discard the code that was recovered.
  expect_gt(nrow(out$errors), 0L)
  expect_equal(out$errors$step, "extract_Rd_code")
})
