# Security Policy

## Reporting a vulnerability

Please report security issues privately, not in public issues.

Use GitHub’s private vulnerability reporting (Security → Report a
vulnerability).

I aim to acknowledge reports within one week.

## Scope

This policy covers vulnerabilities in pkgaudit itself — for example, a
crafted package or tarball that causes pkgaudit to write outside its
extraction directory or execute code while scanning.

pkgaudit does not execute the code it analyses. If you believe you have
found a vulnerability or malicious code in some *other* R package, that
is not a pkgaudit issue: contact that package’s maintainer, and CRAN
(<cran@r-project.org>) if it is distributed there.

## Security model

pkgaudit analyses packages without executing them, and reads from but
does not write to disk with one exception:
[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
extracts the tarball to a temporary directory (`temp_dir`, default
[`tempdir()`](https://rdrr.io/r/base/tempfile.html)) and removes it when
finished.

Untrusted tarballs are validated fail-closed *before* extraction: link
entries, path traversal, absolute and drive-qualified paths,
control-character and empty paths, decompression bombs (entry-count,
size, and expansion-ratio caps), unparseable size fields, and archives
without exactly one top-level directory are refused rather than
partially extracted. After extraction the directory is re-checked for
symlinks as defense in depth.

## Operating on sensitive data

[`audit_tarball()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_tarball.md)
writes the extracted package contents to `temp_dir` in cleartext. If the
package under audit may contain sensitive material, or you operate under
data-at-rest controls:

- set `temp_dir` to an encrypted volume or a tmpfs (RAM-backed) mount;
- note that cleanup uses
  [`unlink()`](https://rdrr.io/r/base/unlink.html), which is not a
  secure wipe, and that a killed process (e.g. SIGKILL) can leave the
  extraction directory behind.

Directory scans
([`audit_package()`](https://tylerjssmith.github.io/pkgaudit/reference/audit_package.md))
and rule loading
([`load_rules()`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md))
do not write to disk.

## Known limitations

- Findings are observations for human review, not a pass/fail verdict;
  rule coverage is not exhaustive.
- The rules database is integrity-checked against its SHA-256 sidecar,
  but the check is time-of-check to time-of-use — see “Security
  considerations” in
  [`?load_rules`](https://tylerjssmith.github.io/pkgaudit/reference/load_rules.md).
  Load rules only from a path trusted writers control.
- A directory hash
  ([`hash_manifest()`](https://tylerjssmith.github.io/pkgaudit/reference/hash_manifest.md))
  is a weaker provenance claim than a tarball hash: its scope depends on
  the exclusion patterns, and symlinks and empty directories are not
  represented. Prefer auditing the tarball when provenance matters.
