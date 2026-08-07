# Renders a pkgaudit summary as text: section layout, aligned tables, and the
# shared width and label helpers.

# --- Summary Rendering --------------------------------------------------------

# Render a summary object as the sectioned report lines.
.format_summary <- function(x, path = TRUE) {
  c(
    .section_header("pkgaudit Summary"),
    .metadata_lines(x$metadata, path = path),
    # A filtered report says so here, so it cannot be read as a full scan of a
    # package whose findings are simply in a phase that was not asked for.
    if (is.null(x$phase)) NULL else
      .field("Phases:", paste(x$phase, collapse = ", ")),
    "",
    .section_header("R Patterns"),
    .summary_section(x$patterns, "No patterns were found."),
    "",
    .section_header("Shell / Make Matches"),
    .summary_section(x$matches, "No matches were found."),
    "",
    .section_header("Errors"),
    .errors_section(x$errors)
  )
}


# Render one summary section: the table, or a message when there is nothing to
# report.
.summary_section <- function(df, empty_message) {
  if (nrow(df) == 0L) empty_message else .format_table(df)
}


# Render the Errors section: the table of every error followed by the notes
# describing the coverage lost, or the all-clear when there were none.
.errors_section <- function(errors) {
  if (nrow(errors) == 0L) return("No exceptions were raised.")
  c(.format_table(errors), "", .error_notes(errors))
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
.format_table <- function(df) {
  columns <- lapply(names(df), function(column) {
    values <- df[[column]]
    text   <- ifelse(is.na(values), "", as.character(values))
    formatC(
      c(column, text),
      width = max(nchar(c(column, text))),
      flag  = if (is.numeric(values)) "" else "-"
    )
  })
  trimws(do.call(paste, c(columns, sep = "   ")), which = "right")
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
