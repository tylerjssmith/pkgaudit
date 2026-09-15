# Scan the checkout with pkgaudit, render the result as SARIF, and export the
# code pkgaudit does not read for another scanner to pick up. Run by
# .github/workflows/pkgaudit.yaml.

library(pkgaudit)

result <- audit_package(".")
writeLines(emit_sarif(result), "pkgaudit.sarif")

# The manifest maps each exported file back to the source it came from, which
# is what pkgaudit_remap.R needs and what the export itself does not record.
manifest <- export_unscanned(result, "semgrep-export")
utils::write.csv(manifest, "semgrep-export-manifest.csv", row.names = FALSE)

# Nothing exported means nothing for the second scanner to do, which is the
# common case: a package of pure R and shell hands on no code at all.
exported <- any(manifest$written)
cat("exported ", sum(manifest$written), " of ", nrow(manifest), " spans\n",
    sep = "")
cat("exported=", tolower(as.character(exported)), "\n", sep = "",
    file = Sys.getenv("GITHUB_OUTPUT"), append = TRUE)
