# Point Semgrep's results back at the sources they came from. Run by
# .github/workflows/pkgaudit.yaml.

# A whole file is exported under the path it has in the package, so Semgrep
# already reports it against a path the repository holds. A span -- a vignette
# chunk in a language pkgaudit does not read -- is exported into a file of its
# own, which the repository does not hold, so only those need rewriting. The
# span is blank-padded to the line numbers it occupies in its source, so the
# path is the whole of the difference.

manifest <- utils::read.csv("semgrep-export-manifest.csv",
                            stringsAsFactors = FALSE)
manifest <- manifest[manifest$written & manifest$path != manifest$file_context,
                     , drop = FALSE]

if (nrow(manifest) > 0L) {
  doc <- jsonlite::fromJSON("semgrep.sarif", simplifyVector = FALSE)

  doc$runs <- lapply(doc$runs, function(run) {
    run$results <- lapply(run$results, function(result) {
      result$locations <- lapply(result$locations, function(location) {
        at <- match(location$physicalLocation$artifactLocation$uri,
                    manifest$path)
        if (!is.na(at)) {
          location$physicalLocation$artifactLocation$uri <-
            manifest$file_context[[at]]
        }
        location
      })
      result
    })
    run
  })

  writeLines(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = TRUE,
                              null = "null"), "semgrep.sarif")
}
