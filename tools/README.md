# tools/

[`osv_lockfile.R`](osv_lockfile.R) is used by the GitHub Actions workflow
`osv-scanner.yaml`. It writes an `renv.lock` describing pkgaudit's resolved R
dependencies, which OSV-Scanner reads to check them against the Open Source
Vulnerabilities (OSV) database.

[`readme_version.R`](readme_version.R) is used by the GitHub Actions workflow
`rules-db.yaml`. It fails the build when the rules-database version published in
`README.md` is not the one `pkgaudit::rules_version()` returns, which happens
when the database is rebuilt without re-rendering `README.Rmd`.

[`test_coverage.R`](test_coverage.R) is used by the GitHub Actions workflow
`test-coverage.yaml` to report test coverage and generate a CI badge without
relying on an external service.


