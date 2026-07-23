# Security Policy

## Reporting a vulnerability

Please report security issues privately, not in public issues.

Use GitHub's private vulnerability reporting (Security → Report a
vulnerability).

I aim to acknowledge reports within one week.

## Scope

This policy covers vulnerabilities in pkgaudit itself — for example, a
crafted package or tarball that causes pkgaudit to write outside its
extraction directory or execute code while scanning.

pkgaudit does not execute the code it analyses. If you believe you have
found a vulnerability or malicious code in some *other* R package, that
is not a pkgaudit issue: contact that package's maintainer, and CRAN
(cran@r-project.org) if it is distributed there.
