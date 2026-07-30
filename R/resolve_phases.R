# This script attaches lifecycle phases to the findings frames. Phases are a
# property of a context, not of an individual finding: a file context and a code
# context each get theirs from the rule that matched, and a pattern inherits
# them from the code context it sits in.

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
# A pattern's phases are those of its code context, which is either a
# code-context rule name or one of the sentinels determine_code_contexts()
# assigns: "Top-level" for code with no enclosing function, "Other" for code
# inside an ordinary function. Both sentinels have rows in the phases table.
#
# "Other" resolves to no phases at all, which is the intended reading: that code
# runs only if something calls it, never as a consequence of building,
# installing, checking, or loading the package.
.resolve_pattern_phases <- function(patterns, phases) {
  cbind(patterns, .phase_lookup(patterns$code_context, phases))
}
