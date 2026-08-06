# tools/

[`download_cran.R`](download_cran.R) and [`audit_cran.R`](audit_cran.R) contain 
functions used to run pkgaudit on many (often all) packages hosted by CRAN. This
is done to evaluate new and existing rules. It is not expected that most 
pkgaudit users will ever call these functions, so they are provided here and may
be defined by calling `source()` on the scripts.

[`survey_tarballs.R`](survey_tarballs.R) reconstructs the empirical basis for
the default validation caps in `tar_entries()` and `validate_tar()`, surveying a
directory of tarballs for entry counts, path shapes, and expansion ratios
without extracting anything.

`audit_cran()` returns one row per finding with `package` and `version`
prepended. Columns recoverable from the rules are dropped to keep the frames
manageable at CRAN scale: `message`, `attck`, and the nine lifecycle-phase
columns. Join `rules$phases` on `rule` for a file or code context, or on
`code_context` for a pattern, to restore the phases. An expression takes its
phases from the file it was found in, so restoring those takes two joins:
`expressions` to `file_contexts` on `package`, `version`, and `file_context` to
recover the file-context `rule`, then `rules$phases` on that.

**IMPORTANT: Respect your CRAN mirror's bandwidth.** Run `download_cran()` 
infrequently and use `pause` > 0 (default is 0.5) to rate-limit the downloads. 
For more frequent downloads, use `rsync` to host a mirror as described by 
[CRAN](https://cran.r-project.org/mirror-howto.html).

**Install Rd macro packages before a full run.** pkgaudit expands user-defined
Rd macros when it scans a help file, so a `\Sexpr{}` reaching a page through a
macro is still found. A macro a package declares in its DESCRIPTION `RdMacros`
field can only be expanded if the providing package is installed; otherwise
`audit_cran()` records an `extract_Rd_code` "unknown macro" error and the
macro's content is not scanned. Most such macros are display-only (`mathjaxr`'s
`\mjeqn`, `Rdpack`'s `\insertRef`) and inject no code, but installing the common
providers -- at least `mathjaxr` and `Rdpack` -- removes the noise and closes
the blind spot for any macro that does carry a `\Sexpr`.

[`test_coverage.R`](test_coverage.R) is used by the GitHub Actions workflow
`test-coverage.yaml` to report test coverage and generate a CI badge without
relying on an external service.


