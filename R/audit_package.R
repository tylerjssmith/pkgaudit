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
#'   provenance. Leave `NULL` for a directory scan. Otherwise a list of `path`
#'   and `sha256`, each a length-one character, and `is_tarball`, a length-one
#'   logical that is not `NA`; these become the scan's provenance, so a
#'   malformed one is refused before the scan rather than silently recorded.
#'
#' @return A [new_pkgaudit()] object: a named list with class `pkgaudit`
#'   containing five data frames and a `metadata` list.
#'   \describe{
#'     \item{file_contexts}{`rule`, `file_context`, `message`, and the phase
#'       columns.}
#'     \item{patterns}{`rule`, `file_context`, `line_number`,
#'       `column_number`, `code_context`, `guarded`, `indirect`, `preview`,
#'       `message`, `attck`, and the phase columns, in that order: the leading
#'       columns are the ones a reader skims, and `message` and `attck` restate
#'       the rule rather than the occurrence. `guarded` and `indirect` say how
#'       the code is reached rather than what it is, and are described under
#'       Details. `code_context` is where the code sits -- the directory or
#'       file it is in, or the lifecycle hook enclosing it -- and is what its
#'       phases are looked up from. Join to the other tables on `file_context`.}
#'     \item{matches}{`rule`, `file_context`, `line_number`,
#'       `column_number`, `preview`, `message`, `attck`, and the phase columns,
#'       ordered as `patterns` is, less the `code_context` a match has no
#'       parse tree to sit in. Regular matches matched in the shell scripts
#'       and Make-like files among the file contexts. Join to the other tables
#'       on `file_context`.}
#'     \item{coverage}{`file_context`, `language`, `status`, `reason`,
#'       `first_line`, `last_line`, `lines`, `bytes`, `rule`, and the phase
#'       columns. One row for every file in the package -- not only the ones
#'       scanned -- saying how well pkgaudit read it and why not better. See
#'       Details.}
#'     \item{errors}{`step`, `file_context`, `rule`, `message`.}
#'     \item{metadata}{List of `pkg_name`, `pkg_version`, `pkg_path`,
#'       `pkg_is_tarball`, `pkg_sha256`, `pkgaudit_version`,
#'       `pkgaudit_rules_version`, `pkgaudit_rules_sha256`, and `scanned`. The
#'       two rules fields describe the database `rules` was read from, and are
#'       `NA` for a rules list that did not come from [load_rules()].}
#'   }
#'   The phase columns are the nine described under Details.
#'
#' @details
#' Every file the scan looks at is found by a file-context rule, and that rule's
#' `type` decides how the file is read: an `R` script is parsed as it stands, an
#' `Rd` help file has its `\examples{}` and `\Sexpr{}` code extracted first, and
#' a `shell` or `make` file is matched line by line against the regex rules.
#' Reading a file yields one or more *segments* of code, which are what the
#' finders actually see; a help file yields two, because its examples and its
#' `\Sexpr` macros run at different phases.
#'
#' A rule's `report` field separates being scanned from being reported. Every
#' rule tells the scan which files to read; only a reporting rule adds a row to
#' `file_contexts`. `report` is `TRUE` where a file runs automatically *and* is
#' matched as text rather than parsed -- the shell and Make-like files, whose
#' contents pkgaudit cannot report on precisely, so the file itself is the
#' finding. `src/install.libs.R` reports too: it is parsed, but its presence
#' alone replaces R's default handling of compiled artifacts. Everything else is
#' scanned just as thoroughly; only the row asserting the file exists is
#' withheld.
#'
#' A file context is claimed by extension, so a language pkgaudit cannot read is
#' left unscanned rather than scanned badly -- the Perl, Python and batch scripts
#' under `exec/`, for instance. Nothing is reported for an unclaimed file, so its
#' absence from the findings is not evidence that it is clean.
#'
#' The `coverage` frame accounts for every file in the package, so that a clean
#' scan can be checked rather than taken on trust. Each row's `status` is one of
#' `parsed` (read as R), `matched` (scanned as text), `exportable` (a language
#' pkgaudit does not read, which [export_unscanned()] can hand to a tool that
#' does), `unexamined` (never read), or `error` (read attempted and refused --
#' too large, unreadable, or would not parse). `reason` says what stood in the
#' way. `unexamined` and `error` are different claims: pkgaudit never tried to
#' read the first and could not read the second. Every `error` row has a
#' matching row in `errors`, and only a failure at a reading step counts: a rule
#' that fails on a file says nothing about the file.
#'
#' Nothing is assumed inert. A `.md` file can be read, parsed and evaluated, and
#' deserializing an `.rda` can execute arbitrary code, so no extension is
#' allowlisted out and coverage never reaches 100%. What the frame offers is not
#' completeness but legibility: what was not examined, and whether it runs.
#' Phases come from where a file sits rather than from what it is named, so a
#' file in a directory no rule anticipates is still reported, with no phases.
#' Version-control and IDE state (`.git/`, `.Rproj.user/`, `renv/library/`) is
#' outside the package and excluded; `.Rbuildignore` is not consulted, since it
#' is written by the package under audit.
#'
#' Recoverable failures in the orchestrated finders are collected in the
#' `errors` data frame rather than aborting the audit. File paths in every
#' returned data frame are relative to the package root.
#'
#' `patterns` and `matches` each carry a `preview`: a display-only excerpt of the
#' line at `line_number`, whitespace collapsed, so the frames can be skimmed
#' without opening the files. A trailing `...` means there is more to see. A long
#' line is windowed on the match rather than cut off at its start, so
#' `column_number` does not index into the preview. A preview from a help file
#' comes from the extracted code, not the `.Rd` text.
#'
#' Each findings data frame also carries one logical column per package
#' lifecycle phase -- `at_autoconf`, `at_build`, `at_check`, `at_install_src`,
#' `at_install_bin`, `at_load`, `at_attach`, `at_unload`, and `at_detach` --
#' which is `TRUE` when that finding's code runs during the phase, so findings
#' can be filtered by when they execute. A file or code context takes its phases
#' from the rule that matched; a pattern inherits them from its `code_context`;
#' a match inherits them from the file context it was found in. A pattern
#' in an ordinary function is `FALSE` for every phase: it runs only if something
#' calls it, and that holds for a function defined in a help-file example too. A
#' finding can belong to several phases, so the phase columns do not partition
#' the rows.
#'
#' Code from a help file is attributed to one of two computed contexts:
#' `Rd_examples`, which `R CMD check` runs, and `Rd_Sexpr`, which is evaluated
#' whenever the page is rendered -- during `R CMD build`, installation from
#' source, and `R CMD check`, but not on installation from a binary package.
#'
#' `patterns` carries two logical columns describing how its code is reached
#' rather than what the code is. `guarded` is `TRUE` for code that ships but
#' the lifecycle does not run -- a `\dontrun{}` or `\donttest{}` block, or a
#' vignette chunk marked `eval=FALSE`. Its phases still come from its context,
#' so they stay an upper bound. `indirect` is `TRUE` where the call was made
#' through the function's name rather than the function, as in
#' `do.call("system", ...)`; such a finding is reported under the rule that owns
#' the name, so filtering on `rule` returns every call to it however it was
#' spelled. See [find_indirect()].
#'
#' Patterns are matched against R's parse tree, matches against the text of
#' a shell script or Make-like file. Text matching has no syntax behind it, so
#' a match reported inside a comment or a quoted string cannot be told
#' apart from one in a live command; see [find_matches()].
#'
#' When called by [audit_tarball()], `.origin` is a list with `path`, `sha256`,
#' and `is_tarball`, which are used for the `metadata` list. When calling
#' [audit_package()] on a package directory directly, leave `NULL`, in which
#' case the directory is hashed with [hash_manifest()].
#'
#' @examples
#' \dontrun{
#' rules  <- load_rules()
#' result <- audit_package("/path/to/somepackage", rules = rules)
#' result$file_contexts
#' result$patterns
#' print(result)
#' }
#'
#' @export
audit_package <- function(path = ".", rules = load_rules(), .origin = NULL) {
  stopifnot(is.character(path), length(path) == 1L, dir.exists(path))
  stopifnot(is.list(rules), all(.rule_classes %in% names(rules)))
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
  file_contexts <- .reported_contexts(found$file_contexts, rules$file_contexts)

  # Rd macros are loaded once for the package. Without them, a \Sexpr reaching a
  # help page through a user-defined macro is invisible to the scan. Loading
  # them reads macro definitions as text; it evaluates nothing.
  macros <- .load_rd_macros(path)

  scanned <- character(0L)
  for (target in .scan_targets(found$file_contexts, rules$file_contexts)) {
    scanned[[target$file_context]] <- target$type
    # Classed by the rule's type, which is the only thing deciding how the file
    # is read, and the only place a new variety of file is named.
    src    <- new_source(file.path(path, target$file_context),
                         target$file_context, target$type, macros,
                         namespace_source = target$namespace_source,
                         code_context     = target$code_context)
    read   <- extract_segments(src)
    errors <- rbind(errors, read$errors)

    for (segment in read$segments) {
      # Classed by the segment's language, which the extractor set. One file may
      # yield several languages, so this is a separate axis from the source.
      hits <- analyze_segment(segment, rules)

      patterns      <- rbind(patterns,      hits$patterns)
      matches       <- rbind(matches,       hits$matches)
      spans         <- rbind(spans,         hits$coverage)
      errors        <- rbind(errors,        hits$errors)
    }
  }

  # Built from the tree rather than from the rules, so a file no rule
  # anticipates is still accounted for. Its phases come from the rule that
  # claimed it, which for the directory-wide coverage rules means a file
  # inherits the phases of where it sits rather than of what it is named.
  coverage <- .merge_coverage(
    build_coverage(path, found$file_contexts, rules$file_contexts,
                   scanned = scanned, errors = errors),
    spans
  )

  file_contexts <- .attach_phases(file_contexts, rules$phases)
  coverage      <- .attach_phases(coverage, rules$phases)
  patterns      <- .resolve_pattern_phases(patterns, rules$phases)
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
.reported_contexts <- function(file_contexts, file_context_rules) {
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


# The files to scan, as a list of list(file_context, type).
#
# The type comes from the rule that matched and selects how the file is read.
# A path is returned once per type even when several rules of that type matched
# it, so a file is read once; .resolve_match_phases() unions the phases of
# every rule that matched a given path.
#
# A path matching rules of two different types is scanned once for each, which
# is the honest reading: the file really does hold both kinds of content.
.scan_targets <- function(file_contexts, file_context_rules) {
  if (nrow(file_contexts) == 0L) return(list())

  i    <- match(file_contexts$rule, file_context_rules$name)
  type <- file_context_rules$type[i]
  # Type "other" means a file pkgaudit does not read. Such a rule exists to
  # account for the file in `coverage` and to give it the phases of where it
  # sits, so it is dropped here rather than dispatched to a reader that would
  # return nothing.
  keep <- !is.na(type) & type != "other"
  if (!any(keep)) return(list())

  pairs <- unique(data.frame(
    file_context     = file_contexts$file_context[keep],
    type             = type[keep],
    # A rules list assembled by hand may not carry the field; treat its absence
    # as "not a namespace source", which withholds the hook rules rather than
    # applying them somewhere they cannot fire.
    namespace_source = if (is.null(file_context_rules$namespace_source)) FALSE
                       else isTRUE_vec(file_context_rules$namespace_source[i][keep]),
    code_context     = if (is.null(file_context_rules$code_context)) .context_top_level
                       else file_context_rules$code_context[i][keep],
    stringsAsFactors = FALSE
  ))
  lapply(seq_len(nrow(pairs)), function(i) as.list(pairs[i, , drop = FALSE]))
}
