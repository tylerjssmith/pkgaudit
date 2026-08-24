# This script attaches lifecycle phases to the findings frames.
#
# Phases are determined by contexts: file contexts and code contexts have phases
# defined in their rule files. Patterns inherit phases from their file and code
# contexts. Matches inherit them from their file contexts.

# Look up phases for a vector of context keys, returning one row per key.
#
# A key with no row in the phases table resolves to all FALSE. That case is a
# broken rules database rather than a normal condition, and load_rules() rejects
# it up front, so this is a floor and not the mechanism relied upon.
.phase_lookup <- function(keys, phases) {
  out <- .empty_phase_cols(length(keys))
  if (length(keys) == 0L) return(out)

  idx <- match(keys, phases$context)
  hit <- !is.na(idx)
  for (phase in .phase_columns) {
    value      <- logical(length(keys))
    value[hit] <- as.logical(phases[[phase]][idx[hit]])
    out[[phase]] <- value
  }
  out
}


# Attach phase columns to a file-contexts or coverage frame, keyed by its rule.
.attach_phases <- function(df, phases) {
  cbind(df, .phase_lookup(df$rule, phases))
}


# Attach phase columns to the patterns frame.
#
# The phases of a pattern depend on its file and code contexts. Phases are
# resolved based on the first of the following that applies:
#
#   if the code is located in a named code context
#     -> the phases of the code context
#
#   else if the code is located at the top level of its file context
#     -> the phases of the file context
#
#   else if the code is inside a function definition, and the file's rule
#        assumes its functions are called (assume_called: TRUE)
#     -> the phases of whatever encloses it: the Rd_examples or Rd_Sexpr_* block
#        it was lifted out of, or the file context
#
#   else
#     -> no phases at all.
#
# `file_rule` and `rd_context` ride along on the frame for this and are
# dropped before the result is built; they are how a finding knows where it sat.
.resolve_pattern_phases <- function(patterns, rules) {
  out <- .empty_phase_cols(nrow(patterns))
  if (nrow(patterns) == 0L) return(cbind(patterns, out))

  # What a computed context inherits from: the help-page block it came out of
  # where there is one, and the file otherwise.
  inherited <- ifelse(is.na(patterns$rd_context),
                      patterns$file_rule, patterns$rd_context)

  computed <- patterns$code_context %in% .computed_contexts
  keys     <- ifelse(computed, inherited, patterns$code_context)
  out      <- .phase_lookup(keys, rules$phases)

  # A rules list assembled by hand may not carry the flag. Unstated, the
  # assumption is made: phases are an upper bound, and withholding them would
  # report code as running nowhere on the strength of a rule that said nothing.
  # The shipped rules always carry it, and load_rules() refuses a database that
  # leaves it out where code contexts can arise.
  assume_called <- rules$file_contexts$assume_called
  assumed <- if (is.null(assume_called)) {
    rep(TRUE, nrow(patterns))
  } else {
    flag <- assume_called[match(patterns$file_rule, rules$file_contexts$name)]
    is.na(flag) | flag
  }

  silent <- patterns$code_context == .context_in_function & !assumed
  for (phase in .phase_columns) out[[phase]][silent] <- FALSE

  cbind(patterns, out)
}


# Attach phase columns to the matches frame.
#
# A match is found in shell code, which has no code context, so its phases are
# those of the file context it sits in -- the shell script or Make-like file
# itself, or the vignette a shell chunk sits in. Since one path can match more
# than one file-context rule, the phases are the union across every rule that
# matched it.
.resolve_match_phases <- function(matches, file_contexts) {
  out <- .empty_phase_cols(nrow(matches))
  if (nrow(matches) == 0L || nrow(file_contexts) == 0L) {
    return(cbind(matches, out))
  }

  for (phase in .phase_columns) {
    by_path      <- tapply(as.logical(file_contexts[[phase]]),
                           file_contexts$file_context, any)
    value        <- unname(by_path[matches$file_context])
    value[is.na(value)] <- FALSE
    out[[phase]] <- value
  }
  cbind(matches, out)
}
