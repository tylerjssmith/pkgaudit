# Security Policy

## Reporting a vulnerability

Please report security issues privately, not in public issues.

Use GitHub's private vulnerability reporting (Security → Report a
vulnerability).

I aim to acknowledge reports within one week.

## Scope

This policy covers vulnerabilities in pkgaudit itself — for example, a crafted 
package or tarball that causes pkgaudit to write outside its extraction 
directory or execute code while scanning.

pkgaudit does not execute the code it analyses. If you believe you have found a 
vulnerability or malicious code in some *other* R package, that is not a 
pkgaudit issue: contact that package's maintainer, and CRAN 
([cran@r-project.org](mailto:cran@r-project.org)) if it is distributed there.

## Security model

pkgaudit analyses packages without executing them. The scan itself only reads.
Two functions write, and both write only where the caller sends them:

- `audit_tarball()` extracts the tarball to a temporary directory (`temp_dir`,
  default `tempdir()`) and removes it when finished.
- `export_unscanned()` writes the code pkgaudit cannot read -- C, C++, Fortran,
  Rust, Python, JavaScript, and vignette chunks in those languages -- into a
  directory the caller names, for a scanner that reads them. It has no default
  directory: naming one is how the caller consents.

Both the content and the file names written by `export_unscanned()` come from
the package under audit, so every target path is resolved and required to lie
under the named directory; a path component that is `.`, `..`, or that contains
a separator or a control character is refused; symlinks are never followed, and
content is read and rewritten rather than copied, so a link pointing out of the
package cannot pull a file in; nothing is written executable; and nothing is
deleted or replaced unless `overwrite = TRUE`. A refused file is recorded in the
returned manifest rather than dropped.

Untrusted tarballs are validated fail-closed *before* extraction: link entries,
path traversal, absolute and drive-qualified paths, control-character and empty 
paths, decompression bombs (entry-count, size, and expansion-ratio caps), 
unparseable size fields, and archives without exactly one top-level directory 
are refused rather than partially extracted. After extraction the directory is 
re-checked for symlinks as defense in depth.

## Operating on sensitive data

`audit_tarball()` writes the extracted package contents to `temp_dir` in
cleartext, and `export_unscanned()` writes package contents to the directory it
is given. If the package under audit may contain sensitive material, or you
operate under data-at-rest controls:

- set `temp_dir` to an encrypted volume or a tmpfs (RAM-backed) mount;
- note that cleanup uses `unlink()`, which is not a secure wipe, and that
  a killed process (e.g. SIGKILL) can leave the extraction directory
  behind.

Directory scans (`audit_package()`), rule loading (`load_rules()`) and SARIF
output (`emit_sarif()`, which returns a string) do not write to disk.

## Known limitations

- Findings are observations for human review, not a pass/fail verdict; rule
  coverage is not exhaustive.
- Coverage is not complete and is not meant to be. The `coverage` frame reports
  what each file was read as -- parsed, matched as text, exportable to another
  tool, unexamined, or attempted and failed -- so that a clean result can be
  checked rather than trusted. It accounts for a file when a rule claimed it or
  when its name says what kind of file it is; a file whose name says nothing is
  not represented.
- The rules database is integrity-checked against its SHA-256 sidecar, but the
  check is time-of-check to time-of-use — see "Security considerations" in 
  `?load_rules`. Load rules only from a path trusted writers control.
- A directory hash (`hash_manifest()`) is a weaker provenance claim than a 
  tarball hash: its scope depends on the exclusion patterns, and symlinks and
  empty directories are not represented. Prefer auditing the tarball when 
  provenance matters.
