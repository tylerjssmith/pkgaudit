# This script builds the coverage frame: one row per file the package carries
# that is, or could be, code, saying how well pkgaudit read it and why not
# better. Which files it accounts for is .in_scope() below.

# The boundary of the package. Version-control and IDE state is not package
# content, and enumerating .git/objects/ would bury the frame. Files listed in
# .Rbuildignore are NOT excluded: that list is written by the package under
# audit and must not be able to hide anything from the scan.
.coverage_exclude <- c("^\\.git/", "^\\.Rproj\\.user/", "^renv/library/")


# Extension to language. Drives both the export and the `language` column, and
# is the only place a file's language is decided.
#
# R and shell appear here so that an R script somewhere no rule scans is still
# reported as R rather than as an unknown file.
.coverage_languages <- c(
  R = "R", r = "R", S = "R", s = "R", q = "R",
  Rd = "Rd", rd = "Rd", Rmd = "Rmd", rmd = "Rmd", qmd = "qmd",
  Rnw = "Rnw", rnw = "Rnw", rsp = "rsp",
  sh = "shell", bash = "shell", ksh = "shell", zsh = "shell", csh = "shell",
  c = "c", h = "c",
  cc = "cpp", cpp = "cpp", cxx = "cpp", hpp = "cpp", hxx = "cpp", ipp = "cpp",
  m = "objc", mm = "objc",
  f = "fortran", f90 = "fortran", f95 = "fortran", f03 = "fortran",
  f77 = "fortran", "for" = "fortran",
  rs = "rust", py = "python", pyx = "python", js = "js", ts = "js",
  java = "java", pl = "perl", pm = "perl", rb = "ruby", lua = "lua"
)

# Languages pkgaudit analyzes itself. Everything else with a known language is
# text another tool can read, and is therefore exportable.
.coverage_analyzed <- c("R", "Rd", "Rmd", "qmd", "Rnw", "rsp", "shell")

# R's serialization formats. Deserializing one of these can execute arbitrary
# code, and data/*.rda and R/sysdata.rda are loaded when the package loads, so
# these are executable surface -- unexaminable by pkgaudit, but not inert.
.coverage_serialized <- c("rda", "RData", "Rdata", "rdata", "rds", "Rds",
                          "RDS", "rdb", "rdx")

# Formats with no useful text form. Listed, never exported.
.coverage_binary <- c(
  "so", "dll", "dylib", "o", "a", "obj", "lib", "class", "jar", "exe",
  "png", "jpg", "jpeg", "gif", "bmp", "ico", "pdf", "eps",
  "zip", "gz", "bz2", "xz", "tar", "tgz", "7z", "rar",
  "woff", "woff2", "ttf", "otf", "eot", "mo", "npy", "nc", "h5", "parquet"
)


#' Describe how well every file in a package was read
#'
#' Builds the `coverage` data frame: one row per file the package carries that
#' is, or could be, code, and one per code span where a file yields several,
#' recording whether pkgaudit parsed it, matched it as text, could hand it to
#' another tool, or did not examine it at all.
#'
#' @param path Path to the package root.
#' @param found The `file_contexts` frame from [find_file_contexts()], carrying
#'   every rule match, reporting or not.
#' @param file_context_rules `rules$file_contexts` from [load_rules()].
#' @param scanned Named character vector of the rule `type` each scanned file
#'   was read as, named by package-root-relative path. The type, not the
#'   extension, is what a scanned file's language comes from: `configure` has no
#'   extension but is read as shell.
#' @param errors The scan's `errors` frame, which is what identifies the files
#'   pkgaudit tried to read and could not.
#'
#' @return A data frame with the columns [audit_package()] documents for
#'   `coverage`, without the phase columns; [audit_package()] attaches those.
#'
#' @section Security considerations:
#' The frame is built by walking the tree rather than by asking the rules what
#' they matched, so a file in a location no rule anticipates still gets a row.
#' That is the point: an unknown-unknown becomes a known-unknown, and a clean
#' scan becomes falsifiable. What a name has to say to earn a row is
#' `.in_scope()`.
#'
#' A symlink is recorded and never read. `list.files()` descends into symlinked
#' directories and a read would follow the link out of the package, so every
#' ancestor component is tested, as [hash_manifest()] does.
#'
#' @keywords internal
build_coverage <- function(path, found, file_context_rules,
                           scanned = character(0L),
                           errors = .empty_errors()) {
  stopifnot(is.character(path), length(path) == 1L, dir.exists(path))

  files <- list.files(path, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  if (length(files) > 0L) {
    drop  <- Reduce(`|`, lapply(.coverage_exclude, grepl, x = files), FALSE)
    files <- files[!drop]
  }
  if (length(files) == 0L) return(.empty_coverage(with_phases = FALSE))
  files <- sort(files, method = "radix")

  rule  <- .claiming_rule(files, found, file_context_rules)
  keep  <- .in_scope(files, rule, file_context_rules)
  files <- files[keep]
  rule  <- rule[keep]
  if (length(files) == 0L) return(.empty_coverage(with_phases = FALSE))

  linked <- unname(vapply(files, .under_symlink, logical(1L), root = path))
  ext    <- .file_extension(files)
  lang   <- unname(.coverage_languages[ext])

  bytes  <- suppressWarnings(file.size(file.path(path, files)))
  failed <- .error_reason(files, errors)

  status <- character(length(files))
  reason <- rep(NA_character_, length(files))

  for (i in seq_along(files)) {
    if (linked[[i]]) {
      status[[i]] <- "unexamined"; reason[[i]] <- "symlink"; next
    }
    if (!is.na(failed[[i]])) {
      status[[i]] <- "error";      reason[[i]] <- failed[[i]]; next
    }
    if (files[[i]] %in% names(scanned)) {
      # The rule's type says how the file was read, which is what its language
      # is; the extension may say nothing at all.
      read_as     <- .segment_language(scanned[[files[[i]]]])
      lang[[i]]   <- read_as
      status[[i]] <- if (identical(read_as, "shell")) "matched" else "parsed"
      next
    }
    if (ext[[i]] %in% .coverage_serialized) {
      status[[i]] <- "unexamined"; reason[[i]] <- "serialized"; next
    }
    if (ext[[i]] %in% .coverage_binary) {
      status[[i]] <- "unexamined"; reason[[i]] <- "binary"; next
    }
    if (!is.na(lang[[i]]) && !lang[[i]] %in% .coverage_analyzed) {
      status[[i]] <- "exportable"; reason[[i]] <- "no_analyzer"; next
    }
    # Nothing read the file. Either a rule claimed it and that rule's type has
    # no extractor -- DESCRIPTION is accounted for, not parsed -- or no rule
    # looks where it sits, as for an R script under misc/. The two are separate
    # claims: the first is a limit of what pkgaudit reads, the second a limit of
    # where it looks.
    status[[i]] <- "unexamined"
    reason[[i]] <- if (is.na(rule[[i]])) "no_rule" else "no_extractor"
  }

  lines <- .coverage_lines(path, files, status, bytes)

  data.frame(
    file_context = files,
    language     = lang,
    status       = status,
    reason       = reason,
    first_line   = ifelse(is.na(lines), NA_integer_, 1L),
    last_line    = lines,
    lines        = lines,
    bytes        = as.integer(bytes),
    rule         = rule,
    stringsAsFactors = FALSE
  )
}


# The files the frame accounts for: those a rule claimed, and those whose name
# says what kind of file they are, wherever they sit.
#
# A rule's `filename` either names a kind of file, anchored on the end, or names
# a place, as src/'s catch-all does. Only the first is applied across the whole
# tree, which puts a stray .R under misc/ in the frame while leaving NAMESPACE
# and MD5 out. The allowlist is therefore derived rather than written: a rule
# for a new kind of file starts accounting for it everywhere. What it costs is a
# file whose name says nothing -- a .txt read and evaluated is not in the frame,
# though the R that reads it is a finding in its own right, and an extensionless
# script is out too, since nothing here opens a file to identify it.
.in_scope <- function(files, rule, file_context_rules) {
  kinds <- file_context_rules$filename[grepl("[$]$", file_context_rules$filename)]
  named <- Reduce(`|`, lapply(kinds, grepl, x = basename(files)), FALSE)
  !is.na(rule) | named
}


# Combine the tree walk with the spans the analyzers reported. A file can appear
# in both: an .Rmd is parsed for its R chunks, and each chunk in a language
# nothing reads is a span of its own. Span rows carry no rule, so they take the
# phases of the file they sit in.
.merge_coverage <- function(files, spans) {
  if (nrow(spans) == 0L) return(files)
  spans$rule <- files$rule[match(spans$file_context, files$file_context)]
  out <- rbind(files, spans)
  out[order(out$file_context, out$first_line, na.last = FALSE), , drop = FALSE]
}


# The language a file read under a given rule type yields. A Makefile is read
# exactly as a shell script is and produces shell segments, so it is reported as
# shell; every other type names its own language.
.segment_language <- function(type) if (identical(type, "make")) "shell" else type


# The rule each file takes its phases from, or NA where none claimed it.
#
# A file can match both a rule that reads it and a directory-wide rule that only
# accounts for it -- src/Makevars is scanned as make and also sits under the
# rule covering all of src/. The reading rule wins, since it is the specific
# claim; without this the phases would depend on rule name ordering.
.claiming_rule <- function(files, found, file_context_rules) {
  out <- rep(NA_character_, length(files))
  if (is.null(found) || nrow(found) == 0L) return(out)

  type    <- file_context_rules$type[match(found$rule, file_context_rules$name)]
  ordered <- found[order(is.na(type) | type == "other"), , drop = FALSE]

  hit <- match(files, ordered$file_context)
  out[!is.na(hit)] <- ordered$rule[hit[!is.na(hit)]]
  out
}


# The lowercase-preserved extension of each path, or "" where there is none.
# The leading dot is dropped, so ".Rprofile" has extension "Rprofile" -- which
# matches nothing, which is correct: it is claimed by a rule, not an extension.
.file_extension <- function(files) {
  base <- basename(files)
  ext  <- sub("^.*\\.([^.]+)$", "\\1", base)
  ifelse(grepl("\\.", base) & !startsWith(base, "."), ext,
         ifelse(grepl("\\.", sub("^\\.", "", base)), ext, ""))
}


# The steps at which an error means the file itself could not be read. A rule
# that fails on a file says nothing about the file, and a help file whose macros
# could not all be resolved is still scanned for what was recovered -- neither
# is a coverage failure, and both leave the file's status alone.
.reading_steps <- c("read_code", "extract_segments", "parse_code")

# Why reading each file failed, or NA where it did not. Errors are keyed by
# file_context, and the step says what failed.
.error_reason <- function(files, errors) {
  out <- rep(NA_character_, length(files))
  if (is.null(errors) || nrow(errors) == 0L) return(out)

  for (i in seq_len(nrow(errors))) {
    fc <- errors$file_context[[i]]
    if (is.na(fc) || !errors$step[[i]] %in% .reading_steps) next
    at <- match(fc, files)
    if (is.na(at) || !is.na(out[[at]])) next
    msg <- errors$message[[i]]
    out[[at]] <- if (grepl("scanning limit", msg, fixed = TRUE)) "too_large"
                 else if (identical(errors$step[[i]], "parse_code")) "unparseable"
                 else "unreadable"
  }
  out
}


# Line counts, for the files a reader would want a size for.
#
# Only for what was read anyway or would be exported. Reading a file purely to
# count its lines is wasted work and needless exposure to a hostile package;
# `bytes` costs a stat and answers the same question well enough. Above the
# scanning limit the count is not available at all, which is the honest NA.
.coverage_lines <- function(path, files, status, bytes) {
  out  <- rep(NA_integer_, length(files))
  want <- status %in% c("parsed", "matched", "exportable") &
          !is.na(bytes) & bytes <= .max_scan_bytes
  for (i in which(want)) {
    n <- tryCatch(
      length(readLines(file.path(path, files[[i]]), warn = FALSE)),
      error = function(e) NA_integer_
    )
    out[[i]] <- as.integer(n)
  }
  out
}
