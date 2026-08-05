# This script attaches lifecycle phases to the findings frames. Phases are a
# property of a context, not of an individual finding: a file context and a code
# context each get theirs from the rule that matched, a pattern inherits them
# from the code context it sits in, and an expression inherits them from the
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


# Attach phase columns to the expressions frame.
#
# An expression is found in a shell script or Make-like file, which has no code
# context, so its phases are those of the file context it sits in. That key is a
# path rather than a rule name, and one path can match more than one
# file-context rule, so the phases are the union across every rule that matched
# it: the file is executed whenever any of those rules says it is.
#
# file_contexts must already carry its phase columns. A path with no row there
# resolves to no phases, which cannot arise from a scan -- expressions are only
# sought in files that are file contexts -- and is a floor for a hand-built
# frame rather than the mechanism relied upon.
.resolve_expression_phases <- function(expressions, file_contexts) {
  out <- .empty_phase_cols(nrow(expressions))
  if (nrow(expressions) == 0L || nrow(file_contexts) == 0L) {
    return(cbind(expressions, out))
  }

  for (phase in .phase_columns) {
    by_path      <- tapply(as.logical(file_contexts[[phase]]),
                           file_contexts$file_context, any)
    value        <- unname(by_path[expressions$file_context])
    value[is.na(value)] <- FALSE
    out[[phase]] <- value
  }
  cbind(expressions, out)
}
