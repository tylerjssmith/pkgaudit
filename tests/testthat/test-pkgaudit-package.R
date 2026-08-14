# The package-level documentation. It names the result frames, and a list in
# prose goes stale silently -- it said "four" while naming five -- so the count
# and the names are checked against the object's own schema.

# The rendered documentation, read from the source tree when there is one and
# from the installed help database otherwise, so the test asserts the same
# thing under pkgload and under R CMD check.
package_doc_text <- function() {
  src <- test_path("..", "..", "man", "pkgaudit-package.Rd")
  if (file.exists(src)) return(paste(readLines(src), collapse = " "))
  db <- tryCatch(tools::Rd_db("pkgaudit"), error = function(e) NULL)
  if (is.null(db) || !"pkgaudit-package.Rd" %in% names(db)) return(NULL)
  paste(as.character(db[["pkgaudit-package.Rd"]]), collapse = " ")
}

test_that("the package doc names exactly the frames the object carries", {
  doc <- package_doc_text()
  skip_if(is.null(doc), "package documentation not available")

  frames <- names(.pkgaudit_columns)
  for (nm in frames) expect_match(doc, nm, fixed = TRUE, info = nm)

  spelled <- c("one", "two", "three", "four", "five", "six", "seven")
  expect_match(doc, paste(spelled[[length(frames)]], "result data frames"),
               fixed = TRUE)
})

test_that("every function the package imports is reachable", {
  # The importFrom list is maintained by hand under a usethis marker, so a
  # function removed upstream would only surface at run time.
  ns <- asNamespace("pkgaudit")
  for (fn in c("dbConnect", "dbDisconnect", "dbGetQuery", "SQLite", "digest",
               "read_xml", "xml_attr", "xml_find_all", "xml_path",
               "xml_parse_data")) {
    expect_true(is.function(get(fn, envir = ns)), info = fn)
  }
})

test_that("the package exports exactly its documented entry points", {
  # A function that becomes exported by accident is public API from then on.
  expect_setequal(
    getNamespaceExports("pkgaudit"),
    c("audit_package", "audit_tarball", "emit_sarif", "export_unscanned",
      "hash_manifest", "load_rules", "rules_version", "validate_tar",
      # The two axes of dispatch, with the constructors a method outside this
      # package needs to build a return value the scan will accept.
      "extract_segments", "analyze_segment", "new_segment", "new_findings")
  )
})

test_that("the S3 methods are registered for dispatch", {
  # Registered rather than exported, so they do not appear above; they are
  # still part of what a user touches.
  for (m in list(c("format", "pkgaudit"), c("print", "pkgaudit"),
                 c("summary", "pkgaudit"), c("print", "summary.pkgaudit"),
                 c("extract_segments", "Rd"), c("extract_segments", "default"),
                 c("analyze_segment", "R"), c("analyze_segment", "default"))) {
    expect_true(is.function(getS3method(m[[1L]], m[[2L]])),
                info = paste(m, collapse = "."))
  }
})

test_that("every script under R/ has a test file of its own", {
  # One test file per source file, so a reader looking for a function's tests
  # knows where they are without searching. The two behaviour-organised files
  # are named for the invariant they assert rather than for a script.
  # An installed package has an R/ directory too -- it holds the lazy-load
  # database -- so the presence of the directory says nothing. What says we are
  # in a source tree is that it contains .R files.
  scripts <- sub("\\.R$", "", basename(list.files(test_path("..", "..", "R"),
                                                  pattern = "\\.R$")))
  skip_if(length(scripts) == 0L, "not running from the source tree")

  tests <- gsub("^test-|\\.R$", "", basename(list.files(test_path("."),
                                                        pattern = "^test-")))
  behaviour <- c("fixtures", "no_execution")

  untested <- setdiff(scripts, tests)
  orphaned <- setdiff(tests, c(scripts, behaviour))
  expect_equal(untested, character(0L),
               info = paste("no test file for:", paste(untested, collapse = ", ")))
  expect_equal(orphaned, character(0L),
               info = paste("no script for:", paste(orphaned, collapse = ", ")))
})
