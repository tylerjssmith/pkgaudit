library(tidyverse)
library(pkgaudit)

source("download_packages.R")
source("pipeline.R")

# --- Download Packages --------------------------------------------------------
# 1. Get list of current packages and versions (n=24,231)
# List retrieved at 12:20am ET on July 7, 2026
all_pkgs = tools::CRAN_package_db()
all_pkgs = all_pkgs[, c("Package","Version")]
write_csv(all_pkgs, "~/pkgaudit/inst/pipeline/packages_on_CRAN.csv")


# 2. Download current packages
downloads = download_r_packages(all_pkgs, dest_dir = "~/pkgaudit.cran")


# During the download 2 packages failed and 15 packages were skipped.
# Failed packages were downloaded with success...
failed = downloads %>%
  filter(status != "downloaded")

failed %>%
  select(Package = package, Version = version) %>%
  download_r_packages(dest_dir = "~/pkgaudit.cran/")


# Skipped packages resulted from duplicates returned by CRAN_package_db()...
all_tarballs = all %>%
  mutate(tarball = paste0(Package, "_", Version, ".tar.gz")) %>%
  pull(tarball)

downloaded_tarballs = list.files("~/pkgaudit.cran/", pattern = "\\.tar\\.gz$")
write_csv(data.frame(tarball = downloaded_tarballs),
  "~/pkgaudit/inst/pipeline/packages_downloaded.csv")

setdiff(downloaded_tarballs, all_tarballs)

all %>%
  arrange(Package, Version) %>%
  duplicated() %>%
  sum()

# The true number of packages (n=24,216) was downloaded.


# --- Scan Packages ------------------------------------------------------------
tictoc::tic()
findings = run_pipeline('~/pkgaudit.cran',
  rules = pkgaudit::load_rules(), workers = 6)
tictoc::toc()
write_rds(findings,
  "~/pkgaudit/inst/pipeline/findings_2026_0707.rds")


# --- Check Results ------------------------------------------------------------
# All 24,216 packages were parsed, but 2 packages had files in R/ subdirectories
# that failed to prase.
findings$errors
findings$errors %>% summarize(n = n_distinct(package))
write_csv(findings$errors,
  "~/pkgaudit/inst/pipeline/findings_2026_0707_errors.csv")


# 4400/24216 (18.2%) of packages had .onLoad or .onAttach hook
findings$findings %>%
  filter(rule == "hook_defined_rule") %>%
  summarize(n = n_distinct(package))
round(4397/24216*100, 1)

# 44/24216 (0.182%) had a finding
findings$findings %>%
  filter(rule != "hook_defined_rule") %>%
  summarize(n = n_distinct(package))
round(44/24216*100, 3)

# 0 packages had >1 finding
findings$findings %>%
  filter(rule != "hook_defined_rule") %>%
  summarise(n = n_distinct(package))


# The most common findings were:
#  - onload_calls_system_rule (n=16)
#  - onload_eval_parse_rule (n=14)
#  - onload_source_rule (n=6)
#  - onload_download_file_rule (n=4)
#  - onload_options_repos_rule (n=3)
#  - onload_calls_curl_rule (n=1)
findings$findings %>%
  filter(rule != "hook_defined_rule") %>%
  count(rule)

# --- Manual Review ------------------------------------------------------------
manual_review = findings$findings %>%
  filter(rule != "hook_defined_rule") %>%
  mutate(tarball = paste0(package, "_", version, ".tar.gz"))
write_csv(manual_review, "~/pkgaudit.cran/_artifacts/manual_review.csv")


copy_by_rule <- function(df, src_dir, dest_dir) {
  stopifnot(all(c("rule", "tarball") %in% names(df)))

  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE)
  }

  rules <- unique(df$rule)

  for (r in rules) {
    rule_dir <- file.path(dest_dir, r)
    if (!dir.exists(rule_dir)) {
      dir.create(rule_dir, recursive = TRUE)
    }

    tarballs <- unique(df$tarball[df$rule == r])
    src_paths <- file.path(src_dir, tarballs)
    dest_paths <- file.path(rule_dir, tarballs)

    exists_mask <- file.exists(src_paths)
    if (any(!exists_mask)) {
      warning(sprintf(
        "Rule '%s': %d file(s) not found in source directory and will be skipped:\n%s",
        r, sum(!exists_mask),
        paste(src_paths[!exists_mask], collapse = "\n")
      ))
    }

    if (any(exists_mask)) {
      ok <- file.copy(
        from = src_paths[exists_mask],
        to = dest_paths[exists_mask],
        overwrite = TRUE
      )
      if (!all(ok)) {
        warning(sprintf(
          "Rule '%s': failed to copy: %s",
          r, paste(src_paths[exists_mask][!ok], collapse = ", ")
        ))
      }
    }
  }

  invisible(NULL)
}

copy_by_rule(manual, "~/pkgaudit.cran/", "~/pkgaudit.cran/_artifacts/manual_review/")





