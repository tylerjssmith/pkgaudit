#' Audit an R source package
#'
#' Finds security-relevant file and code contexts, code patterns, and shell and
#' make expressions for review before an R source package is trusted.
#'
#' @param path Path to an R source package root directory. Defaults to the
#'   current directory.
#' @param rules Named list of rules. Defaults to the rules bundled with the
#'   package as returned by [load_rules()].
#' @param .origin Internal. Used by [audit_tarball()] to record tarball
#'   provenance. Leave `NULL` for a directory scan.
#'
#' @return A [new_pkgaudit()] object: a named list with class `pkgaudit`
#'   containing five data frames and a `metadata` list.
#'   \describe{
#'     \item{file_contexts}{`rule`, `file_context`, `message`, and the phase
#'       columns.}
#'     \item{code_contexts}{`rule`, `file_context`, `line_number`,
#'       `column_number`, `message`, and the phase columns. Join to
#'       `file_contexts` on `file_context`.}
#'     \item{patterns}{`rule`, `file_context`, `line_number`,
#'       `column_number`, `message`, `attck`, `code_context`, and the phase
#'       columns. Join to the other tables on `file_context`, and to
#'       `code_contexts$rule` on `code_context`.}
#'     \item{expressions}{`rule`, `file_context`, `line_number`,
#'       `column_number`, `message`, `attck`, and the phase columns. Regular
#'       expressions matched in the shell scripts and Make-like files among the
#'       file contexts. Join to the other tables on `file_context`.}
#'     \item{errors}{`stage`, `file_context`, `rule`, `message`.}
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
#' Reading a file yields one or more *streams* of code, which are what the
#' finders actually see; a help file yields two, because its examples and its
#' `\Sexpr` macros run at different phases.
#'
#' A rule's `report` field separates being scanned from being reported. Rules
#' for `R/` and `man/` exist to tell the scan which files to read and do not
#' report, so `file_contexts` stays a list of security-relevant files rather
#' than an inventory of the package.
#'
#' Recoverable failures in the orchestrated finders are collected in the
#' `errors` data frame rather than aborting the audit. File paths in every
#' returned data frame are relative to the package root.
#'
#' Each findings data frame also carries one logical column per package
#' lifecycle phase -- `at_autoconf`, `at_build`, `at_check`, `at_install_src`,
#' `at_install_bin`, `at_load`, `at_attach`, `at_unload`, and `at_detach` --
#' which is `TRUE` when that finding's code runs during the phase, so findings
#' can be filtered by when they execute. A file or code context takes its phases
#' from the rule that matched; a pattern inherits them from its `code_context`;
#' an expression inherits them from the file context it was found in. A pattern
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
#' Patterns are matched against R's parse tree, expressions against the text of
#' a shell script or Make-like file. Text matching has no syntax behind it, so
#' an expression reported inside a comment or a quoted string cannot be told
#' apart from one in a live command; see [find_regex()].
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
  stopifnot(
    is.list(rules),
    all(c("file_contexts", "code_contexts", "patterns", "regex", "phases") %in%
          names(rules))
  )

  # The finders build frames without phase columns; phases are attached once,
  # from rules$phases, after every file has been scanned.
  errors        <- .empty_errors()
  code_contexts <- .empty_code_contexts(with_phases = FALSE)
  patterns      <- .empty_patterns(with_phases = FALSE)
  expressions   <- .empty_expressions(with_phases = FALSE)

  found  <- find_file_contexts(path, rules$file_contexts)
  errors <- rbind(errors, found$errors)

  # Every rule finds files to scan; only a reporting rule contributes a finding.
  # Discovery and reporting are separate concerns, so that adding rules for R/
  # and man/ -- which exist to be read, not flagged -- leaves the file_contexts
  # frame the short list of security-relevant files it has always been.
  file_contexts <- .reported_contexts(found$file_contexts, rules$file_contexts)

  # Rd macros are loaded once for the package. Without them, a \Sexpr reaching a
  # help page through a user-defined macro is invisible to the scan. Loading
  # them reads macro definitions as text; it evaluates nothing.
  macros <- .load_rd_macros(path)

  for (target in .scan_targets(found$file_contexts, rules$file_contexts)) {
    read   <- .read_streams(file.path(path, target$file_context), target$type,
                            target$file_context, macros)
    errors <- rbind(errors, read$errors)

    for (stream in read$streams) {
      analyzed <- .analyze_stream(stream, target$file_context, rules)
      code_contexts <- rbind(code_contexts, analyzed$code_contexts)
      patterns      <- rbind(patterns,      analyzed$patterns)
      expressions   <- rbind(expressions,   analyzed$expressions)
      errors        <- rbind(errors,        analyzed$errors)
    }
  }

  file_contexts <- .attach_phases(file_contexts, rules$phases)
  code_contexts <- .attach_phases(code_contexts, rules$phases)
  patterns      <- .resolve_pattern_phases(patterns, rules$phases)
  expressions   <- .resolve_expression_phases(expressions, file_contexts)

  # provenance: hash the tarball as received when scanning one (via
  # audit_tarball), otherwise hash a manifest of the directory.
  if (is.null(.origin)) {
    pkg_is_tarball <- FALSE
    pkg_path       <- path
    pkg_sha256     <- tryCatch(hash_manifest(path)$hash,
                               error = function(e) NA_character_)
  } else {
    pkg_is_tarball <- isTRUE(.origin$is_tarball)
    pkg_path       <- .origin$path
    pkg_sha256     <- .origin$sha256
  }

  metadata <- .build_metadata(path, pkg_path, pkg_is_tarball, pkg_sha256, rules)

  new_pkgaudit(
    file_contexts = file_contexts,
    code_contexts = code_contexts,
    patterns      = patterns,
    expressions   = expressions,
    errors        = errors,
    metadata      = metadata
  )
}

# --- Scanning -----------------------------------------------------------------

# The rows of a found-contexts frame that are findings in their own right.
# `report` is a property of the rule that matched, which the found contexts do
# not carry, so it is looked up in the rules that produced them.
.reported_contexts <- function(file_contexts, file_context_rules) {
  if (nrow(file_contexts) == 0L) return(file_contexts)

  report <- file_context_rules$report[match(file_contexts$rule,
                                            file_context_rules$name)]
  file_contexts[!is.na(report) & report, , drop = FALSE]
}


# The files to scan, as a list of list(file_context, type).
#
# The type comes from the rule that matched and selects how the file is read.
# A path is returned once per type even when several rules of that type matched
# it, so a file is read once; .resolve_expression_phases() unions the phases of
# every rule that matched a given path.
#
# A path matching rules of two different types is scanned once for each, which
# is the honest reading: the file really does hold both kinds of content.
.scan_targets <- function(file_contexts, file_context_rules) {
  if (nrow(file_contexts) == 0L) return(list())

  type <- file_context_rules$type[match(file_contexts$rule,
                                        file_context_rules$name)]
  keep <- !is.na(type)
  if (!any(keep)) return(list())

  pairs <- unique(data.frame(
    file_context = file_contexts$file_context[keep],
    type         = type[keep],
    stringsAsFactors = FALSE
  ))
  lapply(seq_len(nrow(pairs)), function(i) as.list(pairs[i, , drop = FALSE]))
}


# Load a package's Rd macros, or NULL if it defines none and NULL on failure.
#
# A macro package named in DESCRIPTION's RdMacros field may not be installed,
# which warns; an unreadable macro file may error. Neither is a reason to abort
# a scan, and neither executes anything: loadPkgRdMacros() reads macro
# definitions as text.
.load_rd_macros <- function(path) {
  tryCatch(
    suppressWarnings(tools::loadPkgRdMacros(path)),
    error = function(e) NULL
  )
}


# Run one stream through the analyzer its language calls for, returning the
# rows it produced for each findings frame.
#
# An R stream with no code context of its own is a script: its patterns are
# placed by determine_code_contexts(), and it can define code contexts. A
# stream that names its context came from a help file, where the context is
# known from which part of the file the code was in.
.analyze_stream <- function(stream, file_context, rules) {
  out <- list(
    code_contexts = .empty_code_contexts(with_phases = FALSE),
    patterns      = .empty_patterns(with_phases = FALSE),
    expressions   = .empty_expressions(with_phases = FALSE),
    errors        = .empty_errors()
  )

  if (identical(stream$language, "shell")) {
    fr              <- find_regex(stream$lines, rules$regex, file_context)
    out$expressions <- fr$expressions
    out$errors      <- fr$errors
    return(out)
  }

  parsed <- parse_code(stream$lines)
  if (!is.null(parsed$error)) {
    out$errors <- .error_row(
      stage        = "parse_code",
      file_context = file_context,
      message      = parsed$error
    )
    return(out)
  }
  tree     <- parsed$tree
  is_script <- is.na(stream$context)

  if (is_script) {
    cc                <- find_code_contexts(tree, rules$code_contexts,
                                            file_context)
    out$code_contexts <- cc$code_contexts
    out$errors        <- rbind(out$errors, cc$errors)
  }

  fp         <- find_patterns(tree, rules$patterns, file_context)
  out$errors <- rbind(out$errors, fp$errors)

  pat <- fp$patterns
  if (nrow(pat) > 0L) {
    # A help file defines no code contexts of its own -- a hook assigned in an
    # example is not a hook -- so the named rules are withheld and only the
    # Top-level/Other distinction is computed. Code at the top level of the
    # stream takes the stream's context; code inside a function definition
    # stays "Other", since it runs only if something calls it.
    pat <- determine_code_contexts(
      tree, pat,
      if (is_script) rules else utils::modifyList(rules, list(code_contexts = NULL))
    )
    if (!is_script) {
      pat$code_context[pat$code_context == .context_top_level] <- stream$context
    }
  } else {
    pat$code_context <- character(0L)
  }
  # drop the node handle before accumulating; rbind() ignores attributes.
  attr(pat, "nodes") <- NULL
  out$patterns <- pat[, names(.empty_patterns(with_phases = FALSE)),
                      drop = FALSE]
  out
}

# --- Metadata construction ----------------------------------------------------

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
