# Renders a pkgaudit summary as text: section layout, aligned tables, and the
# shared width and label helpers.

# --- Summary Rendering --------------------------------------------------------

# Render a summary object as the sectioned report lines.
.format_summary <- function(x, path = TRUE) {
  # The two findings tables carry the same columns and are meant to be read
  # together, so they are laid out to one set of widths rather than each to its
  # own content.
  findings <- .shared_widths(x$patterns, x$matches)
  c(
    .section_header("pkgaudit Summary"),
    .metadata_lines(x$metadata, path = path),
    # A filtered report says so here, so it cannot be read as a full scan of a
    # package whose findings are simply in a phase that was not asked for.
    if (is.null(x$phase)) NULL else
      .field("Phases:", paste(x$phase, collapse = ", ")),
    "",
    .section_header("R Patterns"),
    .summary_section(x$patterns, "No patterns were found.", findings),
    "",
    .section_header("Shell / Make Matches"),
    .summary_section(x$matches, "No matches were found.", findings),
    "",
    .section_header("Coverage"),
    .coverage_section(x$coverage),
    "",
    .section_header("Errors"),
    .errors_section(x$errors)
  )
}


# Render the Coverage section: what pkgaudit made of the package, then the
# uncovered code that runs anyway.
#
# Counts with reasons, and no percentage. Nothing is assumed inert, so coverage
# never reaches 100% and a ratio would only ever flatter -- what a reader needs
# is which files were not examined and whether they execute.
.coverage_section <- function(coverage) {
  if (nrow(coverage) == 0L) return("No files were found.")
  .format_table(coverage)
}

# Render one summary section: the table, or a message when there is nothing to
# report.
.summary_section <- function(df, empty_message, widths = NULL) {
  if (nrow(df) == 0L) empty_message else .format_table(df, widths)
}


# Render the Errors section: every error by step and script, followed by the
# notes describing the coverage lost, or the all-clear when there were none.
#
# Only two columns. The rule is already implied by the step for the rules that
# have one, and a message runs long enough to wrap the report -- what the reader
# needs from the table is where to look, and the notes say what it cost.
# "file_context", not "script": an error can be recorded against a Makevars or
# a help page, and file_context is what every frame in the object calls it.
.errors_section <- function(errors) {
  if (nrow(errors) == 0L) return("No exceptions were raised.")
  c(.format_table(errors[, c("step", "file_context")]), "", .error_notes(errors))
}


# Shorten a path from the left, keeping the tail that distinguishes it, so a
# deep directory cannot push the report past its width. Display only; the frame
# carries the whole path.
.elide <- function(x, width = 40L) {
  ifelse(nchar(x) <= width, x,
         paste0("...", substring(x, nchar(x) - width + 4L)))
}


# --- Shared Display Helpers ---------------------------------------------------

# The metadata block shared by the print and summary reports: what was scanned,
# where it came from, and what scanned it.
.metadata_lines <- function(m, path = TRUE) {
  name_part <- .or_unknown(m$pkg_name)
  ver_part  <- if (is.na(m$pkg_version)) "" else paste0(" v", m$pkg_version)
  kind      <- if (isTRUE(m$pkg_is_tarball)) "source tarball" else "source directory"
  pkg_value <- paste0(name_part, ver_part, " (", kind, ")")

  scanned_value <- paste0(
    .format_scanned(m$scanned),
    " with pkgaudit v", .or_unknown(m$pkgaudit_version),
    ", rules v", .or_unknown(m$pkgaudit_rules_version)
  )

  lines <- .field("Package:", pkg_value)
  if (isTRUE(path)) {
    lines <- c(lines, .field("Path:", .or_unknown(m$pkg_path)))
  }
  c(
    lines,
    .field("SHA-256:", .or_unknown(m$pkg_sha256)),
    .field("Scanned:", scanned_value)
  )
}


# The report width. Three characters narrower than a terminal line, so that
# knitr output prefixed with "#> " still fits in 80 columns.
.report_width <- 77L

# Label field widths. The metadata labels are short enough to set their values
# close to the left margin; the finding counts carry longer labels of their own.
.metadata_label_width <- 11L
.count_label_width    <- 16L


# Render one labelled line, padding the label to the given field width.
.field <- function(label, value, width = .metadata_label_width) {
  sprintf("%-*s%s", width, label, as.character(value))
}


# Render a section rule: the label set off by dashes to the report width.
.section_header <- function(label) {
  prefix <- paste0("--- ", label, " ")
  paste0(prefix, strrep("-", max(0L, .report_width - nchar(prefix))))
}


# Render a data frame as aligned text: a header line of column names followed by
# one line per row, columns three spaces apart. Character columns are
# left-aligned and numeric columns right-aligned, and NA renders blank.
# print.data.frame() cannot be used here: it right-aligns character columns and
# reserves a leading gutter for row names.
.format_table <- function(df, widths = NULL) {
  columns <- lapply(names(df), function(column) {
    values <- df[[column]]
    text   <- ifelse(is.na(values), "", as.character(values))
    formatC(
      c(column, text),
      width = max(.column_width(column, values), widths[[column]], 0L),
      flag  = if (is.numeric(values)) "" else "-"
    )
  })
  # Trailing padding is stripped, so the last column carries none; the widths
  # that matter for reading two tables side by side are the ones before it.
  trimws(do.call(paste, c(columns, sep = "   ")), which = "right")
}


# The widths two or more tables of the same shape should share, so that columns
# meant to be compared land in the same place on the page.
.shared_widths <- function(...) {
  frames <- Filter(function(d) !is.null(d) && nrow(d) > 0L, list(...))
  if (length(frames) == 0L) return(NULL)

  columns <- unique(unlist(lapply(frames, names)))
  widths  <- vapply(columns, function(column) {
    max(vapply(frames, function(d) .column_width(column, d[[column]]),
               integer(1L)))
  }, integer(1L))
  as.list(widths)
}


# How wide a column has to be to hold its header and every value in it. A column
# a frame does not have needs nothing.
.column_width <- function(column, values) {
  if (is.null(values)) return(0L)
  max(nchar(c(column, ifelse(is.na(values), "", as.character(values)))))
}


# Render a length-one metadata value, or "<unknown>" when it is absent or NA.
# new_pkgaudit() validates field types but not knownness, so any metadata field
# may be NA in a hand-constructed object; the display renders those uniformly.
.or_unknown <- function(x) {
  if (length(x) != 1L || is.na(x)) "<unknown>" else x
}


# Render the stored ISO 8601 UTC timestamp as "YYYY-MM-DD HH:MM UTC". Falls back
# to the raw stored value if it cannot be parsed, and to "<unknown>" if absent.
.format_scanned <- function(scanned) {
  if (length(scanned) != 1L || is.na(scanned)) return("<unknown>")
  t <- tryCatch(
    as.POSIXct(scanned, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    error = function(e) NA
  )
  if (is.na(t)) return(scanned)
  format(t, "%Y-%m-%d %H:%M UTC", tz = "UTC")
}
