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
  db <- .dependency_db()
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
  # Named in the log so a version that came from the repository rather than
  # from the library is visible in the run that produced it.
  from_repo <- setdiff(closure, rownames(utils::installed.packages()))
  if (length(from_repo) > 0L) {
    message("Not installed, versions taken from the repository: ",
            paste(from_repo, collapse = ", "))
  }
  invisible(closure)
}


# What each package is, taken from the library where the package is installed
# and from the repository where it is not.
#
# A LinkingTo dependency is absent from a library built out of binaries: it is
# needed to compile the package that links it, not to run it. cpp11 reaches
# RSQLite that way. Its headers are compiled into the object code a user
# executes all the same, so it is scanned, and the repository supplies the
# version the library cannot.
.dependency_db <- function() {
  cols <- c("Package", "Version", "Priority", "Depends", "Imports", "LinkingTo")

  installed <- utils::installed.packages()[, cols, drop = FALSE]
  # One row per package per library; the first library on the path wins, as it
  # would when the package is loaded.
  installed <- installed[!duplicated(rownames(installed)), , drop = FALSE]

  available <- tryCatch(utils::available.packages()[, cols, drop = FALSE],
                        error = function(e) installed[0L, , drop = FALSE])
  rbind(installed,
        available[!rownames(available) %in% rownames(installed), , drop = FALSE])
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

  # A dependency in neither the library nor the repository is one this script
  # cannot describe; stop rather than emit a lock file that quietly omits it.
  missing <- setdiff(all, rownames(db))
  if (length(missing) > 0L) {
    stop("cannot resolve: ", paste(missing, collapse = ", "), call. = FALSE)
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
