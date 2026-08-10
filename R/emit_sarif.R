# This script renders a scan as SARIF 2.1.0, the interchange format code
# scanning tools publish results in.

.sarif_schema  <- "https://json.schemastore.org/sarif-2.1.0.json"
.sarif_version <- "2.1.0"
.sarif_info    <- "https://tylerjssmith.github.io/pkgaudit/"

# Every rule links to the rules vignette rather than to its own YAML file. The
# file name is conventional rather than guaranteed, and a link a reviewer cannot
# follow is worse than a coarse one that always resolves.
.sarif_help <- paste0(.sarif_info, "articles/rules.html")

# The findings frames that become results, and the prefix each rule's id takes.
# Ids must be namespaced: `curl` names both a pattern rule and a match rule, and
# merging them would silently combine two rules in every consumer.
.sarif_kinds <- c(file_contexts = "file", patterns = "pattern",
                  matches = "match")


#' Render a scan as SARIF
#'
#' Renders a `pkgaudit` object as a SARIF 2.1.0 document, the format code
#' scanning tools publish results in, so a scan can be read in an editor or
#' loaded by any SARIF consumer.
#'
#' @param object A `pkgaudit` object.
#' @param pretty Logical; if `TRUE` (default) indent the JSON for reading.
#'
#' @return A length-one character vector holding the SARIF document. Nothing is
#'   written; `writeLines()` it where you want it.
#'
#' @details
#' Every finding in `file_contexts`, `patterns` and `matches` becomes a result,
#' located by the path and, where there is one, the line and column. Rule ids
#' are namespaced by the kind of rule -- `pattern/curl`, `match/curl`,
#' `file/configure` -- because a rule name is unique only within its kind.
#'
#' `level` is `warning` for a pattern or match whose code executes during at
#' least one lifecycle phase, and `note` for everything else. That is a mapping
#' of pkgaudit's phase model onto SARIF's severity field, not a severity
#' judgement: pkgaudit does not rank findings, and the line it can draw honestly
#' is between code that runs on its own and code that runs only when called.
#'
#' A file context is always a `note`. It is not a claim about code -- it says a
#' file exists and will execute -- and most packages that build native code have
#' one. Read a `note` on a file context as pkgaudit pointing at something it
#' could only grep, not as a minor finding: across CRAN, 78% of reported file
#' contexts contain no match at all, so often that row is all pkgaudit can say.
#'
#' `partialFingerprints` identifies a finding by its rule, its file, the code
#' context it sits in, and the text of the line -- not by line number, which
#' shifts whenever anything above it is edited. Two occurrences a consumer could
#' not otherwise tell apart are numbered, since a fingerprint repeated within a
#' run makes several findings read as one. The `coverage` frame becomes the
#' `artifacts` array, so a consumer can see which files were never read, and
#' `errors` become execution notifications on the invocation.
#'
#' Requires the jsonlite package, which is a suggested dependency: pkgaudit's
#' short list of imports is part of what a security team evaluates, and only
#' this function needs a JSON writer.
#'
#' @examples
#' \dontrun{
#' result <- audit_package("/path/to/package")
#' writeLines(emit_sarif(result), "pkgaudit.sarif")
#' }
#'
#' @export
emit_sarif <- function(object, pretty = TRUE) {
  stopifnot(inherits(object, "pkgaudit"))
  stopifnot(is.logical(pretty), length(pretty) == 1L, !is.na(pretty))
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("emit_sarif() needs the jsonlite package.\n",
         '  install.packages("jsonlite")', call. = FALSE)
  }

  found <- .sarif_findings(object)
  doc <- list(
    `$schema` = .sarif_schema,
    version   = .sarif_version,
    runs = list(list(
      tool = list(driver = list(
        name           = "pkgaudit",
        version        = .or_null(object$metadata$pkgaudit_version),
        informationUri = .sarif_info,
        rules          = .sarif_descriptors(found)
      )),
      invocations = list(list(
        executionSuccessful = TRUE,
        toolExecutionNotifications = .sarif_notifications(object$errors)
      )),
      artifacts = .sarif_artifacts(object$coverage),
      results   = .sarif_results(found)
    ))
  )

  jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = pretty, null = "null",
                   na = "null")
}


# Every finding, as one frame carrying the columns SARIF needs of it.
#
# The three findings frames differ in what locates a finding -- a file context
# is a whole file, a match has a line, a pattern has a line and a code context
# -- so they are normalised here rather than in three near-identical loops.
.sarif_findings <- function(object) {
  rows <- lapply(names(.sarif_kinds), function(frame) {
    df <- object[[frame]]
    if (is.null(df) || nrow(df) == 0L) return(NULL)
    data.frame(
      id           = paste0(.sarif_kinds[[frame]], "/", df$rule),
      kind         = .sarif_kinds[[frame]],
      rule         = df$rule,
      file_context = df$file_context,
      line         = if (is.null(df$line_number)) NA_integer_ else df$line_number,
      column       = if (is.null(df$column_number)) NA_integer_
                     else df$column_number,
      code_context = if (is.null(df$code_context)) NA_character_
                     else df$code_context,
      guarded      = if (is.null(df$guarded))  NA else df$guarded,
      indirect     = if (is.null(df$indirect)) NA else df$indirect,
      preview      = if (is.null(df$preview)) NA_character_ else df$preview,
      message      = df$message,
      attck        = if (is.null(df$attck)) NA_character_ else df$attck,
      phases       = apply(df[, .phase_columns], 1L, function(on)
                       paste(.phase_columns[as.logical(on)], collapse = " ")),
      runs         = .runs_automatically(df),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, Filter(Negate(is.null), rows))
  if (is.null(out)) {
    return(data.frame(id = character(0L), kind = character(0L),
                      rule = character(0L),
                      file_context = character(0L), line = integer(0L),
                      column = integer(0L), code_context = character(0L),
                      guarded = logical(0L), indirect = logical(0L),
                      preview = character(0L), message = character(0L),
                      attck = character(0L), phases = character(0L),
                      runs = logical(0L), fingerprint = character(0L),
                      stringsAsFactors = FALSE))
  }
  # Deterministic, so two runs over the same package produce the same document,
  # and the occurrence numbering in a fingerprint is stable.
  out <- out[order(out$id, out$file_context, out$line, out$column,
                   method = "radix"), , drop = FALSE]
  out$fingerprint <- .sarif_fingerprints(out)
  out
}


# One reportingDescriptor per rule that produced a finding.
#
# Built from the findings rather than from the rules database, so a descriptor
# can never describe a rule other than the one that actually fired.
.sarif_descriptors <- function(found) {
  if (nrow(found) == 0L) return(list())
  first <- match(sort(unique(found$id), method = "radix"), found$id)

  unname(lapply(first, function(i) {
    # A file-context rule carries no ATT&CK technique, and nzchar(NA) is TRUE,
    # so the NA has to be dropped explicitly or it renders as a null tag.
    tags <- strsplit(.or_empty(found$attck[[i]]), "[[:space:]]+")[[1L]]
    list(
      id               = found$id[[i]],
      name             = found$rule[[i]],
      shortDescription = list(text = found$message[[i]]),
      helpUri          = .sarif_help,
      properties       = list(tags = as.list(tags[nzchar(tags)]))
    )
  }))
}


# One result per finding.
.sarif_results <- function(found) {
  if (nrow(found) == 0L) return(list())

  unname(lapply(seq_len(nrow(found)), function(i) {
    region <- list()
    if (!is.na(found$line[[i]]))   region$startLine   <- found$line[[i]]
    if (!is.na(found$column[[i]])) region$startColumn <- found$column[[i]]

    location <- list(physicalLocation = list(
      # Relative, forward-slashed, no base id: that is what a consumer resolves
      # against the repository root, and it keeps local paths out of the file.
      artifactLocation = list(uri = found$file_context[[i]])
    ))
    if (length(region) > 0L) location$physicalLocation$region <- region

    properties <- list(phases = as.list(
      strsplit(found$phases[[i]], " ")[[1L]]
    ))
    if (!is.na(found$code_context[[i]])) {
      properties$codeContext <- found$code_context[[i]]
    }
    if (!is.na(found$guarded[[i]]))  properties$guarded  <- found$guarded[[i]]
    if (!is.na(found$indirect[[i]])) properties$indirect <- found$indirect[[i]]

    list(
      ruleId  = found$id[[i]],
      level   = .sarif_level(found$kind[[i]], found$runs[[i]]),
      message = list(text = found$message[[i]]),
      locations = list(location),
      partialFingerprints = list(pkgauditFindingV1 = found$fingerprint[[i]]),
      properties = properties
    )
  }))
}


# Warning for a finding about code that runs on its own; note for everything
# else. Not a severity ranking, which pkgaudit does not make.
#
# A file context is always a note, whatever its phases. It is not a claim about
# code -- it says a file exists and will execute -- and most packages that build
# native code have one, so alerting on its presence is inventory rather than a
# finding. That does mean a note can be the only thing said about a script
# pkgaudit could not read: in a CRAN-scale scan, 78% of reported file contexts
# contained no match at all. A note here is pkgaudit pointing, not shrugging.
.sarif_level <- function(kind, runs) {
  if (identical(kind, "file")) return("note")
  if (isTRUE(runs)) "warning" else "note"
}


# A fingerprint per finding: its rule, its file, the context it sits in, and the
# line it sits on as text.
#
# Not the line *number*, which shifts whenever anything above it is edited, so
# an alert would be retired and reopened by an unrelated change. The text of the
# line is what distinguishes one occurrence from another while surviving a move.
#
# Where that is still not enough -- the same call written the same way twice in
# one file -- the occurrences are numbered. A fingerprint repeated within a run
# makes a consumer treat several findings as one, so they must be distinct even
# when nothing about them differs.
.sarif_fingerprints <- function(found) {
  if (nrow(found) == 0L) return(character(0L))

  key <- paste(found$id, found$file_context, .or_empty_vec(found$code_context),
               .or_empty_vec(found$preview), sep = "\r")
  key <- paste(key, ave_seq(key), sep = "\r")
  vapply(key, digest::digest, character(1L), algo = "sha256",
         serialize = FALSE, USE.NAMES = FALSE)
}


# The occurrence number of each element within its own group of equal values.
ave_seq <- function(x) {
  out <- integer(length(x))
  for (k in unique(x)) out[x == k] <- seq_len(sum(x == k))
  out
}


# The coverage frame as SARIF artifacts, so a consumer can see not only what was
# found but what was never read.
.sarif_artifacts <- function(coverage) {
  if (is.null(coverage) || nrow(coverage) == 0L) return(list())
  whole <- coverage[!duplicated(coverage$file_context), , drop = FALSE]

  unname(lapply(seq_len(nrow(whole)), function(i) {
    list(
      location   = list(uri = whole$file_context[[i]]),
      properties = list(
        status   = whole$status[[i]],
        reason   = .or_null(whole$reason[[i]]),
        language = .or_null(whole$language[[i]]),
        lines    = .or_null(whole$lines[[i]]),
        bytes    = .or_null(whole$bytes[[i]])
      )
    )
  }))
}


# Errors as notifications on the invocation. The scan itself succeeded -- an
# error here is coverage lost, not a failed run -- so executionSuccessful stays
# TRUE and each failure is reported against the step that raised it.
.sarif_notifications <- function(errors) {
  if (is.null(errors) || nrow(errors) == 0L) return(list())

  unname(lapply(seq_len(nrow(errors)), function(i) {
    out <- list(
      level      = "error",
      message    = list(text = errors$message[[i]]),
      descriptor = list(id = errors$step[[i]])
    )
    if (!is.na(errors$file_context[[i]])) {
      out$locations <- list(list(physicalLocation = list(
        artifactLocation = list(uri = errors$file_context[[i]])
      )))
    }
    if (!is.na(errors$rule[[i]])) {
      out$associatedRule <- list(id = errors$rule[[i]])
    }
    out
  }))
}


# NULL for an absent or NA value, so it renders as JSON null rather than as the
# string "NA".
.or_null <- function(x) if (length(x) != 1L || is.na(x)) NULL else unname(x)

# "" for an absent or NA value, for building a key where a gap must be stable.
.or_empty <- function(x) if (length(x) != 1L || is.na(x)) "" else x
.or_empty_vec <- function(x) ifelse(is.na(x), "", as.character(x))
