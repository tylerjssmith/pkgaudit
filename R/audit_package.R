#' Audit an R source package
#'
#' Finds security-relevant file and code contexts, code patterns, and shell and
#' make matches for review before an R source package is trusted.
#'
#' @param path Path to an R source package root directory. Defaults to the
#'   current directory.
#' @param rules Named list of rules. Defaults to the rules bundled with the
#'   package as returned by [load_rules()].
#' @param .origin Internal. Used by [audit_tarball()] to record tarball
#'   provenance: a list of `path` and `sha256`, each a length-one character, and
#'   `is_tarball`, a length-one logical that is not `NA`. A malformed one is
#'   refused before the scan rather than silently recorded. `NULL` for a
#'   directory scan, which is hashed with [hash_manifest()] instead.
#'
#' @return A [new_pkgaudit()] object: a named list with class `pkgaudit` holding
#'   five data frames and a `metadata` list. Every findings frame carries the
#'   nine phase columns described under Lifecycle phases and joins to the others
#'   on `file_context`. Paths are relative to the package root.
#'   \describe{
#'     \item{file_contexts}{`rule`, `file_context`, `message`.}
#'     \item{patterns}{`rule`, `file_context`, `line_number`, `column_number`,
#'       `code_context`, `guarded`, `indirect`, `preview`, `message`, `attck`.
#'       `code_context` is where the code sits within its file: `top_level`,
#'       `in_function`, an enclosing lifecycle hook, or the part of a help file
#'       it came from.}
#'     \item{matches}{`rule`, `file_context`, `line_number`, `column_number`,
#'       `preview`, `message`, `attck`: regular-expression matches in the shell
#'       and Make-like file contexts. Text matching has no parse tree behind it,
#'       so the three columns `patterns` derives from one -- `code_context`,
#'       `guarded` and `indirect` -- are absent rather than empty.}
#'     \item{coverage}{`file_context`, `language`, `status`, `reason`,
#'       `first_line`, `last_line`, `lines`, `bytes`, `rule`. One row per file
#'       the package carries that is, or could be, code.}
#'     \item{errors}{`step`, `file_context`, `rule`, `message`. Recoverable
#'       failures, collected rather than aborting the scan.}
#'     \item{metadata}{`pkg_name`, `pkg_version`, `pkg_path`, `pkg_is_tarball`,
#'       `pkg_sha256`, `pkgaudit_version`, `pkgaudit_rules_version`,
#'       `pkgaudit_rules_sha256`, `scanned`. The two rules fields are `NA` for a
#'       rules list that did not come from [load_rules()].}
#'   }
#'
#' @details
#' A file-context rule decides which files are read and how. Only some rules
#' report the files they match as findings in their own right; the rest exist to
#' point the scan at code. A file in a language pkgaudit cannot read is left
#' unscanned rather than scanned badly, so a file's absence from `patterns` and
#' `matches` is not evidence that it is clean -- `coverage` is where that
#' question is answered.
#'
#' @section Coverage:
#' `coverage` accounts for the code a package carries, so a clean scan can be
#' checked rather than trusted. `status` is one of `parsed` (read as R),
#' `matched` (scanned as text), `exportable` (a language pkgaudit does not read,
#' which [export_unscanned()] can hand to a tool that does), `unexamined` (never
#' read), or `error` (read attempted and refused); `reason` says what stood in
#' the way. `unexamined` and `error` are different claims: pkgaudit never tried
#' to read the first and could not read the second.
#'
#' `reason` is `NA` where nothing stood in the way, and otherwise one of:
#' `no_analyser` (pkgaudit does not read that language), `no_extractor` (a rule
#' claimed the file but nothing reads that kind of file, as for `DESCRIPTION`),
#' `no_rule` (no rule looks where it sits), `serialized`, `binary`, `symlink`,
#' `too_large` (over the 10 MB scanning limit), `unreadable`, or `unparseable`.
#'
#' A file earns a row when a rule claimed it, or when its name says what kind of
#' file it is, wherever it sits. Files are identified by name and never by
#' content, so a script with no extension -- `tools/build` opening `#!/bin/sh`
#' -- is missed. Coverage never reaches 100% and is not meant
#' to; what it offers is legibility rather than completeness. Deserializing an
#' `.rda` can execute arbitrary code, so serialized objects are reported as
#' executable surface rather than as data. Version-control and IDE state is
#' excluded, and `.Rbuildignore` is not consulted, since the package under audit
#' writes it.
#'
#' @section Lifecycle phases:
#' Every findings frame carries one logical column per phase -- `at_autoconf`,
#' `at_build`, `at_check`, `at_install_src`, `at_install_bin`, `at_load`,
#' `at_attach`, `at_unload` and `at_detach` -- `TRUE` when that finding's code
#' runs then. A finding can belong to several, so the columns do not partition
#' the rows.
#'
#' A file context, and a match found in one, take the phases of the rule that
#' matched. A pattern takes them from where its file sits and where the code
#' sits within it: a lifecycle hook or a part of a help file carries phases of
#' its own, and otherwise the code inherits the phases around it, so the same
#' call reports `at_check` under `tests/` and `at_build` under `data/`. Code
#' inside a function definition inherits too, except where a rule sets
#' `assume_called = FALSE`, as the rules for `R/` do. See `vignette("rules")`.
#'
#' @section Reading a finding:
#' `preview` is a display-only excerpt of the line, whitespace collapsed, so the
#' frames can be skimmed without opening files. A long line is windowed on the
#' match, so `column_number` does not index into it.
#'
#' `guarded` is `TRUE` for code that ships but the lifecycle does not run -- a
#' `\dontrun{}` block, or a vignette chunk suppressed by either `eval=FALSE` in
#' its header or `#| eval: false` beneath it. Its phases still come from its
#' context and remain an upper bound. A document-wide `execute: eval: false` in
#' Quarto front matter is not read, so a chunk it suppresses still reports.
#' `indirect` is `TRUE` where
#' the call was made through the function's name, as in `do.call("system", ...)`,
#' and is reported under the rule that owns the name; see [find_indirect()].
#'
#' Patterns are matched against R's parse tree, matches against text. Text
#' matching has no syntax behind it, so a match inside a comment or a quoted
#' string cannot be told from one in a live command; see [find_matches()].
#'
#' A file over 10 MB is not read at all: a hostile package must not be able to
#' spend the scanner's memory. It still earns a `coverage` row, with `reason`
#' `too_large`, so the skip is reported rather than silent.
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
#' rules  <- load_rules()
#' result <- audit_package(file.path(exdir, "untrustedpkg"), rules = rules)
#' result$file_contexts
#' result$patterns
#' print(result)
#'
#' @export
audit_package <- function(path = ".", rules = load_rules(), .origin = NULL) {
  .check_path(path, "path", dir = TRUE)
  .check_rules(rules)
  .validate_origin(.origin)

  # The finders build frames without phase columns; phases are attached once,
  # from rules$phases, after every file has been scanned.
  patterns      <- .empty_patterns(with_phases = FALSE)
  matches       <- .empty_matches(with_phases = FALSE)
  spans         <- .empty_coverage(with_phases = FALSE)
  errors        <- .empty_errors()

  found  <- find_file_contexts(path, rules$file_contexts)
  errors <- rbind(errors, found$errors)

  # Every rule finds files to scan; only some files are reported as findings.
  file_contexts <- .report_file_contexts(found$file_contexts,
                                         rules$file_contexts)

  # Rd macros are loaded once for the package. Without them, a \Sexpr reaching a
  # help page through a user-defined macro is invisible to the scan. Loading
  # them reads macro definitions as text; it evaluates nothing.
  macros <- .load_rd_macros(path)

  scanned <- character(0L)
  for (fc in .scan_file_contexts(found$file_contexts, rules$file_contexts)) {
    scanned[[fc$file_context]] <- fc$type
    # classed by the rule's type, which is the only thing deciding how the file
    # is read, and the only place a new variety of file is named.
    src    <- new_source(file.path(path, fc$file_context),
                         fc$file_context, fc$type, macros,
                         file_rule     = fc$rule,
                         code_contexts = fc$code_contexts)
    read   <- extract_segments(src)
    errors <- rbind(errors, read$errors)

    for (segment in read$segments) {
      # classed by the segment's language, which the extractor set. One file may
      # yield several languages, so this is a separate axis from the source.
      hits <- analyze_segment(segment, rules)

      patterns      <- rbind(patterns,      hits$patterns)
      matches       <- rbind(matches,       hits$matches)
      spans         <- rbind(spans,         hits$coverage)
      errors        <- rbind(errors,        hits$errors)
    }
  }

  # build coverage frame from the tree rather than from the rules, so a file no
  # rule anticipates is still accounted for.
  coverage <- .merge_coverage(
    build_coverage(path, found$file_contexts, rules$file_contexts,
                   scanned = scanned, errors = errors),
    spans
  )

  # resolve phases
  file_contexts <- .attach_phases(file_contexts, rules$phases)
  coverage      <- .attach_phases(coverage, rules$phases)
  patterns      <- .resolve_pattern_phases(patterns, rules)
  patterns      <- patterns[, setdiff(names(patterns),
                                      .internal_pattern_columns), drop = FALSE]
  matches       <- .resolve_match_phases(matches,
    .attach_phases(found$file_contexts, rules$phases)
  )

  # provenance: hash the tarball as received when scanning one (via
  # audit_tarball), otherwise hash a manifest of the directory.
  if (is.null(.origin)) {
    pkg_is_tarball <- FALSE
    pkg_path       <- path
    pkg_sha256     <- tryCatch(hash_manifest(path)$hash,
                               error = function(e) NA_character_)
  } else {
    pkg_is_tarball <- .origin$is_tarball
    pkg_path       <- .origin$path
    pkg_sha256     <- .origin$sha256
  }

  metadata <- .build_metadata(path, pkg_path, pkg_is_tarball, pkg_sha256, rules)

  new_pkgaudit(
    file_contexts = file_contexts,
    patterns      = patterns,
    matches       = matches,
    coverage      = coverage,
    errors        = errors,
    metadata      = metadata
  )
}

# --- Scanning -----------------------------------------------------------------

# The rows of a found-contexts frame that are findings in their own right.
# `report` is a property of the rule (report: TRUE).
.report_file_contexts <- function(file_contexts, file_context_rules) {
  if (nrow(file_contexts) == 0L) return(file_contexts)

  report <- file_context_rules$report[match(file_contexts$rule,
                                            file_context_rules$name)]
  file_contexts[!is.na(report) & report, , drop = FALSE]
}


# Load a package's Rd macros, or NULL if it defines none and NULL on failure.
# loadPkgRdMacros() reads macro definitions as text; it does not execute.
.load_rd_macros <- function(path) {
  tryCatch(
    suppressWarnings(tools::loadPkgRdMacros(path)),
    error = function(e) NULL
  )
}


# The files to scan, as a list of list(file_context, type, rule, code_contexts).
#
# The type comes from the rule that matched and selects how the file is read.
# The rule travels with the file because a pattern's phases depend on it, and
# `code_contexts` because the rule decides which code contexts can arise inside
# the files it claims.
#
# A path is returned once per (type, rule) even when several rules of that type
# matched it, so a file is read once per distinct reading; a file matching two
# rules of the same type with different code contexts is genuinely two readings.
# .resolve_match_phases() unions the phases of every rule that matched a path.
#
# A path matching rules of two different types is scanned once for each, which
# is the honest reading: the file really does hold both kinds of content.
.scan_file_contexts <- function(file_contexts, file_context_rules) {
  if (nrow(file_contexts) == 0L) return(list())

  i    <- match(file_contexts$rule, file_context_rules$name)
  type <- file_context_rules$type[i]
  # Type "other" means a file pkgaudit does not read. Such a rule exists to
  # account for the file in `coverage` and to give it the phases of where it
  # sits, so it is dropped here rather than dispatched to a reader that would
  # return nothing.
  keep <- !is.na(type) & type != "other"
  if (!any(keep)) return(list())

  # A rules list assembled by hand may not carry the field. Treat its absence as
  # "no code contexts apply", which withholds the hook rules rather than
  # applying them somewhere the probe package measures they cannot fire.
  spec <- if (is.null(file_context_rules$code_context)) {
    rep(NA_character_, sum(keep))
  } else {
    file_context_rules$code_context[i][keep]
  }

  pairs <- unique(data.frame(
    file_context = file_contexts$file_context[keep],
    type         = type[keep],
    rule         = file_contexts$rule[keep],
    code_context = spec,
    stringsAsFactors = FALSE
  ))

  lapply(seq_len(nrow(pairs)), function(j) {
    row <- as.list(pairs[j, , drop = FALSE])
    row$code_contexts <- .named_contexts(row$code_context)
    row$code_context  <- NULL
    row
  })
}


# The code-context rule names a file-context rule's spec declares, or NULL where
# it declares none. "computed" names no rules: only the top_level/in_function
# distinction applies there, and neither is a rule.
.named_contexts <- function(spec) {
  if (length(spec) != 1L || is.na(spec) || identical(spec, "computed")) {
    return(NULL)
  }
  named <- strsplit(spec, "[[:space:]]+")[[1L]]
  named <- named[nzchar(named)]
  if (length(named) == 0L) NULL else named
}
