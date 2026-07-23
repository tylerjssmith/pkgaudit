#' Download R package source tarballs from a CRAN mirror.
#'
#' Downloads R package source tarballs from a CRAN mirror. Skips packages that
#' have already been downloaded. Returns a data frame summarizing the result of
#' each download attempt.
#'
#' @param pkgs Data frame with columns Package (character) and Version
#'   (character) identifying the packages to be downloaded
#' @param mirror Base URL of a CRAN mirror. Defaults to RStudio/Posit global
#'   mirror.
#' @param dest_dir Path to a destination directory. Created if it does not
#'   exist.
#' @param pause Number of seconds to pause between downloads. Defaults to 0.5.
#'   Set to 0 for no pause. Be considerate of mirror bandwidth.
#'
#' @return A data frame with one row per package and columns:
#'   package  Package name
#'   version  Package version
#'   filename Tarball filename
#'   path     Full path to the downloaded file on success, NA on failure
#'   status   One of "downloaded", "skipped" (already exists), or "failed"
#'   message  Empty string on success, error message on failure
#'
#' @examples
#' \dontrun{
#' packages  = tools::CRAN_package_db()
#' packages  = packages[sample(1:length(packages), 5)]
#' downloads = download_packages(pkgs = packages)
#' }
#'
#' @export
download_r_packages <- function(
  pkgs,
  mirror   = "https://cloud.r-project.org",
  dest_dir = file.path("data", "cran", "src"),
  pause    = 0.5
) {
  stopifnot(is.data.frame(pkgs))
  stopifnot(all(c("Package", "Version") %in% names(pkgs)))
  stopifnot(is.character(mirror),  length(mirror)   == 1L)
  stopifnot(is.character(dest_dir), length(dest_dir) == 1L)
  stopifnot(is.numeric(pause), length(pause) == 1L, pause >= 0)

  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE)
    message("Created destination directory: ", dest_dir)
  }

  # Normalizes mirror URL: removes trailing slash
  mirror <- sub("/+$", "", mirror)

  n <- nrow(pkgs)
  message("Downloading ", n, " package(s) to ", dest_dir, " ...")

  results <- vector("list", n)

  for (i in seq_len(n)) {
    pkg     <- pkgs$Package[[i]]
    version <- pkgs$Version[[i]]
    fname   <- paste0(pkg, "_", version, ".tar.gz")
    url     <- paste0(mirror, "/src/contrib/", fname)
    path    <- file.path(dest_dir, fname)

    result <- list(
      package  = pkg,
      version  = version,
      filename = fname,
      path     = NA_character_,
      status   = NA_character_,
      message  = ""
    )

    # Skip if already downloaded
    if (file.exists(path)) {
      result$path   <- path
      result$status <- "skipped"
      message("  [", i, "/", n, "] Skipped (exists): ", fname)
      results[[i]]  <- result
      next
    }

    # Attempt download
    tryCatch({
      download.file(
        url      = url,
        destfile = path,
        mode     = "wb",
        quiet    = TRUE
      )
      result$path   <- path
      result$status <- "downloaded"
      message("  [", i, "/", n, "] Downloaded: ", fname)
    }, error = function(e) {
      result$status  <<- "failed"
      result$message <<- conditionMessage(e)
      message("  [", i, "/", n, "] Failed: ", fname, " -- ", conditionMessage(e))
    })

    results[[i]] <- result

    # Pause between downloads, but not after the last one
    if (pause > 0 && i < n) Sys.sleep(pause)
  }

  out <- do.call(rbind, lapply(results, as.data.frame,
                               stringsAsFactors = FALSE))
  rownames(out) <- NULL

  n_downloaded <- sum(out$status == "downloaded")
  n_skipped    <- sum(out$status == "skipped")
  n_failed     <- sum(out$status == "failed")

  message(
    "Done. ",
    n_downloaded, " downloaded, ",
    n_skipped,    " skipped, ",
    n_failed,     " failed."
  )

  invisible(out)
}
