# This script attaches lifecycle phases to the findings frames. Phases are a
# property of a context, not of an individual finding: a file context and a code
# context each get theirs from the rule that matched, a pattern inherits them
# from the code context it sits in, and a match inherits them from the
# file context it was found in.

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


# Attach phase columns to a file- or code-contexts frame, keyed by its rule.
.attach_phases <- function(df, phases) {
  cbind(df, .phase_lookup(df$rule, phases))
}


# Attach phase columns to the patterns frame.
#
# A phase is a property of both where the file sits and where the code sits
# within it, so resolving one walks a chain, first match winning:
#
#   1. the code context is a rule -- a lifecycle hook, or a part of a help file
#      -- and carries phases of its own.
#   2. the file context overrides `in_function`, and says so outright.
#   3. the code is inside a function definition, and takes the phases of the
#      segment around it.
#   4. otherwise it is top-level code, and takes the file context's phases.
#
# Steps 3 and 4 are the same lookup: code inherits from where it sits. They are
# written apart because only 3 can be overridden, and because the distinction is
# what the override is choosing between. Both readings are measured -- a
# function called from top level fires wherever that top-level code does, and
# one nothing calls fires nowhere -- so a rule that overrides is choosing which
# measurement to report, not asserting something unmeasured.
#
# `file_rule` and `segment_context` are carried on the frame for this and
# dropped before the result is built; they are how a pattern knows where it sat.
.resolve_pattern_phases <- function(patterns, rules) {
  out <- .empty_phase_cols(nrow(patterns))
  if (nrow(patterns) == 0L) return(cbind(patterns, out))

  # Where a pattern inherits from: the segment's own context where it has one,
  # as a help file's \examples does, and the file context otherwise.
  inherited <- ifelse(is.na(patterns$segment_context),
                      patterns$file_rule, patterns$segment_context)

  computed <- patterns$code_context %in% .computed_contexts
  keys     <- ifelse(computed, inherited, patterns$code_context)

  out <- .phase_lookup(keys, rules$phases)
  .apply_phase_overrides(out, patterns, rules$phase_overrides)
}


# Replace the phases of any row a file context overrides for its code context.
#
# Applied after the chain rather than inside it so that an override is visibly
# the last word: whatever the row would have inherited, this is what the rule
# says it carries.
.apply_phase_overrides <- function(out, patterns, overrides) {
  if (is.null(overrides) || nrow(overrides) == 0L) return(cbind(patterns, out))

  hit <- match(paste(patterns$file_rule, patterns$code_context, sep = "\r"),
               paste(overrides$file_context, overrides$code_context, sep = "\r"))
  for (phase in .phase_columns) {
    out[[phase]][!is.na(hit)] <- as.logical(overrides[[phase]][hit[!is.na(hit)]])
  }
  cbind(patterns, out)
}


# Attach phase columns to the matches frame.
#
# An match is found in a shell script or Make-like file, which has no code
# context, so its phases are those of the file context it sits in. That key is a
# path rather than a rule name, and one path ca match more than one
# file-context rule, so the phases are the union across every rule that matched
# it: the file is executed whenever any of those rules says it is.
#
# file_contexts must already carry its phase columns. A path with no row there
# resolves to no phases, which cannot arise from a scan -- matches are only
# sought in files that are file contexts -- and is a floor for a hand-built
# frame rather than the mechanism relied upon.
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
