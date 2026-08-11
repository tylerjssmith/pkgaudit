#' Compute a manifest hash for a directory
#'
#' Hashes a package manifest, a canonically ordered list of every included
#' file's relative path and SHA-256 content hash.
#'
#' @param path Path to the directory to hash.
#' @param exclude Character vector of regular expressions matched against paths
#'   relative to `path`. Defaults exclude version-control and IDE scratch state,
#'   which are not part of the package and (for `.git/`) are large and volatile.
#'   Pass `character(0)` to hash everything present.
#'
#' @return A list with:
#'   \describe{
#'     \item{hash}{SHA-256 of the manifest text (character scalar).}
#'     \item{manifest}{The manifest text (character scalar), one line per file,
#'       formatted as `"<hash>  <relative path>"`.}
#'     \item{n_files}{Number of files included (integer).}
#'     \item{exclude}{The exclusion patterns applied, for recording in metadata.}
#'     \item{symlinks}{Relative paths of symlinks and files under symlinked
#'       directories, excluded from the manifest (character).}
#'     \item{unreadable}{Relative paths that could not be hashed, excluded from
#'       the manifest (character).}
#'   }
#'
#' @details
#' Directories, unlike tarballs, have no single canonical byte stream to hash.
#' This function instead hashes a manifest: a canonically ordered list of
#' every included file's relative path and SHA-256 content hash. The manifest is
#' returned alongside the hash so that two disagreeing scans can be diffed to
#' identify which file differs.
#'
#' A directory hash is a weaker provenance claim than a tarball hash, because
#' its scope depends on `exclude`: two directories that differ only in excluded
#' paths hash identically. The exclusion patterns are returned so the caller
#' can record them. Empty directories and symlinks are likewise not represented
#' in the manifest, so two trees differing only in those also hash identically.
#' For vetting untrusted code, prefer hashing the tarball.
#'
#' @examples
#' # untrustedpkg is a small package shipped with pkgaudit to be scanned.
#' tarball <- system.file(
#'   "extdata", "untrustedpkg", "untrustedpkg_0.1.0.tar.gz",
#'   package = "pkgaudit"
#' )
#' exdir <- file.path(tempdir(), "untrustedpkg-example")
#' utils::untar(tarball, exdir = exdir)
#'
#' hash_manifest(file.path(exdir, "untrustedpkg"))$hash
#'
#' @export
hash_manifest <- function(path, exclude = c("^\\.git/", "^\\.Rproj\\.user/")) {
  stopifnot(is.character(path), length(path) == 1L)
  if (!dir.exists(path)) {
    stop("hash_manifest(): not an existing directory: ", path, call. = FALSE)
  }
  stopifnot(is.character(exclude))

  # ---- 1. Enumerate ----------------------------------------------------------
  # Relative paths, so the hash does not depend on where the directory sits on
  # disk. all.files = TRUE to include hidden files.
  files <- list.files(path, recursive = TRUE, all.files = TRUE, no.. = TRUE)

  # ---- 2. Apply exclusions ---------------------------------------------------
  if (length(exclude) > 0L && length(files) > 0L) {
    drop  <- Reduce(`|`, lapply(exclude, grepl, x = files), FALSE)
    files <- files[!drop]
  }

  # ---- 3. Exclude symlinks ---------------------------------------------------
  # list.files() descends into symlinked directories, and digest() reads through
  # a symlink to its target, which may lie outside `path`. A file is out of scope
  # if it is a symlink or sits under a symlinked directory, so every ancestor
  # component is checked, not just the leaf. Report these rather than hashing
  # content from outside scope.
  symlinks <- character(0L)
  if (length(files) > 0L) {
    is_link  <- unname(vapply(files, .under_symlink, logical(1L), root = path))
    symlinks <- files[is_link]
    files    <- files[!is_link]
  }

  # ---- 4. Canonical order ----------------------------------------------------
  # Radix sort = C-locale ordering, so the manifest does not shift under a
  # different LC_COLLATE. Never use the default locale-dependent sort here.
  files <- sort(files, method = "radix")

  # ---- 5. Hash each file -----------------------------------------------------
  # A file that cannot be read is recorded rather than silently dropped: a
  # security tool must not let an unreadable file quietly change the hash's
  # meaning.
  hashes     <- character(length(files))
  unreadable <- character(0L)
  for (i in seq_along(files)) {
    p <- file.path(path, files[[i]])
    h <- tryCatch(
      digest::digest(p, algo = "sha256", file = TRUE),
      error = function(e) NA_character_
    )
    if (is.na(h)) unreadable <- c(unreadable, files[[i]])
    hashes[[i]] <- h
  }
  keep   <- !is.na(hashes)
  files  <- files[keep]
  hashes <- hashes[keep]

  # ---- 6. Build and hash the manifest ----------------------------------------
  # Format mirrors sha256sum output ("<hash>  <path>") so the manifest is
  # checkable with standard tools. serialize = FALSE hashes the raw bytes of the
  # string; the default (TRUE) would hash R's version-dependent serialization,
  # which is not reproducible outside R.
  manifest <- paste0(hashes, "  ", files, collapse = "\n")
  hash     <- digest::digest(manifest, algo = "sha256", serialize = FALSE)

  list(
    hash       = hash,
    manifest   = manifest,
    n_files    = length(files),
    exclude    = exclude,
    symlinks   = symlinks,
    unreadable = unreadable
  )
}


# TRUE if the relative path `rel` is itself a symlink or lies under a symlinked
# directory. list.files(recursive = TRUE) descends into linked directories, so
# checking only the leaf would admit content outside `root` reached through a
# directory symlink. Each ancestor component is tested in turn.
.under_symlink <- function(rel, root) {
  parts <- strsplit(rel, "/", fixed = TRUE)[[1L]]
  for (k in seq_along(parts)) {
    tgt <- Sys.readlink(file.path(root, paste(parts[seq_len(k)], collapse = "/")))
    if (!is.na(tgt) && nzchar(tgt)) return(TRUE)
  }
  FALSE
}
