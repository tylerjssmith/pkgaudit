# Turns the errors frame into the sentences a report shows: one per step that
# failed, saying what coverage the scan lost. Each note is a claim about what
# was not scanned, so a wrong one tells a reviewer a file was examined when it
# was not.

# --- Error Notes --------------------------------------------------------------

# Build one note per step that recorded an error, in pipeline order, each
# stating what the failure cost the scan. Notes are wrapped to the report width
# and separated by a blank line.
.error_notes <- function(errors) {
  notes <- character(0L)
  for (step in names(.error_note_builders)) {
    rows <- errors[errors$step == step, , drop = FALSE]
    if (nrow(rows) == 0L) next
    notes <- c(notes, .error_note_builders[[step]](rows))
  }
  # A step this method does not know about still gets counted rather than
  # silently dropped from the notes.
  other <- errors[!errors$step %in% names(.error_note_builders), , drop = FALSE]
  for (step in unique(other$step)) {
    n     <- sum(other$step == step)
    notes <- c(notes, paste0(
      .count(n, "error"), " occurred during ", step,
      ". Findings may not reflect a complete scan."
    ))
  }

  wrapped <- lapply(notes, strwrap, width = .report_width)
  unlist(.interleave(wrapped, ""), use.names = FALSE)
}


# Note builders keyed by step, in the order the steps run. Each takes that
# step's error rows and returns the unwrapped sentences describing them.
.error_note_builders <- list(
  find_file_contexts = function(rows) {
    paste0(
      .count(.n_rules(rows), "file-context rule"),
      " could not be evaluated. Findings may not reflect all ",
      "security-relevant files."
    )
  },
  find_matches = function(rows) {
    n <- .n_scripts(rows)
    paste0(
      .count(.n_rules(rows), "match rule"), " could not be evaluated in ",
      .count(n, "shell or Make-like file"),
      ". Findings may not reflect all matches in ", .those_files(n), "."
    )
  },
  read_code = function(rows) {
    n <- .n_scripts(rows)
    paste0(
      .count(n, "file"), " could not be read in full and ",
      if (n == 1L) "was" else "were", " not completely scanned. Findings do ",
      "not reflect all of the contents of ", .those_files(n), "."
    )
  },
  # Two different failures. An unexpandable macro means the file was read but
  # the code inside the macro was not; a parse warning means the file itself was
  # recovered only in part.
  extract_Rd_code = function(rows) {
    macro <- .macro_rows(rows)
    notes <- character(0L)

    if (any(macro)) {
      n <- .n_scripts(rows[macro, , drop = FALSE])
      providers <- .macro_providers(rows$error[macro])
      notes <- c(notes, paste0(
        .count(n, "help file"), " used Rd macros that could not be expanded, so ",
        "the code inside them was not scanned. Findings do not reflect the ",
        "\\Sexpr code those macros produce",
        if (length(providers)) paste0(
          "; installing ", .and_list(providers), " would recover it"
        ), "."
      ))
    }
    if (any(!macro)) {
      n <- .n_scripts(rows[!macro, , drop = FALSE])
      notes <- c(notes, paste0(
        .count(n, "help file"), " could not be read in full, so the R code in ",
        if (n == 1L) "it" else "them", " may be incomplete. Findings may not ",
        "reflect all of the examples or \\Sexpr code in ",
        if (n == 1L) "that file" else "these files", "."
      ))
    }
    notes
  },
  # The step covers R scripts and the code extracted from help files alike, so
  # the note says "file" and claims only what is true of both: a help file
  # defines no code contexts, so a failure there costs patterns only.
  parse_code = function(rows) {
    n <- .n_scripts(rows)
    paste0(
      .count(n, "file"), " could not be parsed and ",
      if (n == 1L) "was" else "were", " not scanned. ",
      "Findings do not reflect the contents of ", .those_files(n), "."
    )
  },
  find_code_contexts = function(rows) {
    n <- .n_scripts(rows)
    paste0(
      .count(.n_rules(rows), "code-context rule"), " could not be evaluated in ",
      .count(n, "R script"), ". Findings may not reflect all code contexts in ",
      .those_scripts(n), "."
    )
  },
  # Patterns are sought in R scripts and in the code extracted from help files
  # alike, so this note says "file" where the code-context one says "R script".
  find_patterns = function(rows) {
    n <- .n_scripts(rows)
    paste0(
      .count(.n_rules(rows), "pattern rule"), " could not be evaluated in ",
      .count(n, "file"), ". Findings may not reflect all patterns in ",
      .those_files(n), "."
    )
  }
)


# Distinct rules and scripts named in a set of error rows. Either field may be
# NA for a given step, in which case the row count is the best available
# measure and is never reported as zero.
.n_rules   <- function(rows) .n_distinct(rows$rule,   nrow(rows))
.n_scripts <- function(rows) .n_distinct(rows$script, nrow(rows))

.n_distinct <- function(x, fallback) {
  n <- length(unique(x[!is.na(x)]))
  if (n == 0L) fallback else n
}


# "1 R script" / "3 R scripts", and the pronoun that agrees with it.
.count <- function(n, singular, plural = paste0(singular, "s")) {
  paste(n, if (n == 1L) singular else plural)
}

.those_scripts <- function(n) if (n == 1L) "that script" else "these scripts"
.those_files   <- function(n) if (n == 1L) "that file"   else "these files"


# Place sep between the elements of a list, but not around them.
.interleave <- function(items, sep) {
  if (length(items) <= 1L) return(items)
  c(items[1L], unlist(lapply(items[-1L], function(x) list(sep, x)),
                      recursive = FALSE))
}


# --- Rd macros ----------------------------------------------------------------

# Macros a few well-known packages define, used to name a package worth
# installing when a scan could not expand one. Each expands to a \Sexpr carrying
# a real call, so an unexpanded macro hides code that runs at build or render.
#
# Keyed by macro name, never by the audited package's `RdMacros` field: that
# field is attacker-controlled, and pkgaudit must not be made to advise
# installing a package of the audited package's choosing. An unrecognised macro
# is still counted as lost coverage, just without a suggestion.
.rd_macro_providers <- c(
  insertAllCited = "Rdpack",   insertCite   = "Rdpack", insertCited = "Rdpack",
  insertCiteOnly = "Rdpack",   insertFig    = "Rdpack", insertNoCite = "Rdpack",
  insertRef      = "Rdpack",   makeFig      = "Rdpack",
  printExample   = "Rdpack",   runExamples  = "Rdpack",
  loadmathjax = "mathjaxr", mjdeqn  = "mathjaxr", mjeqn  = "mathjaxr",
  mjsdeqn     = "mathjaxr", mjseqn  = "mathjaxr", mjtdeqn = "mathjaxr",
  mjteqn      = "mathjaxr",
  lifecycle = "lifecycle",
  foldstart = "details", foldend = "details"
)

# Which error rows report a macro that could not be expanded.
.macro_rows <- function(rows) {
  !is.na(rows$error) & grepl("unknown macro", rows$error, fixed = TRUE)
}

# The known providers of the macros named in these messages, in a stable order.
# A macro this does not recognise contributes nothing rather than a guess.
.macro_providers <- function(messages) {
  named <- unlist(regmatches(
    messages, gregexpr("unknown macro '\\\\[A-Za-z]+'", messages)
  ))
  named <- sub("^unknown macro '\\\\", "", sub("'$", "", named))
  hits  <- .rd_macro_providers[named[named %in% names(.rd_macro_providers)]]
  unique(unname(hits))
}

# "a", "a and b", "a, b and c"
.and_list <- function(x) {
  if (length(x) <= 1L) return(x)
  paste0(paste(utils::head(x, -1L), collapse = ", "), " and ", utils::tail(x, 1L))
}
