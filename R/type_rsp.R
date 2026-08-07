# Extraction for R.rsp vignettes.
#
# An .rsp file is a template: everything is output except what sits between <%
# and %>, where five things can appear and three are R.
#
#   <% code %>      a statement
#   <%= expr %>     an expression, written into the output
#   <%: code %>     code, evaluated and echoed
#   <%@ ... %>      a directive -- meta, include, import -- not R
#   <%% ... %>      an escaped literal delimiter, not R
#
# A "-" before %> trims whitespace, and <%-- --%> is a comment.

#' @export
extract_segments.rsp <- function(source) {
  read <- read_code(source$path)

  errors <- if (is.null(read$error)) .empty_errors() else .error_row(
    step = "read_code", file_context = source$file_context,
    message = read$error
  )
  if (is.null(read$lines)) return(list(segments = list(), errors = errors))

  lines <- .rsp_code(read$lines)
  if (!any(nzchar(trimws(lines)))) {
    return(list(segments = list(), errors = errors))
  }

  list(
    segments = list(new_segment(
      language     = "R",
      lines        = lines,
      file_context = source$file_context,
      context      = source$code_context,
      named_contexts = FALSE
    )),
    errors = errors
  )
}


# Blank out everything that is not R code, leaving the code where it sits.
#
# Working on the joined text and replacing non-code characters with spaces --
# never deleting them -- is what keeps the result line-aligned to the source, so
# a finding's line and column point straight into the .rsp file. A <% %> region
# may span lines, which is why this cannot be done a line at a time.
.rsp_code <- function(lines) {
  text  <- paste(lines, collapse = "\n")
  chars <- strsplit(text, "", fixed = TRUE)[[1L]]
  keep  <- rep(FALSE, length(chars))

  opens  <- .fixed_positions(text, "<%")
  closes <- .fixed_positions(text, "%>")

  i <- 1L
  while (i <= length(opens)) {
    o     <- opens[[i]]
    after <- closes[closes > o + 1L]
    # An unterminated region runs to the end of the file rather than being
    # dropped: truncated input should cost formatting, not coverage.
    c1    <- if (length(after)) after[[1L]] else length(chars) + 1L
    inner <- seq.int(o + 2L, length.out = max(0L, c1 - (o + 2L)))

    # A directive's quoted content can itself contain "<%", so any open inside
    # the region just consumed is text, not the start of another region. Pairing
    # it with a later close would splice the directive into the extracted code.
    i <- i + 1L
    while (i <= length(opens) && opens[[i]] < c1) i <- i + 1L
    if (length(inner) == 0L) next

    body  <- chars[inner]
    first <- which(!(body %in% c(" ", "\t", "\n")))
    if (length(first) == 0L) next
    lead  <- body[[first[[1L]]]]

    # Directives, comments, and the "<%%" escape for a literal delimiter all
    # carry no R. Nothing valid starts an R expression with "%".
    if (lead == "@" || lead == "%") next
    if (lead == "-" && identical(body[first[[1L]] + 1L], "-")) next

    code <- inner
    # "=" and ":" mark what R.rsp does with the value -- write it out, echo it --
    # and are not part of the code. Stripping the marker keeps the code in the
    # scan; skipping the region would lose it, which is the costlier mistake.
    if (lead == "=" || lead == ":") code <- code[-seq_len(first[[1L]])]
    # A lone "-" is a trim marker, as is a trailing one before %>.
    if (length(code) == 0L) next
    tail_ch <- chars[code]
    last    <- which(!(tail_ch %in% c(" ", "\t", "\n")))
    if (length(last) == 0L) next
    if (tail_ch[[last[[length(last)]]]] == "-") {
      code <- code[-last[[length(last)]]]
    }
    keep[code] <- TRUE
  }

  # Two regions can share a line -- <%=a%> <%=b%> -- and each is an independent
  # expression, so they need separating or the result is not parseable. Regions
  # on different lines are already separated by the newline.
  kept <- which(keep)
  if (length(kept) > 1L) {
    newline <- chars == "\n"
    for (k in seq_len(length(kept) - 1L)) {
      a <- kept[[k]]; b <- kept[[k + 1L]]
      if (b > a + 1L && !any(newline[(a + 1L):(b - 1L)])) {
        chars[[a + 1L]] <- ";"
        keep[[a + 1L]]  <- TRUE
      }
    }
  }

  chars[!keep & chars != "\n"] <- " "
  strsplit(paste(chars, collapse = ""), "\n", fixed = TRUE)[[1L]]
}


# Character positions of every occurrence of a fixed pattern, or integer(0).
.fixed_positions <- function(text, pattern) {
  hits <- gregexpr(pattern, text, fixed = TRUE)[[1L]]
  if (length(hits) == 1L && hits[[1L]] == -1L) integer(0L) else as.integer(hits)
}
