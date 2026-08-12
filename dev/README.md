# dev/

This directory contains scripts used to snapshot and survey CRAN packages in
support of pkgaudit development. Rules are evaluated at CRAN-scale before a new
version of pkgaudit or its rules database is shipped.

* [`download_cran.R`](download_cran.R) downloads R package source tarballs from
a CRAN mirror, skipping packages that have already been downloaded so that it
can be re-run quickly if some downloads fail. Optionally, it checks MD5 hashes
declared by CRAN and adds SHA-256 hashes, which are more secure.

* [`survey_cran.R`](survey_cran.R) contains functions used to run pkgaudit on
many (e.g., ~25,000) source package tarballs.

* [`survey_tarballs.R`](survey_tarballs.R) contains functions used to establish
the empirical basis for the default validation caps in `tar_entries()` and
`validate_tar()`, surveying a directory of tarballs for entry counts, path
shapes, and expansion ratios without extracting anything to disk.

**IMPORTANT: Respect your CRAN mirror's bandwidth.** Run `download_cran()` 
infrequently and use `pause` > 0 (default is 0.5) to rate-limit the downloads. 
For more frequent downloads, use `rsync` to host a mirror as described by 
[CRAN](https://cran.r-project.org/mirror-howto.html).

**Install Rd macro packages before a full run.** pkgaudit expands user-defined
Rd macros when it scans a help file, so a `\Sexpr{}` reaching a page through a
macro is still found. A macro a package declares in its DESCRIPTION `RdMacros`
field can only be expanded if the providing package is installed; otherwise
`survey_cran()` records an `extract_Rd_code` "unknown macro" error and the
macro's content is not scanned. Most such macros are display-only (`mathjaxr`'s
`\mjeqn`, `Rdpack`'s `\insertRef`) and inject no code, but installing the common
providers -- at least `mathjaxr` and `Rdpack` -- removes the noise and closes
the blind spot for any macro that does carry a `\Sexpr`.


