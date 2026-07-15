# Threat Model

pkgaudit is designed around the following threat model.

## Assets

The primary assets at risk are the data processed and analyzed by R users and the underlying systems on which R is run.

R's presence in clinical trial analysis, government statistics, financial risk modeling, and academic research means that data processed in R sessions is often sensitive, regulated, or proprietary. Data exfiltration represents a direct harm to individuals and organizations.

The systems on which R is deployed are also valuable targets independent of the data they process. High-performance computing (HPC) clusters, cloud instances, and institutional servers used for statistical analysis provide substantial compute resources that attackers can exploit for cryptomining or as a launchpad for lateral movement.

A user's local R session may itself contain little sensitive data, but credentials stored in that environment — SSH keys, API tokens, `.Renviron` files — may grant access to RStudio Server, HPC clusters, or cloud storage buckets where sensitive data reside.

## Threats

The assets described above are relevant to a broad range of threat actors, reflecting R's penetration across industries handling sensitive data.

Nation-state actors and commercial competitors may target the intellectual property produced by R users. Cybercriminals may seek to steal or ransom sensitive data, or to exploit the compute infrastructure on which R runs. Hacktivists may target organizations such as pharmaceutical companies or financial institutions on ideological grounds.

The supply chain attack vector is particularly well-suited to this threat landscape. A malicious or compromised R package reaches every user who installs it, without requiring the attacker to target any individual or organization directly. This makes R package supply chain attacks attractive to threat actors across all of the above categories.

## Attack Surface

The immediate attack surface is the set of lifecycle hooks — `.onLoad()` and `.onAttach()` — executed automatically when a package is loaded via `library()`. Any code in these hooks runs with the privileges of the R process before the user has any opportunity to review it.

The effective attack surface is considerably larger. Loading a single package may trigger `.onLoad()` and `.onAttach()` hooks across its entire dependency graph. A user who calls `library(tidyverse)`, for example, initiates the loading of dozens of packages, each of which may execute hook code. 

A malicious or compromised package anywhere in that dependency graph — including packages the user has never heard of and would never install directly — executes its hook code with the same privileges as the top-level package. This significantly multiplies the number of packages an attacker can target while remaining invisible to the user.

## Attack Patterns

pkgaudit v0.1.0 detects two categories of attack patterns, each mapped to the MITRE ATT&CK framework:

1. **Arbitrary code execution** via shell commands (`system()`, `system2()`) inside lifecycle hooks enables an attacker to run any command available on the user's system. This maps to ATT&CK T1059.004 (Command and Scripting Interpreter: Unix Shell) and T1195.002 (Supply Chain Compromise: Compromise Software Supply Chain).

2. **Network exfiltration** via outbound HTTP requests (`httr::POST()`) inside lifecycle hooks enables an attacker to transmit data from the user's environment to an attacker-controlled server. This maps to ATT&CK T1041 (Exfiltration Over C2 Channel) and T1195.002.

Future versions will expand coverage to credential harvesting via environment variable access, filesystem access targeting known credential locations, obfuscation via `eval(parse())`, and persistence via modification of `.Rprofile` or `.Renviron`.

## Mitigation and Limitations

pkgaudit provides static analysis of R source code and is one layer of defense, not a complete solution. A determined attacker can obfuscate dangerous patterns beyond what source-level analysis can reliably detect. 

pkgaudit v0.1.0 scans `R/`. Future versions will expand coverage to `vignettes/`, `tests/`, and dependency graph scanning.

Beyond pkgaudit, mitigations operate at several layers:

1. **Reducing the attack surface.** Least-privilege R environments — where the R process has access only to the data and credentials it needs for a specific task — limit what an attacker can exfiltrate or access. Separating local exploratory work from production environments with sensitive data reduces the value of credentials in any single environment.

2. **Protecting credentials.** Multi-factor authentication on systems accessible via credentials stored in R environments (RStudio Server, cloud accounts, HPC clusters) limits the damage from credential theft. Secrets managers and environment-specific credentials reduce the blast radius of any single compromise compared to long-lived credentials stored in `.Renviron`.

3. **Protecting data.** Encryption of sensitive data at rest limits exfiltration impact, though it provides no protection against a running R process with legitimate read access to that data — the same process executing a malicious hook has access to any data the user can read. Network egress controls that restrict outbound connections from R environments are more directly effective against the exfiltration patterns pkgaudit detects.

4. **Ecosystem-level controls.** CRAN's submission review process checks for policy compliance but does not perform behavioral security analysis. Institutional controls such as private package repositories, allowlists of approved packages, and mandatory security review before package installation complement static analysis tools like pkgaudit.
