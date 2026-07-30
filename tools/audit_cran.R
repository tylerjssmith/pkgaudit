#' Run pkgaudit::audit_tarball() over many CRAN source tarballs
#'
#' Iterates [pkgaudit::audit_tarball()] over every `.tar.gz` source package
#' tarball in `dir` and returns the aggregated results as tidy data frames. This
#' function is intended for evaluating pkgaudit rules against all packages
#' currently hosted by CRAN.
#'
#' @param dir Path to a directory containing `.tar.gz` source package tarballs,
#'   as downloaded from CRAN by [download_cran()].
#' @param rules Named list of rules as returned by [pkgaudit::load_rules()].
#' @param temp_dir Directory used for temporary extraction. Passed through to
#'   [pkgaudit::audit_tarball()], which extracts into a unique subdirectory here
#'   and removes it after auditing. Defaults to a subdirectory of
#'   [base::tempdir()].
#' @param pattern Regular expression matching tarball file names. Defaults to
#'   files ending in `.tar.gz`.
#' @param on_error One of `"skip"` (default) or `"stop"`. If `"skip"`, an error
#'   auditing a package is captured as a row in the `errors` frame and
#'   processing continues. If `"stop"`, the run halts at the end of the chunk in
#'   which the first error occurs.
#' @param workers Number of parallel workers, passed to [parallel::mclapply()]
#'   as `mc.cores`.
#' @param chunk_size Number of tarballs per chunk. Controls progress-report
#'   frequency, peak memory, and (with `checkpoint_dir`) checkpoint granularity.
#'   Defaults to 200 (about 120 progress updates over a full CRAN run).
#' @param checkpoint_dir Optional directory. When set, each chunk's aggregated
#'   result is written there as `chunk_NNNNN.rds` as it completes, so a long run
#'   can be resumed or recovered after a crash. Created if it does not exist.
#' @param max_entries,max_bytes,max_ratio Pre-extraction validation caps passed
#'   through to [pkgaudit::audit_tarball()] / [pkgaudit::validate_tar()]. The
#'   defaults are calibrated to CRAN; raise them for larger ecosystems.
#'
#' @return A named list of five data frames, with `package` and `version`
#'   prepended to the columns from [pkgaudit::audit_package()]. Columns
#'   recoverable from the rules are dropped from the finding frames, since at
#'   CRAN scale they repeat over millions of rows: `message` from all three,
#'   `attck` from patterns, and the nine lifecycle-phase columns from all three
#'   (join `rules$phases` on `rule` for a context, or on `code_context` for a
#'   pattern, to restore them). The error frame keeps its `message`, which is
#'   the runtime error text.
#'   \describe{
#'     \item{file_contexts}{`package`, `version`, `rule`, `file_context`.}
#'     \item{code_contexts}{`package`, `version`, `rule`, `file_context`,
#'       `line_number`, `column_number`.}
#'     \item{patterns}{`package`, `version`, `rule`, `file_context`,
#'       `line_number`, `column_number`, `code_context`.}
#'     \item{errors}{`package`, `version`, `stage`, `file_context`, `rule`,
#'       `message`. Captures per-file audit errors as well as tarball-level
#'       failures (`stage` `"parse_filename"`, `"validate_tar"` for a refused
#'       archive, or `"audit_tarball"`) and any generic warnings (`stage`
#'       `"warning"`).}
#'     \item{provenance}{`package`, `version`, `filename_name`,
#'       `filename_version`, `desc_name`, `desc_version`, `message`. One row per
#'       tarball whose filename disagrees with its DESCRIPTION `Package`/`Version`
#'       (a mislabeled or repackaged tarball).}
#'   }
#'   Packages that produce no rows for a given frame are simply absent from it.
#'
#' @details
#' Extraction, package-directory selection, and cleanup are delegated to
#' [pkgaudit::audit_tarball()]. Package name and version are taken from the
#' audited package's DESCRIPTION (the `metadata` returned by
#' [pkgaudit::audit_package()]), falling back to the tarball filename
#' (`<package>_<version>.tar.gz`; package names cannot contain `_`, so the first
#' underscore separates the two) when the DESCRIPTION is missing or malformed or
#' the audit fails. A filename not matching that convention at all is recorded
#' as a `parse_filename` error and skipped.
#'
#' Work is processed in chunks so that progress and an ETA can be reported from
#' the parent process (`parallel::mclapply()` forks workers and blocks until a
#' whole batch returns, so per-worker messages are unreliable). Chunking also
#' bounds peak memory and enables optional per-chunk checkpointing.
#'
#' @examples
#' \dontrun{
#' # Download source packages first with download_cran().
#' rules  <- pkgaudit::load_rules()
#' result <- audit_cran("data/cran/src", checkpoint_dir = "data/cran/checkpoints")
#'
#' # Patterns that execute automatically on load, across all packages.
#' subset(result$patterns, code_context != "Other")
#' }
#'
#' @importFrom parallel mclapply detectCores
#' @export
audit_cran <- function(
  dir,
  rules          = pkgaudit::load_rules(),
  temp_dir       = file.path(tempdir(), "pkgaudit"),
  pattern        = "\\.tar\\.gz$",
  on_error       = c("skip", "stop"),
  workers        = parallel::detectCores(logical = FALSE) - 1L,
  chunk_size     = 200L,
  checkpoint_dir = NULL,
  max_entries    = 100000L,
  max_bytes      = 2 * 1024^3,
  max_ratio      = Inf
) {
  on_error   <- match.arg(on_error)
  workers    <- max(1L, as.integer(workers))
  chunk_size <- as.integer(chunk_size)

  stopifnot(is.character(dir), length(dir) == 1L)
  if (!dir.exists(dir)) {
    stop("dir does not exist: ", dir)
  }
  stopifnot(
    is.list(rules),
    all(c("file_contexts", "code_contexts", "patterns", "phases") %in%
          names(rules))
  )
  stopifnot(length(chunk_size) == 1L, !is.na(chunk_size), chunk_size >= 1L)
  if (!is.null(checkpoint_dir)) {
    stopifnot(is.character(checkpoint_dir), length(checkpoint_dir) == 1L)
    dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
  }

  tarballs <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(tarballs) == 0L) {
    message("No tarballs found in: ", dir)
    return(.empty_cran_result())
  }

  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

  total  <- length(tarballs)
  chunks <- split(seq_len(total), ceiling(seq_len(total) / chunk_size))
  message(sprintf(
    "Auditing %d package(s) in %d chunk(s) of up to %d, using %d worker(s).",
    total, length(chunks), chunk_size, workers
  ))

  per_chunk <- vector("list", length(chunks))
  done <- 0L
  t0   <- Sys.time()

  for (k in seq_along(chunks)) {
    idx <- chunks[[k]]

    raw <- parallel::mclapply(
      idx,
      function(i) .audit_worker(tarballs[[i]], rules, temp_dir, on_error,
                                max_entries, max_bytes, max_ratio),
      mc.cores       = workers,
      mc.preschedule = FALSE   # better load balancing for uneven package sizes
    )

    # Under on_error = "stop", a worker's stop() surfaces as a try-error rather
    # than aborting mclapply; halt the run once the chunk is in.
    if (on_error == "stop") {
      te <- Filter(function(x) inherits(x, "try-error"), raw)
      if (length(te) > 0L) {
        cond <- attr(te[[1L]], "condition")
        stop(if (!is.null(cond)) conditionMessage(cond) else as.character(te[[1L]]),
             call. = FALSE)
      }
    }

    chunk <- .combine_results(raw)
    per_chunk[[k]] <- chunk

    if (!is.null(checkpoint_dir)) {
      saveRDS(chunk, file.path(checkpoint_dir, sprintf("chunk_%05d.rds", k)))
    }

    done    <- done + length(idx)
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    eta_min <- (elapsed / done) * (total - done) / 60
    message(sprintf(
      "  %s  %d/%d (%.1f%%)  %d finding(s), %d error(s) this chunk  ~%.0f min left",
      format(Sys.time(), "%H:%M:%S"), done, total, 100 * done / total,
      nrow(chunk$patterns) + nrow(chunk$code_contexts) + nrow(chunk$file_contexts),
      nrow(chunk$errors), eta_min
    ))
  }

  out <- .combine_results(per_chunk)

  message(sprintf(
    "Done. Across %d package(s): %d file context(s), %d code context(s), %d pattern(s), %d error(s), %d provenance mismatch(es).",
    total, nrow(out$file_contexts), nrow(out$code_contexts),
    nrow(out$patterns), nrow(out$errors), nrow(out$provenance)
  ))

  out
}


# --- Helpers ------------------------------------------------------------------

# Audit one tarball, capturing errors and warnings as data so nothing depends on
# forked-worker stderr. Returns a four-frame result (see audit_cran()). Under
# on_error = "stop" a failure is re-raised instead of captured.
#
# Package name and version label every row from the audited DESCRIPTION
# (audit_package() metadata); the filename-derived values are a fallback for the
# error path (no metadata) and a missing/malformed DESCRIPTION (metadata NA).
.audit_worker <- function(tarball, rules, temp_dir, on_error,
                          max_entries, max_bytes, max_ratio) {
  meta <- .parse_tarball_name(tarball)
  if (is.null(meta)) {
    return(.cran_fail(
      NA_character_, NA_character_, "parse_filename",
      paste0("filename does not match <package>_<version>.tar.gz: ",
             basename(tarball))
    ))
  }

  fb_name    <- meta$name       # filename-derived fallback
  fb_version <- meta$version

  # Provenance mismatches are captured separately (as findings) from generic
  # warnings (which become errors rows). A single class-aware handler routes
  # each and muffles both so nothing is double-recorded.
  warns <- character(0L)
  mism  <- list()
  audit <- tryCatch(
    withCallingHandlers(
      pkgaudit::audit_tarball(tarball, rules = rules, temp_dir = temp_dir,
                              max_entries = max_entries, max_bytes = max_bytes,
                              max_ratio = max_ratio),
      warning = function(w) {
        if (inherits(w, "pkgaudit_provenance_mismatch")) {
          mism[[length(mism) + 1L]] <<- w
        } else {
          warns[[length(warns) + 1L]] <<- conditionMessage(w)
        }
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      if (identical(on_error, "stop")) {
        stop("Error processing ", fb_name, " ", fb_version, ": ",
             conditionMessage(e), call. = FALSE)
      }
      e   # signal failure to the caller below
    }
  )

  if (inherits(audit, "condition")) {
    pkg_name    <- fb_name
    pkg_version <- fb_version
    # A refused archive (validate_tar) is recorded distinctly from other
    # audit_tarball errors so refused tarballs can be filtered at CRAN scale.
    stage <- if (inherits(audit, "pkgaudit_invalid_tarball")) {
      "validate_tar"
    } else {
      "audit_tarball"
    }
    res <- .cran_fail(pkg_name, pkg_version, stage, conditionMessage(audit))
  } else {
    # Authoritative name/version from the audited DESCRIPTION, filename as
    # fallback when the DESCRIPTION was missing or malformed (metadata NA).
    pkg_name    <- if (!is.na(audit$metadata$pkg_name))    audit$metadata$pkg_name    else fb_name
    pkg_version <- if (!is.na(audit$metadata$pkg_version)) audit$metadata$pkg_version else fb_version
    res <- .prefix_audit(audit, pkg_name, pkg_version)
  }

  if (length(warns) > 0L) {
    res$errors <- rbind(res$errors, do.call(rbind, lapply(
      warns, function(m) .cran_error_row(pkg_name, pkg_version, "warning", m)
    )))
  }
  if (length(mism) > 0L) {
    res$provenance <- rbind(res$provenance, do.call(rbind, lapply(
      mism, function(w) .cran_provenance_row(pkg_name, pkg_version, w)
    )))
  }
  res
}


# The lifecycle-phase columns pkgaudit attaches to every findings frame. They
# are dropped from the survey frames: a context's phases are a property of the
# rule that matched and a pattern's of the code context it sits in, so both are
# recoverable by joining rules$phases, and carrying nine logicals on every row
# is dead weight at CRAN scale.
.cran_phase_columns <- c(
  "at_autoconf", "at_build", "at_check", "at_install_src", "at_install_bin",
  "on_load", "on_attach", "on_unload", "on_detach"
)


# Prepend the resolved package name/version to each frame of an audit_tarball()
# result, dropping the columns recoverable from the rules (message from the
# finding frames, attck from patterns, phases from all three).
.prefix_audit <- function(audit, pkg_name, pkg_version) {
  drop <- c("message", .cran_phase_columns)
  list(
    file_contexts = .prefix_pkg(.drop_col(audit$file_contexts, drop),
                                pkg_name, pkg_version, .empty_cran_file_contexts),
    code_contexts = .prefix_pkg(.drop_col(audit$code_contexts, drop),
                                pkg_name, pkg_version, .empty_cran_code_contexts),
    patterns      = .prefix_pkg(.drop_col(audit$patterns, c(drop, "attck")),
                                pkg_name, pkg_version, .empty_cran_patterns),
    errors        = .prefix_pkg(audit$errors, pkg_name, pkg_version,
                                .empty_cran_errors),
    # Provenance rows are attached by .audit_worker() from captured mismatch
    # conditions; start empty here.
    provenance    = .empty_cran_provenance()
  )
}


# rbind the same-named frame across a list of four-frame results, dropping
# NULL/try-error entries. Zero-row frames are skipped for speed but the correct
# empty schema is returned when a class has no rows anywhere.
.combine_results <- function(results) {
  results <- Filter(function(x) is.list(x) && !inherits(x, "try-error"), results)
  key <- function(k, empty_fn) {
    parts <- Filter(function(x) nrow(x) > 0L, lapply(results, `[[`, k))
    out   <- if (length(parts) > 0L) do.call(rbind, parts) else empty_fn()
    rownames(out) <- NULL
    out
  }
  list(
    file_contexts = key("file_contexts", .empty_cran_file_contexts),
    code_contexts = key("code_contexts", .empty_cran_code_contexts),
    patterns      = key("patterns",      .empty_cran_patterns),
    errors        = key("errors",        .empty_cran_errors),
    provenance    = key("provenance",    .empty_cran_provenance)
  )
}


# Prepend package/version columns to an audit frame. Returns the correctly typed
# empty frame when there are no rows (cbind cannot widen a zero-row frame against
# a one-row package/version stub).
.prefix_pkg <- function(df, pkg, version, empty_fn) {
  if (nrow(df) == 0L) return(empty_fn())
  cbind(
    data.frame(package = pkg, version = version, stringsAsFactors = FALSE),
    df
  )
}


# Drop one or more columns by name if present; a no-op otherwise.
.drop_col <- function(df, cols) {
  df[, setdiff(names(df), cols), drop = FALSE]
}


# Parse <package>_<version>.tar.gz from a full path. Returns list(name, version)
# or NULL if the filename does not match. CRAN package names cannot contain '_',
# so the first underscore separates name from version.
.parse_tarball_name <- function(path) {
  fname <- sub("\\.tar\\.gz$", "", basename(path))
  parts <- regmatches(fname, regexpr("_", fname), invert = TRUE)[[1L]]
  if (length(parts) != 2L || !nzchar(parts[[1L]]) || !nzchar(parts[[2L]])) {
    return(NULL)
  }
  list(name = parts[[1L]], version = parts[[2L]])
}


# A four-frame result for a package that failed before or during auditing: empty
# finding frames plus a single error row.
.cran_fail <- function(pkg, version, stage, message) {
  res <- .empty_cran_result()
  res$errors <- .cran_error_row(pkg, version, stage, message)
  res
}

.cran_error_row <- function(pkg, version, stage, message) {
  data.frame(
    package      = pkg,
    version      = version,
    stage        = stage,
    file_context = NA_character_,
    rule         = NA_character_,
    message      = message,
    stringsAsFactors = FALSE
  )
}

# One provenance-mismatch finding row, built from a pkgaudit_provenance_mismatch
# condition. package/version are the resolved (DESCRIPTION) identity; the row
# also records both the filename-derived and DESCRIPTION name/version.
.cran_provenance_row <- function(pkg, version, w) {
  na_if_null <- function(x) if (is.null(x)) NA_character_ else x
  data.frame(
    package          = pkg,
    version          = version,
    filename_name    = na_if_null(w$filename_name),
    filename_version = na_if_null(w$filename_version),
    desc_name        = na_if_null(w$desc_name),
    desc_version     = na_if_null(w$desc_version),
    message          = conditionMessage(w),
    stringsAsFactors = FALSE
  )
}


# --- Empty-frame templates (mirror pkgaudit::audit_package() v0.3.0 columns) --
.empty_cran_file_contexts <- function() {
  data.frame(
    package      = character(0L),
    version      = character(0L),
    rule         = character(0L),
    file_context = character(0L),
    stringsAsFactors = FALSE
  )
}

.empty_cran_code_contexts <- function() {
  data.frame(
    package       = character(0L),
    version       = character(0L),
    rule          = character(0L),
    file_context  = character(0L),
    line_number   = integer(0L),
    column_number = integer(0L),
    stringsAsFactors = FALSE
  )
}

.empty_cran_patterns <- function() {
  data.frame(
    package       = character(0L),
    version       = character(0L),
    rule          = character(0L),
    file_context  = character(0L),
    line_number   = integer(0L),
    column_number = integer(0L),
    code_context  = character(0L),
    stringsAsFactors = FALSE
  )
}

.empty_cran_errors <- function() {
  data.frame(
    package      = character(0L),
    version      = character(0L),
    stage        = character(0L),
    file_context = character(0L),
    rule         = character(0L),
    message      = character(0L),
    stringsAsFactors = FALSE
  )
}

.empty_cran_provenance <- function() {
  data.frame(
    package          = character(0L),
    version          = character(0L),
    filename_name    = character(0L),
    filename_version = character(0L),
    desc_name        = character(0L),
    desc_version     = character(0L),
    message          = character(0L),
    stringsAsFactors = FALSE
  )
}

.empty_cran_result <- function() {
  list(
    file_contexts = .empty_cran_file_contexts(),
    code_contexts = .empty_cran_code_contexts(),
    patterns      = .empty_cran_patterns(),
    errors        = .empty_cran_errors(),
    provenance    = .empty_cran_provenance()
  )
}
