# Extraction for Sweave and knitr .Rnw vignettes. Code sits between <<options>>=
# and a terminator: a line holding @ alone or followed by whitespace, since
# anything after the @ is documentation -- Sweave itself emits `@ %def x` lines.
# Both flavours share those delimiters.
#
# Inline \Sexpr{} runs at the same time as the chunks around it, so it joins the
# same segment rather than earning one of its own.

#' @export
extract_segments.Rnw <- function(source) {
  read <- read_code(source$path)

  errors <- if (is.null(read$error)) .empty_errors() else .error_row(
    step = "read_code", file_context = source$file_context,
    message = read$error
  )
  if (is.null(read$lines)) return(list(segments = list(), errors = errors))

  found <- .rnw_code(read$lines)
  if (length(found$keep) == 0L) return(list(segments = list(), errors = errors))

  list(
    segments = list(new_segment(
      language     = "R",
      lines        = .blank_except(length(read$lines), found$keep, found$lines),
      file_context = source$file_context,
      context       = NA_character_,
      file_rule     = source$file_rule,
      code_contexts = source$code_contexts,
      guarded_lines  = found$guarded
    )),
    errors = errors
  )
}


# The R in an .Rnw: the lines inside <<>>=/@ chunks, plus any inline \Sexpr.
#
# Returns list(lines, keep, guarded). `lines` is the source with inline \Sexpr
# lines rewritten to hold just their code, `keep` indexes the lines that carry R,
# and `guarded` holds chunk lines whose header says eval=FALSE.
.rnw_code <- function(lines) {
  n     <- length(lines)
  open  <- grepl("^[[:space:]]*<<.*>>=", lines)
  close <- grepl("^[[:space:]]*@([[:space:]].*)?$", lines)

  keep    <- integer(0L)
  guarded <- integer(0L)
  out     <- lines

  i <- 1L
  while (i <= n) {
    if (open[[i]]) {
      shut <- which(close & seq_len(n) > i)
      # An unterminated chunk runs to the end of the file rather than being
      # dropped: truncated input should cost formatting, not coverage.
      last <- if (length(shut)) shut[[1L]] - 1L else n
      if (last >= i + 1L) {
        body <- (i + 1L):last
        keep <- c(keep, body)
        if (grepl("eval[[:space:]]*=[[:space:]]*F(ALSE)?([,>[:space:]]|$)",
                  lines[[i]])) {
          guarded <- c(guarded, body)
        }
      }
      i <- if (length(shut)) shut[[1L]] + 1L else n + 1L
      next
    }
    # Inline \Sexpr{} outside a chunk. Only the innermost braces are read, so a
    # macro spanning lines is left alone rather than guessed at.
    inline <- .inline_code(lines[[i]], .rnw_sexpr_pattern, .rnw_sexpr_code)
    if (!is.na(inline)) {
      out[[i]] <- inline
      keep     <- c(keep, i)
    }
    i <- i + 1L
  }
  list(lines = out, keep = unique(keep), guarded = unique(guarded))
}


# One \Sexpr{} macro, and the code inside it. Only the innermost braces match,
# so a macro whose code itself carries braces is left alone rather than read
# wrongly.
.rnw_sexpr_pattern <- "\\\\Sexpr\\{[^{}]*\\}"

.rnw_sexpr_code <- function(macro) {
  sub("^\\\\Sexpr\\{", "", sub("\\}$", "", macro))
}
