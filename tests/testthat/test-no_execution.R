# pkgaudit must never execute the code it is scanning. That is not a property
# any one function can be inspected for -- R's Rd machinery will happily
# evaluate \Sexpr if asked, and tools::prepare_Rd(), Rd2HTML(), Rd2txt() and
# their kin do exactly that -- so it is asserted end to end instead: every
# execution site in a package writes a marker file, and a full scan must leave
# no marker behind.
#
# If this test ever fails, a rendering function has been introduced somewhere
# in the read path, and the scanner has become an execution engine.

# Build a package whose every R execution site tries to create a marker file in
# `dir`. Returns the package root.
make_marker_pkg <- function(dir) {
  pkg <- tempfile("marker")
  dir.create(file.path(pkg, "R"), recursive = TRUE)
  dir.create(file.path(pkg, "man", "macros"), recursive = TRUE)
  writeLines(c("Package: markerpkg", "Version: 0.1.0"),
             file.path(pkg, "DESCRIPTION"))

  # file.create() is written as a call the scanner will also flag, so a scan
  # that finds nothing at all cannot pass this test by accident.
  mark <- function(name) {
    sprintf("system(paste0('touch %s'))", file.path(dir, name))
  }

  writeLines(sprintf("\\newcommand{\\bang}{\\Sexpr{%s}}", mark("macro")),
             file.path(pkg, "man", "macros", "m.Rd"))
  writeLines(c(
    "\\name{f}", "\\alias{f}",
    sprintf("\\title{T \\Sexpr{%s}}", mark("sexpr_title")),
    "\\description{D \\bang{} here.}",
    sprintf("\\details{\\Sexpr[stage=install]{%s}}", mark("sexpr_details")),
    "\\examples{", mark("examples"),
    "\\dontrun{", mark("dontrun"), "}",
    "\\dontshow{", mark("dontshow"), "}",
    "}"
  ), file.path(pkg, "man", "f.Rd"))

  writeLines(c(mark("r_toplevel"),
               ".onLoad <- function(libname, pkgname) {",
               paste0("  ", mark("r_onload")), "}"),
             file.path(pkg, "R", "zzz.R"))
  writeLines(c("#!/bin/sh", sprintf("touch %s", file.path(dir, "configure"))),
             file.path(pkg, "configure"))
  pkg
}

markers_dir <- function() {
  d <- tempfile("markers")
  dir.create(d)
  d
}

test_that("the marker mechanism itself works", {
  # A negative result is worthless unless a marker can actually be created, so
  # the harness is verified before it is relied on.
  dir <- markers_dir()
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file.create(file.path(dir, "sanity"))
  expect_true(file.exists(file.path(dir, "sanity")))
})

test_that("audit_package() executes nothing in the package it scans", {
  dir <- markers_dir()
  pkg <- make_marker_pkg(dir)
  on.exit(unlink(c(dir, pkg), recursive = TRUE), add = TRUE)

  res <- audit_package(pkg)

  expect_equal(list.files(dir), character(0L))
  # And the scan really did look at the code that would have fired: the .Rd
  # examples, the \Sexpr macros, and the R sources are all represented.
  expect_true(all(c("man/f.Rd", "R/zzz.R") %in% res$patterns$file_context))
  expect_true(any(res$patterns$code_context == "Rd_examples"))
  expect_true(any(res$patterns$code_context == "Rd_Sexpr_install"))
})

test_that("extract_Rd_code() executes nothing, with or without macros", {
  dir <- markers_dir()
  pkg <- make_marker_pkg(dir)
  on.exit(unlink(c(dir, pkg), recursive = TRUE), add = TRUE)
  page <- file.path(pkg, "man", "f.Rd")

  extract_Rd_code(page)
  extract_Rd_code(page, macros = tools::loadPkgRdMacros(pkg))
  expect_equal(list.files(dir), character(0L))
})

test_that("parsing extracted code executes nothing", {
  dir <- markers_dir()
  pkg <- make_marker_pkg(dir)
  on.exit(unlink(c(dir, pkg), recursive = TRUE), add = TRUE)

  code <- extract_Rd_code(file.path(pkg, "man", "f.Rd"),
                          macros = tools::loadPkgRdMacros(pkg))
  parse_code(strsplit(code$examples, "\n", fixed = TRUE)[[1L]])
  for (stage in code$sexpr) {
    parse_code(strsplit(stage, "\n", fixed = TRUE)[[1L]])
  }
  expect_equal(list.files(dir), character(0L))
})

test_that("audit_tarball() executes nothing in the tarball it scans", {
  dir <- markers_dir()
  pkg <- make_marker_pkg(dir)
  on.exit(unlink(c(dir, pkg), recursive = TRUE), add = TRUE)

  # Rename to the <name>_<version> convention audit_tarball() requires.
  staged <- file.path(tempfile("step"), "markerpkg")
  dir.create(dirname(staged), recursive = TRUE)
  file.rename(pkg, staged)
  on.exit(unlink(dirname(staged), recursive = TRUE), add = TRUE)

  tarball <- file.path(dirname(staged), "markerpkg_0.1.0.tar.gz")
  owd <- setwd(dirname(staged))
  utils::tar(tarball, files = "markerpkg", compression = "gzip",
             tar = "internal")
  setwd(owd)

  audit_tarball(tarball)
  expect_equal(list.files(dir), character(0L))
})

test_that("exporting the unreadable parts executes nothing either", {
  # export_unscanned() is the only function that writes, and it reads files the
  # scan deliberately did not. The invariant has to hold over that path too.
  dir <- tempfile("markers"); dir.create(dir)
  pkg <- make_marker_pkg(dir)
  out <- tempfile("out")
  on.exit(unlink(c(dir, pkg, out), recursive = TRUE), add = TRUE)

  export_unscanned(audit_package(pkg, load_rules()), out, source = pkg)
  expect_length(list.files(dir, recursive = TRUE), 0L)
})
