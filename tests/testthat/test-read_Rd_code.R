rd_file <- function(lines, name = "f.Rd") {
  dir <- tempfile("rd")
  dir.create(dir)
  path <- file.path(dir, name)
  writeLines(lines, path)
  path
}

# A help page exercising every construct the extractor has to handle.
probe <- c(
  "\\name{f}",                                                  # 1
  "\\alias{f}",                                                 # 2
  "\\title{T \\Sexpr{format(Sys.time())}}",                     # 3
  "\\description{",                                             # 4
  "  D \\Sexpr[stage=build]{system(\"id\")} here.",             # 5
  "}",                                                          # 6
  "\\examples{",                                                # 7
  "x <- 1  # 50\\% and a brace \\{",                            # 8
  "cat(\"a\\\\nb\")",                                           # 9
  "\\dontrun{",                                                 # 10
  "  system(\"id\")",                                           # 11
  "}",                                                          # 12
  "\\dontshow{ hidden <- TRUE }",                               # 13
  "y <- 2",                                                     # 14
  "}"                                                           # 15
)

test_that("read_Rd_code() returns the examples, one string per Sexpr stage", {
  path <- rd_file(probe)
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- read_Rd_code(path)
  expect_named(res, c("examples", "guarded", "sexpr", "error"))
  expect_type(res$examples, "character")
  expect_named(res$sexpr, c("build", "install", "render"))
  expect_true(all(vapply(res$sexpr, is.character, TRUE)))
  expect_null(res$error)
})

test_that("both streams parse as R", {
  path <- rd_file(probe)
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- read_Rd_code(path)
  expect_no_error(parse(text = res$examples))
  for (stage in res$sexpr) expect_no_error(parse(text = stage))
})

# Line alignment is the property that lets a finding point into the .Rd, so it
# is asserted directly rather than inferred from downstream behaviour.
test_that("extracted code is aligned to the lines of the .Rd", {
  path <- rd_file(probe)
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- read_Rd_code(path)
  ex  <- strsplit(res$examples,       "\n", fixed = TRUE)[[1L]]
  ins <- strsplit(res$sexpr$install,  "\n", fixed = TRUE)[[1L]]
  bld <- strsplit(res$sexpr$build,    "\n", fixed = TRUE)[[1L]]

  expect_match(ex[[8L]],  "^x <- 1")
  expect_match(ex[[11L]], "system")
  expect_match(ex[[14L]], "^y <- 2")
  # Line 3 is unlabelled, so install; line 5 declares stage=build.
  expect_match(ins[[3L]], "format\\(Sys.time\\(\\)\\)")
  expect_match(bld[[5L]], "system")
})

test_that("parsing the examples code yields .Rd line numbers", {
  path <- rd_file(probe)
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  parsed <- parse(text = read_Rd_code(path)$examples, keep.source = TRUE)
  lines  <- vapply(attr(parsed, "srcref"), function(s) s[[1L]], integer(1L))
  # x <- 1 on line 8, the \dontrun system() on 11, hidden on 13, y <- 2 on 14.
  expect_equal(lines, c(8L, 9L, 11L, 13L, 14L))
})

test_that("all four example wrappers are unwrapped", {
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\examples{",
                    "\\dontrun{  a <- 1 }", "\\donttest{ b <- 2 }",
                    "\\dontshow{ c <- 3 }", "\\testonly{ d <- 4 }", "}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  code <- read_Rd_code(path)$examples
  for (v in c("a <- 1", "b <- 2", "c <- 3", "d <- 4")) expect_match(code, v)
})

test_that("Rd escapes are resolved and Rd comments dropped", {
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\examples{",
                    "z <- c(1,2) \\%in\\% c(1)",
                    "% an Rd comment",
                    "g(1)  % a trailing Rd comment", "}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  code <- read_Rd_code(path)$examples
  expect_match(code, "%in%", fixed = TRUE)
  expect_false(grepl("an Rd comment", code))
  expect_no_error(parse(text = code))
})

test_that("\\dots becomes an ellipsis rather than vanishing", {
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\examples{", "f(\\dots)", "}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  code <- read_Rd_code(path)$examples
  expect_match(code, "f(...", fixed = TRUE)
})

test_that("an inline \\Sexpr goes to the sexpr code, not the examples one", {
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\examples{",
                    "h(\\Sexpr{2+2})", "}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- read_Rd_code(path)
  expect_match(res$sexpr$install, "2+2", fixed = TRUE)
  expect_false(grepl("2+2", res$examples, fixed = TRUE))
  expect_no_error(parse(text = res$examples))
})

test_that("a file with no code yields empty strings and no error", {
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\description{No code.}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- read_Rd_code(path)
  expect_equal(res$examples, "")
  expect_true(all(unlist(res$sexpr) == ""))
  expect_null(res$error)
})

# errors -----------------------------------------------------------------------
test_that("a missing file or a directory is reported, not signalled", {
  expect_match(read_Rd_code(tempfile())$error, "not a readable file")
  expect_match(read_Rd_code(tempdir())$error, "not a readable file")
})

test_that("a help file above the scanning limit is refused unread", {
  path <- rd_file(c(
    "\\name{f}", "\\title{T}", "\\description{d}",
    "\\examples{", paste0("# ", strrep("x", .max_scan_bytes)),
    "system(\"id\")", "}"
  ))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- read_Rd_code(path)
  # Refused before parse_Rd() sees it, so no code is returned for a file that
  # was never examined.
  expect_equal(res$examples, "")
  expect_true(all(unlist(res$sexpr) == ""))
  expect_match(res$error, "scanning limit")
})

test_that("a file parse_Rd() only warns about keeps its code and reports why", {
  # parse_Rd() recovers from this with a warning and a truncated tree. The
  # recovered code is still returned, but error says not to trust it as whole.
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\examples{ a <- 1"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  res <- read_Rd_code(path)
  expect_type(res$error, "character")
  expect_match(res$examples, "a <- 1")
})

test_that("macros are expanded only when supplied", {
  pkg <- tempfile("mp")
  dir.create(file.path(pkg, "man", "macros"), recursive = TRUE)
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  writeLines("Package: mp", file.path(pkg, "DESCRIPTION"))
  writeLines("\\newcommand{\\bang}{\\Sexpr{system(\"id\")}}",
             file.path(pkg, "man", "macros", "m.Rd"))
  page <- file.path(pkg, "man", "page.Rd")
  writeLines(c("\\name{p}", "\\title{P}", "\\description{Uses \\bang{} here.}"),
             page)

  with_m <- read_Rd_code(page, macros = tools::loadPkgRdMacros(pkg))
  expect_match(with_m$sexpr$install, "system")
  expect_null(with_m$error)

  without <- read_Rd_code(page)
  expect_true(all(unlist(without$sexpr) == ""))
  expect_match(without$error, "unknown macro")
})


# stages and guards ------------------------------------------------------------
test_that("each \\Sexpr goes to the stage it declares, unlabelled meaning install", {
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\description{",
                    "\\Sexpr[stage=build,results=hide]{b <- 1}",
                    "\\Sexpr[stage=render,results=hide]{r <- 2}",
                    "\\Sexpr[stage=install,results=hide]{i <- 3}",
                    "\\Sexpr{u <- 4}", "}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  sx <- read_Rd_code(path)$sexpr
  expect_match(sx$build,  "b <- 1")
  expect_match(sx$render, "r <- 2")
  # An unlabelled \\Sexpr behaves identically to stage=install, so both land here.
  expect_match(sx$install, "i <- 3")
  expect_match(sx$install, "u <- 4")
  expect_false(grepl("u <- 4", sx$build, fixed = TRUE))
})

test_that("an unrecognised stage is refused by R's own Rd parser", {
  path <- rd_file(c("\\name{f}", "\\title{T}",
                    "\\description{\\Sexpr[stage=nonsense]{x <- 1}}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  # tools::parse_Rd() validates the stage itself, so an invalid one never
  # reaches .Sexpr_stage(): the file fails to parse and the error is recorded
  # rather than the code being silently filed under a guessed stage.
  res <- read_Rd_code(path)
  expect_type(res$error, "character")
  expect_true(all(unlist(res$sexpr) == ""))
})

test_that("a stage is read case-insensitively, as parse_Rd() reads it", {
  path <- rd_file(c("\\name{f}", "\\title{T}",
                    "\\description{\\Sexpr[stage=BUILD,results=hide]{x <- 1}}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)
  expect_match(read_Rd_code(path)$sexpr$build, "x <- 1")
})

test_that("only the wrapper no example run reaches is marked guarded", {
  path <- rd_file(c("\\name{f}", "\\title{T}", "\\examples{",   # 1-3
                    "plain <- 1",                                    # 4
                    "\\dontrun{ nope <- 2 }",                      # 5
                    "\\donttest{ also <- 3 }",                     # 6
                    "\\dontshow{ hidden <- 4 }",                   # 7
                    "\\testonly{ only <- 5 }",                     # 8
                    "}"))
  on.exit(unlink(dirname(path), recursive = TRUE), add = TRUE)

  # \\dontshow and \\testonly run under any example run, and \\donttest runs
  # under `R CMD check --as-cran`, so only \\dontrun is guarded.
  expect_setequal(read_Rd_code(path)$guarded, 5L)
})

# Assembly (internal) ----------------------------------------------------------
test_that(".assemble_lines() over nothing, or over empty fragments, is empty", {
  expect_equal(.assemble_lines(list()), "")
  expect_equal(.assemble_lines(list(list(line = 1L, col = 1L, text = ""))), "")
})

test_that(".assemble_lines() separates two fragments sharing a line", {
  frags <- list(list(line = 1L, col = 1L, text = "a()"),
                list(line = 1L, col = 9L, text = "b()"))
  # Without a separator the second is placed at its own column.
  expect_equal(.assemble_lines(frags), "a()     b()")
  # With one, the separator is written in after the first fragment, which is
  # what keeps two neighbouring matches from parsing as a single call. Column
  # padding still applies, so the second fragment stays where it was.
  expect_match(.assemble_lines(frags, separator = "; "), "^a\\(\\); +b\\(\\)$")
})

test_that(".Sexpr_stage() falls back to install, the broadest stage", {
  expect_equal(.Sexpr_stage(NULL), "install")
  # An option list carrying no stage= at all.
  expect_equal(.Sexpr_stage("results=hide"), "install")
  # A stage pkgaudit does not know is never under-reported.
  expect_equal(.Sexpr_stage("stage=nonesuch"), "install")
  expect_equal(.Sexpr_stage("stage=BUILD"), "build")
  expect_equal(.Sexpr_stage("stage = render"), "render")
})

test_that(".Rd_fragments() drops a node carrying no text or no position", {
  # Built by hand: a fragment with nothing in it, and one whose position the
  # parser did not record. Neither can be placed in a line-aligned buffer, so
  # neither may be reported at a line it was guessed into.
  sexpr <- function(text) {
    structure(list(structure(text, Rd_tag = "RCODE")),
              Rd_tag = "\\Sexpr", Rd_option = "stage=install")
  }
  rd <- structure(list(sexpr(""), sexpr("system('id')")), Rd_tag = "Rd")

  frags <- .Rd_fragments(rd)
  expect_length(frags$sexpr$install, 0L)
  expect_length(frags$examples, 0L)
})
