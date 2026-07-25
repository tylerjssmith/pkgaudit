#' @details
#' The main entry points are [audit_package()] and [audit_tarball()], which scan
#' a package source directory and tarball, respectively, and return a
#' [new_pkgaudit()] object holding four result data frames (file_contexts,
#' code_contexts, patterns, errors) plus scan metadata. Its
#' [format()][format.pkgaudit] and [print()][print.pkgaudit] methods render the
#' metadata and finding counts.
#'
#' @seealso [audit_package()] and [audit_tarball()] for the scan entry points;
#'   [print.pkgaudit()] for the rendered summary.
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom DBI dbConnect
#' @importFrom DBI dbDisconnect
#' @importFrom DBI dbGetQuery
#' @importFrom RSQLite SQLite
#' @importFrom digest digest
#' @importFrom xml2 read_xml
#' @importFrom xml2 xml_attr
#' @importFrom xml2 xml_find_all
#' @importFrom xml2 xml_path
#' @importFrom xmlparsedata xml_parse_data
## usethis namespace: end
NULL
