#' Find security-relevant file contexts in a package
#'
#' Finds files in an R package that can be executed by `R CMD build`,
#' `R CMD check`, or `R CMD INSTALL` (e.g. `configure`,`src/Makevars`,
#' `src/install.libs.R`).
#'
#' @param pkg Path to the root of the package being audited.
#' @param file_context_rules Data frame of file-context rules
#'   (`rules$file_contexts` from [load_rules()]), with columns `name`, `path`,
#'   `recursive`, `pattern`, and `message`.
#'
#' @return A list with two data frames:
#'   \describe{
#'     \item{file_contexts}{Columns `file_context` (package-root-relative path),
#'       `file_path` (same path), and `message`. One row per file found.}
#'     \item{errors}{Columns `stage`, `file_context`, `rule`, `message`.}
#'   }
#'
#' @keywords internal
find_file_contexts <- function(pkg, file_context_rules) {
  stopifnot(is.character(pkg), length(pkg) == 1L)
  stopifnot(is.data.frame(file_context_rules))

  found  <- list()
  errors <- .empty_errors()

  if (is.null(file_context_rules) || nrow(file_context_rules) == 0L) {
    return(list(file_contexts = .empty_file_contexts(), errors = errors))
  }

  for (i in seq_len(nrow(file_context_rules))) {
    rule       <- file_context_rules[i, , drop = FALSE]
    search_dir <- file.path(pkg, rule$path)

    hits <- tryCatch(
      {
        matches <- list.files(
          search_dir,
          pattern    = rule$pattern,
          recursive  = rule$recursive,
          full.names = TRUE,
          all.files  = TRUE
        )
        # list.files() can return directories whose names match; keep only
        # regular files that actually exist.
        matches[file.exists(matches) & !dir.exists(matches)]
      },
      error = function(e) {
        errors <<- rbind(errors, .error_row(
          stage        = "find_file_contexts",
          rule         = rule$name,
          message      = conditionMessage(e)
        ))
        NULL
      }
    )

    if (is.null(hits) || length(hits) == 0L) next

    rel <- .relativize(hits, pkg)
    found[[length(found) + 1L]] <- data.frame(
      file_context = rel,
      file_path    = rel,
      message      = rule$message,
      stringsAsFactors = FALSE
    )
  }

  file_contexts <- if (length(found) == 0L) {
    .empty_file_contexts()
  } else {
    do.call(rbind, found)
  }

  list(file_contexts = file_contexts, errors = errors)
}
