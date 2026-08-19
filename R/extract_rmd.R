# Extraction for knitr-style literate documents: .Rmd, and .qmd which inherits
# from it because the chunk syntax is the same.
#
# Engine-agnostic by design: a segment is emitted for every chunk, tagged with
# the language its header names, never filtered to `r`. A `bash` chunk is shell
# that runs when the vignette is built; a language with no analyser falls
# through to analyze_segment.default() and finds nothing.

#' @export
extract_segments.Rmd <- function(source) {
  read <- read_code(source$path)

  errors <- if (is.null(read$error)) .empty_errors() else .error_row(
    step = "read_code", file_context = source$file_context,
    message = read$error
  )
  if (is.null(read$lines)) return(list(segments = list(), errors = errors))

  found  <- .rmd_chunks(read$lines)
  chunks <- found$chunks
  n      <- length(read$lines)

  segments <- lapply(chunks, function(ch) {
    new_segment(
      language     = ch$language,
      # Line-aligned to the source, as every other extractor is, so a finding's
      # line_number points into the .Rmd with no offset to apply.
      lines        = .blank_except(n, ch$first:ch$last, found$lines),
      file_context  = source$file_context,
      # No label of its own: a chunk belongs to the file context it sits in.
      context       = NA_character_,
      file_rule     = source$file_rule,
      code_contexts = source$code_contexts,
      # A chunk that never evaluates still ships; it is scanned and marked, and
      # keeps the context's phases as an upper bound.
      guarded_lines  = if (ch$eval) integer(0L) else ch$first:ch$last
    )
  })

  # Inline code runs when the document is rendered, exactly as the chunks do,
  # and it is always R. It gets one segment of its own rather than joining a
  # chunk's, since it belongs to no chunk.
  inline <- .rmd_inline(read$lines, chunks)
  if (length(inline$keep)) {
    segments <- c(segments, list(new_segment(
      language      = "R",
      lines         = .blank_except(n, inline$keep, inline$lines),
      file_context  = source$file_context,
      context       = NA_character_,
      file_rule     = source$file_rule,
      code_contexts = source$code_contexts,
      # Inline code carries no eval option; there is nowhere to put one.
      guarded_lines = integer(0L)
    )))
  }

  list(segments = Filter(Negate(is.null), segments), errors = errors)
}


# Split lines into fenced chunks. Returns list(chunks, lines): each chunk is
# list(language, first, last, eval), where first and last bound the chunk's
# code excluding its fences, and `lines` is the source with any blockquote
# markers inside chunk bodies turned to spaces.
#
# Fences are matched at the start of a line, allowing the leading whitespace a
# chunk inside a list item carries and the `>` a blockquoted chunk carries --
# knitr evaluates both. A chunk with no closing fence runs to the end of the
# file rather than being dropped: truncated input should cost formatting, not
# coverage.
.rmd_chunks <- function(lines) {
  open  <- grepl("^[[:space:]>]*```+[[:space:]]*\\{", lines)
  fence <- grepl("^[[:space:]>]*```+[[:space:]]*$", lines)

  chunks <- list()
  out <- lines
  i <- 1L
  n <- length(lines)
  while (i <= n) {
    if (!open[[i]]) { i <- i + 1L; next }

    header <- .rmd_header(lines[[i]])
    close  <- which(fence & seq_len(n) > i)
    last   <- if (length(close)) close[[1L]] - 1L else n
    if (last >= i + 1L && !is.null(header$language)) {
      body <- (i + 1L):last
      # knitr strips the blockquote markers before evaluating, so the body of a
      # quoted chunk is code, not prose. They become spaces rather than being
      # removed, so every column keeps its position in the source line.
      if (grepl(">", sub("```.*$", "", lines[[i]]), fixed = TRUE)) {
        out[body] <- .unquote_lines(out[body])
      }
      chunks[[length(chunks) + 1L]] <- list(
        language = header$language, first = i + 1L, last = last,
        # Either syntax can suppress a chunk, so either is enough to guard it.
        eval = header$eval && .rmd_pipe_eval(out[body])
      )
    }
    i <- if (length(close)) close[[1L]] + 1L else n + 1L
  }
  list(chunks = chunks, lines = out)
}


# Turn the blockquote markers at the start of each line into spaces of the same
# width. Only the leading run of `>`, spaces and tabs is touched, so a `>` in
# the code itself is left alone.
.unquote_lines <- function(lines) {
  at <- regexpr("^[> \t]*", lines)
  regmatches(lines, at) <- chartr(">", " ", regmatches(lines, at))
  lines
}


# The language and eval option of a chunk header such as ```{r name, eval=FALSE}
#
# The language is the first word inside the braces. Everything after the first
# comma is options; only eval is read, and only when it is a literal FALSE. An
# eval option computed at render time is not resolved -- doing so would mean
# evaluating the document's code, which pkgaudit never does -- so it is left
# unguarded, which reports more rather than less.
#
# A first word beginning with "." or "#" is a Pandoc class or id, not an engine:
# ```{.r} marks a block to be syntax-highlighted in the rendered page, and its
# contents are printed rather than run. Such a block has no language, so it
# yields no segment.
.rmd_header <- function(line) {
  inside <- sub("^[[:space:]>]*```+[[:space:]]*\\{", "", line)
  inside <- sub("\\}[[:space:]]*$", "", inside)

  engine <- tolower(trimws(sub("[,[:space:]].*$", "", inside)))
  language <- if (nzchar(engine) && !startsWith(engine, ".") &&
                  !startsWith(engine, "#")) .chunk_language(engine) else NULL

  eval <- !grepl("(^|,)[[:space:]]*eval[[:space:]]*=[[:space:]]*F(ALSE)?[[:space:]]*(,|$)",
                 inside)
  list(language = language, eval = eval)
}


# The inline R in a document: `r expr` as knitr writes it, and `{r} expr` as
# Quarto does. Returns list(lines, keep) in the shape .blank_except() wants,
# with each expression sitting at the column it occupies in the source.
#
# Two kinds of line are skipped. A line inside a fenced chunk is already a
# segment of its own, and reading it again would report its code twice. A span
# written with doubled backticks -- `` `r x` `` -- is how a document displays
# inline code without running it. The YAML front matter is not skipped: knitr
# evaluates inline code there too, so a title can run code at render.
.rmd_inline <- function(lines, chunks) {
  n    <- length(lines)
  out  <- lines
  keep <- integer(0L)

  skip <- logical(n)
  for (ch in chunks) skip[ch$first:ch$last] <- TRUE
  # Fence lines themselves sit outside every chunk's body but carry no prose.
  skip <- skip | grepl("^[[:space:]>]*```", lines)

  for (i in seq_len(n)) {
    if (skip[[i]]) next
    code <- .inline_code(.mask_verbatim(lines[[i]]),
                         .rmd_inline_pattern, .rmd_inline_code)
    if (!is.na(code)) {
      out[[i]] <- code
      keep     <- c(keep, i)
    }
  }
  list(lines = out, keep = keep)
}


# Blank out every doubled-backtick span, which is how a document shows inline
# code without running it: `` `r x` `` displays the text rather than evaluating
# it. Replaced with spaces of the same width rather than removed, so every
# column after the span stays where it was.
.mask_verbatim <- function(line) {
  spans <- gregexpr("``.*?``", line)[[1L]]
  if (spans[[1L]] == -1L) return(line)
  widths <- attr(spans, "match.length")
  for (i in seq_along(spans)) {
    substr(line, spans[[i]], spans[[i]] + widths[[i]] - 1L) <-
      strrep(" ", widths[[i]])
  }
  line
}


# One inline expression, in either syntax, and the code inside it. Neither form
# may contain a backtick, so neither runs past its own closing one. knitr
# accepts `#` in place of the space after the r, so `r#expr` is read too.
.rmd_inline_pattern <- "`(?:\\{r\\}|r)[ \t#][^`]*`"

.rmd_inline_code <- function(macro) {
  sub("^`(\\{r\\}|r)[ \t#]", "", sub("`$", "", macro))
}


# Whether a chunk's hash-pipe options let it evaluate. Quarto writes chunk
# options as YAML comments on the lines after the fence:
#
#   ```{r}
#   #| eval: false
#
# knitr reads the same syntax, so this is not Quarto-only. The options run until
# the first line that is not one, which is what keeps a `#|` written further
# down, inside the code, from being read as an option.
#
# Only a literal false counts, as in the header form: an option computed at
# render time is left unguarded, since resolving it would mean evaluating the
# document.
.rmd_pipe_eval <- function(body) {
  is_pipe <- grepl("^[[:space:]]*#\\|", body)
  pipe    <- body[cumsum(!is_pipe) == 0L]
  if (length(pipe) == 0L) return(TRUE)
  !any(grepl(
    "^[[:space:]]*#\\|[[:space:]]*eval[[:space:]]*:[[:space:]]*(false|FALSE|F)[[:space:]]*$",
    pipe
  ))
}


# The analyser language a chunk engine feeds. knitr engine names are lowercase,
# while the analysers are classed "R" and "shell", so the two have to be mapped.
#
# An engine with no entry keeps its own name and falls through to
# analyze_segment.default(): no findings, no error. Adding a language later is
# an entry here plus an analyser, and touches nothing else.
.chunk_engines <- c(r = "R", bash = "shell", sh = "shell", zsh = "shell")

.chunk_language <- function(engine) {
  if (engine %in% names(.chunk_engines)) .chunk_engines[[engine]] else engine
}


# A character vector of length n holding `lines` at the given indices and "" at
# every other position, so a segment lines up with the file it came from.
.blank_except <- function(n, keep, lines) {
  out <- rep("", n)
  out[keep] <- lines[keep]
  out
}
