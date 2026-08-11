# This script writes the code pkgaudit cannot read into a tree another scanner
# can. It is the only place pkgaudit writes anything, and every guard here
# exists because the content and the file names come from an untrusted package.

# The file extension to give each exported language. A language with no entry
# keeps its own name, which is right for c, cpp, js, java and rust.
.export_extensions <- c(python = "py", perl = "pl", ruby = "rb",
                        fortran = "f90", objc = "m")

# How large a file may be before it is left behind. Above the scanning limit,
# since a file too big for pkgaudit to read is exactly the one worth handing to
# a tool that can, but not unbounded: the export writes to the caller's disk.
.max_export_bytes <- 64 * 1024^2


#' Export the code pkgaudit could not read
#'
#' Writes the parts of a package that pkgaudit does not analyse -- C, C++,
#' Fortran, Rust, Python, JavaScript, and the vignette chunks written in them --
#' into a directory another static analyser can be pointed at.
#'
#' @param object A `pkgaudit` object.
#' @param dir Directory to write into. Required, and created if absent. Naming
#'   it is how the caller consents to being written to, so there is no default.
#' @param source The package to read from. Defaults to `object$metadata$pkg_path`,
#'   which is right for a directory scan. A tarball scan must supply this: the
#'   directory it was extracted into is gone by the time the scan returns.
#' @param overwrite Logical; if `FALSE` (default), `dir` must be absent or
#'   empty and an existing file is left alone. `TRUE` allows writing into a
#'   directory that already holds something and replaces a previous export of
#'   the same file. Nothing is ever deleted either way.
#' @param max_bytes Largest file to copy, in bytes. A larger one is recorded in
#'   the manifest and left behind.
#'
#' @return Invisibly, a manifest data frame with one row per exportable span:
#'   `path` (relative to `dir`, `NA` if not written), `file_context`,
#'   `language`, `first_line`, `last_line`, `written`, and `note`.
#'
#' @details
#' A whole file is copied verbatim. A span -- a vignette chunk in a language
#' with no analyser -- is written into a file of its own, blank-padded so its
#' code sits at the same line numbers it occupies in the source. A finding
#' another tool reports at line 40 of `intro.python.py` is therefore at line 40
#' of `intro.Rmd`, with no offset to apply. All spans of one language in one
#' source share a file, since that is how they run.
#'
#' What gets exported is read from the `coverage` frame, so the scan's own
#' account of what it could not read is the single source of truth.
#'
#' @section Security considerations:
#' This is the only function in pkgaudit that writes. Both the content and the
#' file names come from an untrusted package, so: every target path is resolved
#' and must lie under `dir`; a path component that is `.`, `..`, or that
#' contains a separator or a NUL byte is refused; symlinks are never followed,
#' and content is read and rewritten rather than copied, so a link pointing out
#' of the package cannot pull a file in; nothing is written executable; and
#' nothing is removed. A refused span is recorded in the manifest
#' rather than dropped, since a file that cannot be exported safely is one worth
#' knowing about.
#'
#' Exporting still executes nothing.
#'
#' @examples
#' # untrustedpkg is a small package shipped with pkgaudit to be scanned. It is
#' # R and shell throughout, so there is nothing to hand on and the manifest
#' # comes back empty; a package carrying compiled code yields one row per
#' # exported file.
#' tarball <- system.file(
#'   "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
#'   package = "pkgaudit"
#' )
#' exdir <- file.path(tempdir(), "untrustedpkg-example")
#' utils::untar(tarball, exdir = exdir)
#'
#' result   <- audit_package(file.path(exdir, "untrustedpkg"))
#' manifest <- export_unscanned(result, file.path(tempdir(), "for-semgrep"))
#' nrow(manifest)
#'
#' @export
export_unscanned <- function(object, dir, source = NULL, overwrite = FALSE,
                             max_bytes = .max_export_bytes) {
  stopifnot(inherits(object, "pkgaudit"))
  stopifnot(is.character(dir), length(dir) == 1L, !is.na(dir), nzchar(dir))
  stopifnot(is.logical(overwrite), length(overwrite) == 1L, !is.na(overwrite))
  stopifnot(is.numeric(max_bytes), length(max_bytes) == 1L, max_bytes > 0)

  source <- .export_source(object, source)
  .prepare_export_dir(dir, overwrite)
  root <- normalizePath(dir, winslash = "/", mustWork = TRUE)

  jobs <- .export_jobs(object$coverage)
  if (nrow(jobs) == 0L) return(invisible(.empty_manifest()))

  rows <- lapply(seq_len(nrow(jobs)), function(i) {
    .export_one(jobs[i, , drop = FALSE], source, root, overwrite, max_bytes)
  })
  invisible(do.call(rbind, rows))
}


# The directory to read the package from, refusing the case the caller has to
# resolve rather than guessing at it.
.export_source <- function(object, source) {
  if (is.null(source)) source <- object$metadata$pkg_path
  if (length(source) != 1L || is.na(source) || !nzchar(source)) {
    stop("export_unscanned(): no source directory recorded; supply 'source'.",
         call. = FALSE)
  }
  if (!dir.exists(source)) {
    stop("export_unscanned(): 'source' is not a directory: ", source,
         if (isTRUE(object$metadata$pkg_is_tarball))
           "\n  This scan came from a tarball. Extract it and pass its path.",
         call. = FALSE)
  }
  normalizePath(source, winslash = "/", mustWork = TRUE)
}


# Create the target, refusing to write into a directory that already holds
# something unless the caller said so. Never deletes.
.prepare_export_dir <- function(dir, overwrite) {
  if (dir.exists(dir)) {
    if (!overwrite && length(list.files(dir, all.files = TRUE, no.. = TRUE))) {
      stop("export_unscanned(): '", dir, "' is not empty. ",
           "Use overwrite = TRUE to add to it.", call. = FALSE)
    }
    return(invisible(TRUE))
  }
  if (!dir.create(dir, recursive = TRUE, showWarnings = FALSE)) {
    stop("export_unscanned(): could not create '", dir, "'.", call. = FALSE)
  }
  invisible(TRUE)
}


# One job per file to write: a whole file, or all the spans of one language in
# one source, which share a file because that is how they run.
.export_jobs <- function(coverage) {
  rows <- coverage[coverage$status == "exportable", , drop = FALSE]
  if (nrow(rows) == 0L) {
    return(data.frame(file_context = character(0L), language = character(0L),
                      first_line = integer(0L), last_line = integer(0L),
                      whole = logical(0L), target = character(0L),
                      collides = logical(0L), stringsAsFactors = FALSE))
  }
  key  <- paste(rows$file_context, rows$language, sep = "\r")
  jobs <- lapply(unique(key), function(k) {
    at <- rows[key == k, , drop = FALSE]
    data.frame(
      file_context = at$file_context[[1L]],
      language     = at$language[[1L]],
      first_line   = min(at$first_line),
      last_line    = max(at$last_line),
      # A whole-file row is measured from the file itself and so carries its
      # size; a span sits inside a file read some other way and carries none.
      whole        = !all(is.na(at$bytes)),
      stringsAsFactors = FALSE
    )
  })
  jobs <- lapply(jobs, function(j) { j$target <- .export_path(j); j })
  out <- do.call(rbind, jobs)
  # Two jobs can want the same name: a package shipping vignettes/intro.py
  # alongside the Python chunks of vignettes/intro.Rmd. Neither may quietly
  # overwrite the other, so both are refused and reported.
  out$collides <- duplicated(out$target) | duplicated(out$target, fromLast = TRUE)
  out
}


# Write one job, or record why it was not written.
.export_one <- function(job, source, root, overwrite, max_bytes) {
  note <- function(msg, path = NA_character_) {
    data.frame(path = path, file_context = job$file_context,
               language = job$language, first_line = job$first_line,
               last_line = job$last_line, written = is.na(msg),
               note = msg, stringsAsFactors = FALSE)
  }

  rel <- job$target
  if (is.na(rel)) return(note("unsafe path"))
  if (job$collides) return(note("name collides with another export"))
  if (.under_symlink(job$file_context, source)) return(note("symlink"))

  from <- file.path(source, job$file_context)
  size <- suppressWarnings(file.size(from))
  if (is.na(size)) return(note("unreadable"))
  if (size > max_bytes) return(note("over max_bytes"))

  target <- file.path(root, rel)
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  # Resolved after the parent exists, so a component that escapes through a
  # link or a traversal is caught here rather than trusted from the string.
  full <- normalizePath(target, winslash = "/", mustWork = FALSE)
  if (!startsWith(full, paste0(root, "/"))) return(note("escapes target"))

  # Warnings are suppressed as well as errors: what a read of an untrusted
  # path complains about belongs in the manifest, not on the caller's console.
  lines <- tryCatch(suppressWarnings(readLines(from, warn = FALSE)),
                    error = function(e) NULL)
  if (is.null(lines)) return(note("unreadable"))
  if (!job$whole) {
    keep  <- seq.int(job$first_line, min(job$last_line, length(lines)))
    lines <- .blank_except(length(lines), keep, lines)
  }

  ok <- tryCatch({ suppressWarnings(writeLines(lines, full)); TRUE },
                 error = function(e) FALSE)
  if (!ok) return(note("could not write"))
  # Never executable, whatever the source file was.
  Sys.chmod(full, mode = "0600", use_umask = FALSE)
  note(NA_character_, rel)
}


# Where a job is written, relative to the target, or NA if the path is unsafe.
#
# The basename comes from the package, because a finding is only useful if its
# path leads back to the source. It is validated rather than rewritten: a name
# that cannot be used safely is refused and reported.
.export_path <- function(job) {
  # A component that is empty, a traversal, a Windows separator, or a control
  # character is refused. R strings cannot hold a NUL, so there is none to test.
  parts <- strsplit(job$file_context, "/", fixed = TRUE)[[1L]]
  bad <- parts %in% c("", ".", "..") | grepl("[\\\\[:cntrl:]]", parts)
  if (length(parts) == 0L || any(bad)) return(NA_character_)

  if (job$whole) return(paste(parts, collapse = "/"))

  # A span shares its file with the code that was read, so it needs a name of
  # its own: the source's, plus the language, plus that language's extension.
  ext  <- unname(.export_extensions[job$language])
  if (is.na(ext)) ext <- job$language
  stem <- sub("\\.[^.]+$", "", parts[[length(parts)]])
  parts[[length(parts)]] <- paste0(stem, ".", job$language, ".", ext)
  paste(parts, collapse = "/")
}


.empty_manifest <- function() {
  data.frame(path = character(0L), file_context = character(0L),
             language = character(0L), first_line = integer(0L),
             last_line = integer(0L), written = logical(0L),
             note = character(0L), stringsAsFactors = FALSE)
}
