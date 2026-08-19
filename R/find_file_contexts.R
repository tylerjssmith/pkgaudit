#' Find security-relevant file contexts in a package
#'
#' Finds file contexts -- files in an R package that can be executed by
#' `R CMD build`, `R CMD check`, or `R CMD INSTALL` (e.g., `configure`,
#' `src/Makevars`, `src/install.libs.R`).
#'
#' @param pkg Path to the root of the package being audited. Must exist and
#'   be a directory.
#' @param file_context_rules Data frame of file-context rules
#'   (`rules$file_contexts` from [load_rules()]), with columns `name`, `path`,
#'   `recursive`, `filename`, and `message`.
#'
#' @return A list with two data frames:
#'   \describe{
#'     \item{file_contexts}{Data frame with columns `rule` (the matching rule's
#'       name), `file_context` (package-root-relative path; the join key), and
#'       `message`. The phase columns are not set here; [audit_package()]
#'       attaches them from the rules database.}
#'     \item{errors}{Data frame with columns `step`, `file_context`, `rule`,
#'       `message`.}
#'   }
#'
#' @section Security considerations:
#' A rule whose directory is absent contributes nothing and reports nothing --
#' most packages have no `R/unix/`, and that is a clean result. `pkg` itself is
#' checked so that a root that does not exist is refused rather than joining
#' that silence as a package with nothing to scan.
#'
#' A symlinked file is never claimed: following it would attribute findings to
#' the target's path rather than the one the package ships. It is reported in
#' `coverage` as `unexamined` with reason `symlink`, so skipping it is stated
#' rather than silent.
#'
#' @keywords internal
find_file_contexts <- function(pkg, file_context_rules) {
  stopifnot(is.character(pkg), length(pkg) == 1L, dir.exists(pkg))
  stopifnot(is.data.frame(file_context_rules))

  found  <- list()
  errors <- .empty_errors()

  if (is.null(file_context_rules) || nrow(file_context_rules) == 0L) {
    return(list(file_contexts = .empty_file_contexts(with_phases = FALSE),
                errors = errors))
  }

  for (i in seq_len(nrow(file_context_rules))) {
    rule       <- file_context_rules[i, , drop = FALSE]
    search_dir <- file.path(pkg, rule$path)

    hits <- tryCatch(
      {
        matches <- list.files(
          search_dir,
          pattern    = rule$filename,
          recursive  = rule$recursive,
          full.names = TRUE,
          all.files  = TRUE
        )
        # list.files() can return directories whose names match; keep only
        # regular files that actually exist.
        matches <- matches[file.exists(matches) & !dir.exists(matches)]
        # A symlink is skipped, never followed: scanning it would attribute
        # its target's code to the target's path, which no rule claims -- or,
        # for a target outside the package, to a path the scan cannot even
        # re-read. build_coverage() reports it as unexamined/symlink instead.
        # Sys.readlink() is NA where symlinks cannot be read (Windows), which
        # keeps the file: no symlink can exist there to follow.
        link <- Sys.readlink(matches)
        matches[is.na(link) | !nzchar(link)]
      },
      error = function(e) e
    )

    if (inherits(hits, "error")) {
      errors <- rbind(errors, .error_row(
        step         = "find_file_contexts",
        rule         = rule$name,
        message      = conditionMessage(hits)
      ))
      next
    }

    if (length(hits) == 0L) next

    rel <- .relativize(hits, pkg)
    found[[length(found) + 1L]] <- data.frame(
      rule         = rule$name,
      file_context = rel,
      message      = rule$message,
      stringsAsFactors = FALSE
    )
  }

  file_contexts <- if (length(found) == 0L) {
    .empty_file_contexts(with_phases = FALSE)
  } else {
    do.call(rbind, found)
  }

  list(file_contexts = file_contexts, errors = errors)
}
