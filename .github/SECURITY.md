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

The package under audit is untrusted input. pkgaudit's job is to read it
without being subverted by it, and to say plainly what it did and did not read.

### The package under audit is never executed

pkgaudit does not install, build, load, or source the package it analyses. R
code is parsed, never evaluated; other files are read as text. A malicious
package is therefore malformed input to a reader, not code running in the
session doing the scan.

### pkgaudit does not reach the network

Nothing is fetched, resolved, or reported anywhere. A scan of a package on disk
is complete offline, and no information about the package under audit leaves
the machine.

### Only two functions write to disk

`audit_tarball()` extracts the tarball to a temporary directory (`temp_dir`,
default `tempdir()`) and removes it when finished. `export_unscanned()` writes
the code pkgaudit cannot read into a directory the caller names; it has no
default directory, so naming one is how the caller consents. Directory scans
(`audit_package()`), rule loading (`load_rules()`) and SARIF output
(`emit_sarif()`, which returns a string) do not write at all.

### Tarballs are validated before extraction, not during

Validation is fail-closed: an archive that fails any check is refused whole
rather than partially extracted. Refused are non-gzip compression (bzip2, xz,
zstd, compress — judged by magic bytes, not filename), link entries, GNU
long-name and PAX typeflags, path traversal, absolute and drive-qualified
paths, paths containing backslashes or control characters, empty paths,
decompression bombs (entry-count, size, and expansion-ratio caps), unparseable
size fields, and archives without exactly one top-level directory. After
extraction the directory is re-checked for symlinks as defense in depth.

### Exported files cannot escape the directory the caller names

Both the content and the file names written by `export_unscanned()` come from
the package under audit, so every target path is resolved and required to lie
under the named directory, and a path component that is `.`, `..`, or that
contains a separator or a control character is refused. Symlinks are never
followed, and content is read and rewritten rather than copied, so a link
pointing out of the package cannot pull a file in. Nothing is written
executable, and nothing is deleted or replaced unless `overwrite = TRUE`. A
refused file is recorded in the returned manifest rather than dropped.

### The rules database is trusted input, and the trust is yours to place

The database is integrity-checked against its SHA-256 sidecar, but the check is
time-of-check to time-of-use — see "Security considerations" in `?load_rules`.
Load rules only from a path whose writers you trust.

### Extraction writes package contents in cleartext

`audit_tarball()` writes the extracted package to `temp_dir`, and
`export_unscanned()` writes package contents to the directory it is given. If
the package under audit may contain sensitive material, or you operate under
data-at-rest controls, set `temp_dir` to an encrypted volume or a tmpfs
(RAM-backed) mount. Cleanup uses `unlink()`, which is not a secure wipe, and a
killed process (e.g. SIGKILL) can leave the extraction directory behind.

### A finding is an observation, not a verdict

Findings are for human review. There is no severity model and no pass/fail
result: every result in SARIF output carries the same `level`, and rule
coverage is not exhaustive. A package with no findings has not been cleared.

### The reading is static: values are not resolved and calls are not traced

A path assembled at runtime, a name built by `paste0()`, or a chunk option
computed at render time is not followed. pkgaudit also does not build call
graphs, so whether a package actually calls a particular function is not
something it determines — which is why the phases of code inside a function
definition are reported as a stated reading rather than a finding.

### Coverage is bounded, and the bound is reported

pkgaudit reads R and shell. It does not read compiled code or other languages;
`export_unscanned()` hands those to a tool that does. Files are identified by
name, not by contents, so an extensionless script — `tools/build` opening
`#!/bin/sh` — earns no coverage row. The `coverage` frame reports what each
file was read as (parsed, matched as text, exportable to another tool,
unexamined, or attempted and failed) so that a clean result can be checked
rather than trusted.

### A directory hash is a weaker provenance claim than a tarball hash

The scope of `hash_manifest()` depends on the exclusion patterns, and symlinks
and empty directories are not represented. Prefer auditing the tarball when
provenance matters.
