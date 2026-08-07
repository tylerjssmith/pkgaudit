# Builds the metadata block a scan records: what was scanned, with which rules,
# and when. This is what makes a finding reproducible later.

# Build the nine-field metadata list for a scanned package. Package name and
# version come from DESCRIPTION and are NA (never an error) when it is missing or
# malformed. The rules version and hash describe the database the scan's rules
# were read from, which is not necessarily the bundled one.
.build_metadata <- function(pkg, pkg_path, pkg_is_tarball, pkg_sha256, rules) {
  desc <- .read_description(pkg)
  prov <- .rules_provenance(rules)
  list(
    pkg_name               = desc$name,
    pkg_version            = desc$version,
    pkg_path               = pkg_path,
    pkg_is_tarball         = pkg_is_tarball,
    pkg_sha256             = pkg_sha256,
    pkgaudit_version       = .pkgaudit_version(),
    pkgaudit_rules_version = prov$version,
    pkgaudit_rules_sha256  = prov$sha256,
    scanned                = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
}

# The database a scan's rules were read from. load_rules() records it on the
# list it returns. A rules list assembled some other way carries no provenance,
# and the honest answer is then that it is unknown: reporting the bundled
# database's version and hash would attribute the scan to rules it did not use.
.rules_provenance <- function(rules) {
  prov <- attr(rules, "provenance")
  if (is.null(prov)) {
    list(version = NA_character_, sha256 = NA_character_)
  } else {
    prov
  }
}

# Read Package and Version from a package's DESCRIPTION. Returns NA_character_
# for either field when DESCRIPTION is missing, unparseable, or lacks it -- a
# malformed package must not abort the scan.
.read_description <- function(pkg) {
  out  <- list(name = NA_character_, version = NA_character_)
  desc <- file.path(pkg, "DESCRIPTION")
  if (!file.exists(desc) || dir.exists(desc)) return(out)

  dcf <- tryCatch(suppressWarnings(read.dcf(desc)), error = function(e) NULL)
  if (is.null(dcf) || nrow(dcf) == 0L) return(out)

  pick <- function(fieldname) {
    if (!fieldname %in% colnames(dcf)) return(NA_character_)
    v <- unname(dcf[1L, fieldname])
    if (is.na(v) || !nzchar(trimws(v))) NA_character_ else trimws(v)
  }
  out$name    <- pick("Package")
  out$version <- pick("Version")
  out
}

# Installed pkgaudit version, or NA if it cannot be determined.
.pkgaudit_version <- function() {
  tryCatch(as.character(utils::packageVersion("pkgaudit")),
           error = function(e) NA_character_)
}
