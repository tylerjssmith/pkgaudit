#!/usr/bin/env Rscript
# Fail if README.md publishes a rules-database version other than the one the
# installed package reports. Run from the package root, against a pkgaudit built
# from the checkout being tested.
#
# The claim is about what a user's rules_version() will return, so this calls it
# rather than restating the query behind it, which would be a second thing to
# keep in step with R/load_rules.R.

readme <- "README.md"
if (!file.exists(readme)) stop("README.md not found", call. = FALSE)

# Newlines are flattened first: pandoc wraps the label onto its own line, so the
# label and the version are not reliably adjacent. Anchoring on the label rather
# than on any version-shaped string keeps example output elsewhere in the README
# from being read as the claim.
flat  <- paste(readLines(readme, warn = FALSE), collapse = " ")
found <- regmatches(
  flat,
  regexpr("Current Version: *`[0-9]+\\.[0-9]+\\.[0-9]+`", flat)
)

if (length(found) == 0L) {
  stop("No 'Current Version:' line found in README.md.\n",
       "Re-render README.Rmd; the integrity section is expected to publish one.",
       call. = FALSE)
}

published <- gsub("[^0-9.]", "", found)
actual    <- pkgaudit::rules_version()

cat("published:", published, "\n")
cat("database: ", actual, "\n")

if (!identical(published, actual)) {
  stop("README.md publishes a stale rules-database version.\n",
       "Install the package, then re-render with ",
       'rmarkdown::render("README.Rmd") and commit README.md.',
       call. = FALSE)
}

cat("README and database agree.\n")
