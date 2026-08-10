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

  chunks <- .rmd_chunks(read$lines)
  n      <- length(read$lines)

  segments <- lapply(chunks, function(ch) {
    new_segment(
      language     = ch$language,
      # Line-aligned to the source, as every other extractor is, so a finding's
      # line_number points into the .Rmd with no offset to apply.
      lines        = .blank_except(n, ch$first:ch$last, read$lines),
      file_context = source$file_context,
      context      = source$code_context,
      # A hook assigned in a vignette chunk is not a hook.
      named_contexts = FALSE,
      # A chunk that never evaluates still ships; it is scanned and marked, and
      # keeps the context's phases as an upper bound.
      guarded_lines  = if (ch$eval) integer(0L) else ch$first:ch$last
    )
  })

  list(segments = Filter(Negate(is.null), segments), errors = errors)
}


# Split lines into fenced chunks: list(language, first, last, eval), where first
# and last bound the chunk's code, excluding its fences.
#
# Fences are matched at the start of a line, allowing the leading whitespace a
# chunk inside a list item carries. A chunk with no closing fence runs to the
# end of the file rather than being dropped: truncated input should cost
# formatting, not coverage.
.rmd_chunks <- function(lines) {
  open  <- grepl("^[[:space:]]*```+[[:space:]]*\\{", lines)
  fence <- grepl("^[[:space:]]*```+[[:space:]]*$", lines)

  chunks <- list()
  i <- 1L
  n <- length(lines)
  while (i <= n) {
    if (!open[[i]]) { i <- i + 1L; next }

    header <- .rmd_header(lines[[i]])
    close  <- which(fence & seq_len(n) > i)
    last   <- if (length(close)) close[[1L]] - 1L else n
    if (last >= i + 1L && !is.null(header$language)) {
      chunks[[length(chunks) + 1L]] <- list(
        language = header$language, first = i + 1L, last = last,
        eval = header$eval
      )
    }
    i <- if (length(close)) close[[1L]] + 1L else n + 1L
  }
  chunks
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
  inside <- sub("^[[:space:]]*```+[[:space:]]*\\{", "", line)
  inside <- sub("\\}[[:space:]]*$", "", inside)

  engine <- tolower(trimws(sub("[,[:space:]].*$", "", inside)))
  language <- if (nzchar(engine) && !startsWith(engine, ".") &&
                  !startsWith(engine, "#")) .chunk_language(engine) else NULL

  eval <- !grepl("(^|,)[[:space:]]*eval[[:space:]]*=[[:space:]]*F(ALSE)?[[:space:]]*(,|$)",
                 inside)
  list(language = language, eval = eval)
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
