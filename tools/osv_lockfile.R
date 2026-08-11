# Write an renv.lock describing pkgaudit's runtime dependency closure, as input
# to OSV-Scanner in CI. See .github/workflows/osv-scanner.yaml.
#
# pkgaudit commits no lock file. Its imports carry no version bounds, so the
# versions a user installs are whatever CRAN resolves on the day rather than a
# snapshot pinned in this repository. This script reads the closure out of the
# library CI just resolved, so a scheduled scan reports on versions a user could
# actually receive, and reports again when they move.
#
#   Rscript tools/osv_lockfile.R [output-path]
#
# Only Depends, Imports and LinkingTo are followed: Suggests are needed to
# develop and check the package, not to use it. Base packages are dropped, as
# they ship with R and are not tracked as CRAN advisories.

osv_lockfile <- function(path = "renv.lock", pkg = ".") {
  db <- utils::installed.packages()
  closure <- .runtime_closure(pkg, db)

  packages <- lapply(closure, function(p) {
    list(Package = p, Version = as.character(db[p, "Version"]),
         Source = "Repository", Repository = "CRAN")
  })
  names(packages) <- closure

  lock <- list(
    R = list(
      Version = paste(R.version$major, R.version$minor, sep = "."),
      Repositories = .repositories()
    ),
    Packages = packages
  )

  writeLines(jsonlite::toJSON(lock, auto_unbox = TRUE, pretty = TRUE), path)
  message("Wrote ", path, " with ", length(closure), " packages.")
  invisible(closure)
}


# Every package reachable from DESCRIPTION by Depends, Imports or LinkingTo,
# sorted, with base packages removed.
.runtime_closure <- function(pkg, db) {
  fields <- c("Depends", "Imports", "LinkingTo")
  desc   <- read.dcf(file.path(pkg, "DESCRIPTION"))
  direct <- .parse_deps(desc[1L, intersect(colnames(desc), fields)])

  found <- tools::package_dependencies(direct, db = db, which = fields,
                                       recursive = TRUE)
  all <- sort(unique(c(direct, unlist(found, use.names = FALSE))))

  # A dependency absent from the library means CI resolved something this
  # script cannot see; stop rather than emit a lock file that quietly omits it.
  missing <- setdiff(all, rownames(db))
  if (length(missing) > 0L) {
    stop("not installed: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  all[!db[all, "Priority"] %in% "base"]
}


# Package names from one or more DESCRIPTION dependency fields, dropping
# version constraints and the R entry.
.parse_deps <- function(fields) {
  entries <- unlist(strsplit(stats::na.omit(as.character(fields)), ","))
  names <- trimws(sub("\\(.*", "", entries))
  sort(unique(names[nzchar(names) & names != "R"]))
}


.repositories <- function() {
  repos <- getOption("repos")
  # "@CRAN@" is the unset-mirror placeholder, not a URL.
  repos <- repos[nzchar(names(repos)) & nzchar(repos) & repos != "@CRAN@"]
  unname(Map(function(n, u) list(Name = n, URL = unname(u)),
             names(repos), repos))
}


# Run only when this file is the script, not when it is sourced: source() is a
# call, so it leaves frames on the stack that a direct Rscript run does not.
if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  osv_lockfile(if (length(args) > 0L) args[[1L]] else "renv.lock")
}
