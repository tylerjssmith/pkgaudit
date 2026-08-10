# export_unscanned() is the only function in pkgaudit that writes, and both the
# content and the file names come from an untrusted package. Most of these tests
# are about what it refuses to do.

rules <- load_rules()

# A package with one compiled source and one vignette carrying a Python chunk,
# which is enough to exercise both the whole-file and the span paths.
export_pkg <- function() {
  make_pkg(files = list(
    "R/f.R"     = "f <- function() 1",
    "src/hi.c"  = c("#include <R.h>", "void hi(void) { }"),
    "vignettes/intro.Rmd" = c("---", "title: x", "---", "",
                              "```{r}", "y <- 1", "```", "",
                              "```{python}", "import os",
                              "os.system('id')", "```")
  ))
}

test_that("a whole file is copied and a chunk keeps its source line numbers", {
  pkg <- export_pkg(); out <- tempfile("out")
  on.exit(unlink(c(pkg, out), recursive = TRUE), add = TRUE)

  man <- export_unscanned(audit_package(pkg, rules), out, source = pkg)
  expect_true(all(man$written))
  expect_setequal(list.files(out, recursive = TRUE),
                  c("src/hi.c", "vignettes/intro.python.py"))

  expect_equal(readLines(file.path(out, "src/hi.c")),
               readLines(file.path(pkg, "src/hi.c")))

  # The point of the padding: a finding another tool reports at line 10 of the
  # exported file is at line 10 of the vignette.
  got <- readLines(file.path(out, "vignettes/intro.python.py"))
  src <- readLines(file.path(pkg, "vignettes/intro.Rmd"))
  expect_equal(got[[10L]], src[[10L]])
  expect_equal(got[[11L]], src[[11L]])
  expect_true(all(!nzchar(got[1:9])))
})

test_that("the manifest maps every export back to where it came from", {
  pkg <- export_pkg(); out <- tempfile("out")
  on.exit(unlink(c(pkg, out), recursive = TRUE), add = TRUE)

  man <- export_unscanned(audit_package(pkg, rules), out, source = pkg)
  expect_named(man, c("path", "file_context", "language", "first_line",
                      "last_line", "written", "note"))
  py <- man[man$language == "python", ]
  expect_equal(py$file_context, "vignettes/intro.Rmd")
  expect_equal(py$first_line, 10L)
})

test_that("nothing is written executable", {
  skip_on_os("windows")
  pkg <- export_pkg(); out <- tempfile("out")
  on.exit(unlink(c(pkg, out), recursive = TRUE), add = TRUE)
  Sys.chmod(file.path(pkg, "src", "hi.c"), "0755")

  export_unscanned(audit_package(pkg, rules), out, source = pkg)
  expect_equal(as.character(file.mode(file.path(out, "src/hi.c"))), "600")
})

test_that("a non-empty target is refused unless the caller says otherwise", {
  pkg <- export_pkg(); out <- tempfile("out")
  on.exit(unlink(c(pkg, out), recursive = TRUE), add = TRUE)
  dir.create(out); writeLines("mine", file.path(out, "keep.txt"))

  res <- audit_package(pkg, rules)
  expect_error(export_unscanned(res, out, source = pkg), "not empty")
  expect_true(file.exists(file.path(out, "keep.txt")))

  # Even told to proceed, it adds rather than replaces or deletes.
  export_unscanned(res, out, source = pkg, overwrite = TRUE)
  expect_true(file.exists(file.path(out, "keep.txt")))
  expect_true(file.exists(file.path(out, "src/hi.c")))
})

test_that("an existing export is replaced only when asked", {
  pkg <- export_pkg(); out <- tempfile("out")
  on.exit(unlink(c(pkg, out), recursive = TRUE), add = TRUE)
  res <- audit_package(pkg, rules)
  export_unscanned(res, out, source = pkg)
  writeLines("edited by hand", file.path(out, "src/hi.c"))

  # Without overwrite the directory itself is refused, so the edit survives.
  expect_error(export_unscanned(res, out, source = pkg), "not empty")
  expect_equal(readLines(file.path(out, "src/hi.c")), "edited by hand")

  export_unscanned(res, out, source = pkg, overwrite = TRUE)
  expect_equal(readLines(file.path(out, "src/hi.c")),
               readLines(file.path(pkg, "src/hi.c")))
})

test_that("a symlink out of the package is refused, not followed", {
  skip_on_os("windows")
  pkg <- export_pkg(); out <- tempfile("out")
  outside <- tempfile("secret"); writeLines("SECRET", outside)
  on.exit(unlink(c(pkg, out, outside), recursive = TRUE), add = TRUE)
  file.symlink(outside, file.path(pkg, "src", "sneak.c"))

  res <- audit_package(pkg, rules)
  # coverage refuses it first, so it never becomes something to export.
  sneak <- res$coverage[res$coverage$file_context == "src/sneak.c", ]
  expect_equal(sneak$reason, "symlink")
  expect_false(sneak$status == "exportable")

  man <- export_unscanned(res, out, source = pkg)
  expect_false("src/sneak.c" %in% man$file_context)
  expect_false(any(grepl("SECRET", unlist(lapply(
    list.files(out, recursive = TRUE, full.names = TRUE), readLines)))))
})

test_that("a file over max_bytes is left behind and recorded", {
  pkg <- export_pkg(); out <- tempfile("out")
  on.exit(unlink(c(pkg, out), recursive = TRUE), add = TRUE)

  man <- export_unscanned(audit_package(pkg, rules), out, source = pkg,
                          max_bytes = 4)
  expect_false(any(man$written))
  expect_true(all(man$note == "over max_bytes"))
  expect_length(list.files(out, recursive = TRUE), 0L)
})

test_that("a path that would escape the target is refused", {
  pkg <- export_pkg(); out <- tempfile("out")
  on.exit(unlink(c(pkg, out), recursive = TRUE), add = TRUE)

  # A path no list.files() would produce, so it is injected directly: the guard
  # must not depend on discovery being well behaved.
  res <- audit_package(pkg, rules)
  row <- res$coverage[res$coverage$status == "exportable", ][1L, ]
  row$file_context <- "../escaped.c"
  res$coverage <- rbind(res$coverage, row)

  man <- export_unscanned(res, out, source = pkg)
  bad <- man[man$file_context == "../escaped.c", ]
  expect_false(bad$written)
  expect_equal(bad$note, "unsafe path")
  expect_false(file.exists(file.path(dirname(out), "escaped.c")))
})

test_that("a tarball scan says what the caller has to supply", {
  pkg <- export_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  res <- audit_package(pkg, rules)
  res$metadata$pkg_is_tarball <- TRUE
  res$metadata$pkg_path <- "/nowhere/pkg_0.1.0.tar.gz"

  expect_error(export_unscanned(res, tempfile("out")), "Extract it")
})

test_that("a package with nothing to export writes nothing", {
  pkg <- make_pkg(files = list("R/f.R" = "f <- function() 1"))
  out <- tempfile("out")
  on.exit(unlink(c(pkg, out), recursive = TRUE), add = TRUE)

  man <- export_unscanned(audit_package(pkg, rules), out, source = pkg)
  expect_equal(nrow(man), 0L)
  expect_length(list.files(out, recursive = TRUE), 0L)
})

test_that("two exports wanting the same name are both refused", {
  # A package shipping vignettes/intro.python.py alongside the Python chunks of
  # vignettes/intro.Rmd: neither may quietly overwrite the other.
  pkg <- export_pkg(); out <- tempfile("out")
  on.exit(unlink(c(pkg, out), recursive = TRUE), add = TRUE)
  writeLines("print('shipped')", file.path(pkg, "vignettes", "intro.python.py"))

  man <- export_unscanned(audit_package(pkg, rules), out, source = pkg)
  clash <- man[grepl("intro", man$file_context), ]
  expect_equal(nrow(clash), 2L)
  expect_false(any(clash$written))
  expect_true(all(grepl("collides", clash$note)))
})
