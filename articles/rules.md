# pkgaudit Rule Coverage

pkgaudit v0.4.0 separates *what* code does from *when* it executes.
**Patterns** and **matches** answer the first, and come first below;
**file contexts** and **code contexts** answer the second. Each rule is
defined in a YAML file under
[inst/rules/](https://github.com/tylerjssmith/pkgaudit/tree/main/inst/rules)
and compiled into the SQLite database at `inst/db/rules.db`. The Rule
columns below link to the defining YAML files.

This vignette is generated from that database, at rules v0.4.0. Every
rule in it must be described here, so a rule that ships without a
description fails the build rather than appearing unexplained.

## Patterns

Patterns are security-relevant function calls. Each pattern finding is
attributed to the code context it executes in, so a
[`system()`](https://rdrr.io/r/base/system.html) call inside `.onLoad`
is distinguished from one inside an ordinary function (“Other”) or at
top level (“R”). Qualified (`pkg::fn()`) and unqualified (`fn()`) call
forms are both detected. Pattern rules carry [MITRE
ATT&CK](https://attack.mitre.org/) technique labels.

A finding also records how the code is *reached*. `guarded` is `TRUE`
for code that ships but the lifecycle does not run – a `\dontrun{}` or
`\donttest{}` block, or a vignette chunk marked `eval=FALSE`; its phases
still come from its context, so they read as an upper bound. `indirect`
is `TRUE` where the call was made through the function’s name rather
than the function.

A pattern rule declares no phases of its own: a pattern inherits them
from the code context it sits in, listed in the two tables above.

A call made through a function’s name rather than the function –
`do.call("system", ...)`,
[`match.fun()`](https://rdrr.io/r/base/match.fun.html), `getFunction()`
– is reported under the rule that owns the name, with the `indirect`
column set. Each rule declares the names it claims, and a name is only
accepted if calling it bare would have matched that same rule, so an
indirect finding can never be attributed to a rule that would not have
reported the direct call. Three rules claim no names: `eval_parse`,
`options_repos` and `system_processx` each match on more than the callee
– a nested call, a named argument, a package qualifier – and none of
that survives the trip through
[`do.call()`](https://rdrr.io/r/base/do.call.html). A name assembled at
runtime is not resolved either, since pkgaudit evaluates nothing.

| Rule | Pattern | Description |
|----|----|----|
| [credentials](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_credentials.yaml) | a path or environment variable that only holds a secret: `~/.ssh/`, `~/.aws/`, `.netrc`, `id_rsa`, `~/.gnupg/`, and [`Sys.getenv()`](https://rdrr.io/r/base/Sys.getenv.html) of a name containing `TOKEN`, `SECRET`, `PASSWORD` or `API_KEY` | A path or environment variable that only exists to hold a secret. Nothing a package needs in order to install or load lives in these, and package code runs with the full privileges of whoever installed it. The literal has to look like a path or a short command rather than a sentence, since prose that merely mentions ~/.ssh is not a package reading it – but naming one is still not proof it is read, so read the line. |
| [curl](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_curl.yaml) | `curl()`, `curl_fetch_memory()`, `curl_fetch_disk()`, `curl_fetch_stream()`, `curl_fetch_multi()`, `curl_download()`, `curl_upload()`, `multi_download()`, `multi_run()`, `send_mail()` | A curl network call sends an outbound HTTP request or opens a connection to a remote host. A request may be used to exfiltrate credentials or other data, or to fetch a remote payload. |
| [decoding](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_decoding.yaml) | `base64decode()`, `base64_dec()`, `base64_decode()`, [`memDecompress()`](https://rdrr.io/r/base/memCompress.html), `rawToChar(as.raw())` | These functions decode or decompress data. Payloads may be encoded (e.g., as base64) to evade static detection and decoded at runtime. |
| [deserialization](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_deserialization.yaml) | [`readRDS()`](https://rdrr.io/r/base/readRDS.html), [`load()`](https://rdrr.io/r/base/load.html), [`unserialize()`](https://rdrr.io/r/base/serialize.html), [`dget()`](https://rdrr.io/r/base/dput.html) | readRDS(), load(), unserialize(), and dget() deserialize R objects or code, which can enable arbitrary code execution (CVE-2024-27322 for RDS). |
| [download_file](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_download_file.yaml) | [`download.file()`](https://rdrr.io/r/utils/download.file.html), [`url()`](https://rdrr.io/r/base/connections.html) | download.file() and url() retrieve or open a connection to a remote resource. This can stage a payload for execution via source() or system() in a two-stage attack. |
| [dynload](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_dynload.yaml) | [`dyn.load()`](https://rdrr.io/r/base/dynload.html), [`library.dynam()`](https://rdrr.io/r/base/library.dynam.html) | dyn.load() and library.dynam() load compiled code from a shared object, which executes outside the visible R source. |
| [eval_parse](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_eval_parse.yaml) | [`eval()`](https://rdrr.io/r/base/eval.html)/[`evalq()`](https://rdrr.io/r/base/eval.html) over [`parse()`](https://rdrr.io/r/base/parse.html), [`str2lang()`](https://rdrr.io/r/base/parse.html) or [`str2expression()`](https://rdrr.io/r/base/parse.html), when the text came from a fetch, a decode, a deserialization, a subprocess or a file read – every function the rules for those already cover, plus [`readLines()`](https://rdrr.io/r/base/readLines.html), [`scan()`](https://rdrr.io/r/base/scan.html), [`readBin()`](https://rdrr.io/r/base/readBin.html) and [`rawToChar()`](https://rdrr.io/r/base/rawConversion.html) | Text that came from somewhere pkgaudit cannot read, parsed and then evaluated. Any one of these calls is ordinary on its own; together in one expression they are a payload being assembled and run. The inner set is every function the rules for fetching, decoding, deserializing, running a subprocess and running Python already cover, plus the file reads no rule covers on its own. |
| [httr](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_httr.yaml) | `GET()`, `POST()`, `PUT()`, `PATCH()`, `DELETE()`, `HEAD()`, `VERB()` | An httr HTTP call sends an outbound request. A request may be used to exfiltrate credentials or other data, or to fetch a remote payload. |
| [httr2](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_httr2.yaml) | `req_perform()`, `req_perform_iterative()`, `req_perform_parallel()`, `req_perform_sequential()`, `req_perform_stream()`, `req_perform_connection()`, `req_perform_promise()` | An httr2 HTTP call sends an outbound request. A request may be used to exfiltrate credentials or other data. |
| [install](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_install.yaml) | [`install.packages()`](https://rdrr.io/r/utils/install.packages.html), `install_github()`, `install_gitlab()`, `install_bitbucket()`, `install_git()`, `install_url()`, `install_version()`, `install_local()`, `install_bioc()`, `install_dev()`, `install_cran()`, `pak()`, `pkg_install()`, `local_install()`, `lockfile_install()`, `BiocManager::install()`, `renv::install()`, `devtools::install()`, `py_install()`, `virtualenv_install()`, `conda_install()`, `virtualenv_create()`, `conda_create()` | These functions install packages, optionally from a specified or remote source. A non-default source can introduce attacker-controlled code. |
| [namespace](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_namespace.yaml) | [`getFromNamespace()`](https://rdrr.io/r/utils/getFromNamespace.html), [`getExportedValue()`](https://rdrr.io/r/base/ns-reflect.html), [`getAnywhere()`](https://rdrr.io/r/utils/getAnywhere.html), [`assignInNamespace()`](https://rdrr.io/r/utils/getFromNamespace.html), [`assignInMyNamespace()`](https://rdrr.io/r/utils/getFromNamespace.html), [`unlockBinding()`](https://rdrr.io/r/base/bindenv.html) | These functions reach past a package namespace. getFromNamespace(), getExportedValue() and getAnywhere() read objects a package does not export; assignInNamespace(), assignInMyNamespace() and unlockBinding() replace or unseal bindings in a namespace already loaded, so an ordinary call made later can run something else. The ::: operator is not matched here, since R CMD check already reports it. |
| [options_repos](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_options_repos.yaml) | `options(repos = )` | options(repos = …) replaces the CRAN mirror for the R session. Subsequent install.packages() calls will fetch packages from the configured repository. If set to an attacker-controlled server, this poisons the installation source. |
| [persistence](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_persistence.yaml) | a startup file or scheduler: `~/.bashrc`, `~/.zshrc`, `~/.profile`, `~/.Rprofile`, `~/.Renviron`, `crontab`, `LaunchAgents`, `/etc/systemd` | A shell startup file, an R startup file, or a scheduler. Code written into one of these runs again on every login or on a timer, outside the install that put it there, and removing the package does not undo it. .Rprofile and .Renviron are the same idea one level in: R reads them at every session. The literal has to look like a path or a short command rather than a sentence, since prose that merely mentions ~/.bashrc is not a package writing to it. |
| [python](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_python.yaml) | `py_run_string()`, `py_run_file()`, `py_eval()`, `source_python()`, `py_call()`, `import_builtins()` | These functions run Python from R through reticulate. pkgaudit does not read Python, so what they run is outside this scan entirely – and code passed as a string is not even a file the coverage frame can account for. import_builtins() is listed with them because it returns Python’s own eval, exec and **import**. |
| [rcurl](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_rcurl.yaml) | `getURL()`, `getURI()`, `getForm()`, `postForm()`, `curlPerform()` | An RCurl network call sends an outbound HTTP request. A request may be used to exfiltrate credentials or other data, or to fetch a remote payload. |
| [socket](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_socket.yaml) | [`socketConnection()`](https://rdrr.io/r/base/connections.html), [`make.socket()`](https://rdrr.io/r/utils/make.socket.html), [`serverSocket()`](https://rdrr.io/r/base/connections.html), [`socketAccept()`](https://rdrr.io/r/base/connections.html) | These functions open a raw network socket, which may be used to exfiltrate data or receive a remote payload outside the usual HTTP clients. |
| [source](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_source.yaml) | [`source()`](https://rdrr.io/r/base/source.html) | source() can fetch and execute local and remote R scripts. |
| [system](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_system.yaml) | [`system()`](https://rdrr.io/r/base/system.html), [`system2()`](https://rdrr.io/r/base/system2.html), `shell()`, [`pipe()`](https://rdrr.io/r/base/connections.html) | system(), system2(), shell() (on Windows), and pipe() execute arbitrary shell commands. |
| [system_callr](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_system_callr.yaml) | [`callr::r()`](https://callr.r-lib.org/reference/r.html), `r_bg()`, `r_safe()`, `r_copycat()`, `r_vanilla()`, [`callr::rcmd()`](https://callr.r-lib.org/reference/rcmd.html), `rcmd_bg()`, `rcmd_safe()`, `rcmd_copycat()`, `rscript()`, `r_session$new()`, `r_process$new()`, `rcmd_process$new()`, `rscript_process$new()` | These callr functions start a separate R session or run an R CMD command, which may be used to execute arbitrary R code or shell commands outside the visible R source. |
| [system_processx](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_system_processx.yaml) | [`processx::run()`](http://processx.r-lib.org/reference/run.md), [`processx::pipeline()`](http://processx.r-lib.org/reference/pipeline.md), `process$new()` | These processx functions run an external process, which may be used to execute arbitrary shell commands outside the visible R source. |
| [system_sys](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/patterns/pattern_system_sys.yaml) | `exec_wait()`, `exec_background()`, `exec_internal()`, `eval_safe()`, `eval_fork()`, `r_background()`, `r_internal()`, `r_wait()` | These sys functions run an external process or fork the R session, which may be used to execute arbitrary shell commands or a second R session outside the visible R source. |

## Matches

Matches are regular-expression matches in the shell scripts and
Make-like files among the file contexts above – those whose Type is
`shell` or `make`. A file context typed `R` is parsed and scanned for
patterns instead, and no other file in the package is scanned for
matches at all. Match rules carry [MITRE
ATT&CK](https://attack.mitre.org/) technique labels.

Like a pattern rule, a match rule declares no phases of its own: a match
inherits them from the file context it was found in, listed in the File
Contexts table above. Where a file matches more than one file-context
rule, it takes the phases of every rule that matched it.

Matching text is less precise than matching a parse tree. A match has no
syntax behind it, so a match inside a comment, a quoted string, or a
branch that never runs is reported the same as one in a live command. A
match is a candidate for review rather than confirmed behaviour, and
warrants reading the file itself more than a pattern finding does.

| Rule | Description |
|----|----|
| [chmod](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/matches/match_chmod.yaml) | Making a file executable, or setting its setuid or setgid bit, during a build turns something the package shipped as data into something that can be run – in the setuid case, with the privileges of whoever owns it rather than whoever runs it. |
| [credentials](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/matches/match_credentials.yaml) | A build script naming a credential store is reading, or preparing to read, something that only exists to authenticate its owner. Nothing a package needs in order to build lives in these files, and a build runs with the full privileges of whoever installs the package. |
| [curl](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/matches/match_curl.yaml) | curl fetches a remote resource or sends data to a remote host. In a shell script or Make-like file it runs when the package is built, checked, or installed, and may be used to fetch a remote payload or to exfiltrate credentials or other data. |
| [decoding](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/matches/match_decoding.yaml) | A decoding command turns bytes that are not readable as text back into something that is. In a build script it is most often seen immediately before the result is run or written to disk, which is how a payload is carried past a reader who only skims the source. |
| [install](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/matches/match_install.yaml) | Installing software during a package build reaches outside the package for code and runs it. What arrives is chosen by a remote index rather than by the package under audit, and is not covered by this scan or by the R dependency graph. |
| [interpreter](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/matches/match_interpreter.yaml) | A build script that calls another language’s interpreter runs code pkgaudit does not read. The script it runs may live in the package, be written by an earlier step, or be fetched; either way its contents are not part of this scan. |
| [persistence](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/matches/match_persistence.yaml) | A build script touching a startup file or a scheduler is arranging to run again later, outside the install that put it there. Removing the package does not undo it. .Rprofile and .Renviron are the same idea one level in: R reads them at the start of every session. |
| [rscript](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/matches/match_rscript.yaml) | Rscript runs R code from a shell script or Make-like file, either from a file it is given or inline with -e. That code executes when the package is built, checked, or installed, and pkgaudit does not parse it: code inside an -e string, or in a script under tools/, is reached only through this invocation. The invocation is reported so a reviewer can follow it. |
| [socket](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/matches/match_socket.yaml) | Opening a socket from a build script moves data to or from a remote host without an HTTP client, which is both a way to fetch a payload and a way to send one out. A shell redirection to /dev/tcp does it with no external program at all. |
| [transfer](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/matches/match_transfer.yaml) | A file-transfer command moves a file between the build machine and a remote host. Unlike an HTTP fetch it often carries credentials of its own, and it runs in whichever direction the script asks for, so it is a way to send data out as well as to bring code in. |
| [wget](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/matches/match_wget.yaml) | wget fetches a remote resource or sends data to a remote host. In a shell script or Make-like file it runs when the package is built, checked, or installed, and may be used to fetch a remote payload or to exfiltrate credentials or other data. |

The regular expressions themselves are matched with `perl = TRUE` and
are case-sensitive:

    chmod        (?<=^|[^[:alnum:]_-])chmod(?=[^[:alnum:]_./-]|$)[^|;&\n]{0,40}?([+][xs]|[24][0-7]{3}|777)
    credentials  (\.ssh/|\.aws/|\.netrc|\.pgpass|\.docker/config\.json|\.config/gcloud|\.kube/config|id_rsa|id_dsa|id_ecdsa|id_ed25519|\.gnupg/|credentials\.json)|[A-Z][A-Z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|PRIVATE_KEY)
    curl         (?<=^|[^[:alnum:]_-])curl(?=(\.exe)?([^[:alnum:]_./-]|$))
    decoding     (?<=^|[^[:alnum:]_-])(base64[^|;&\n]{0,40}(--decode|-[dD])|openssl[[:space:]]+enc[^|;&\n]{0,60}-d|xxd[^|;&\n]{0,20}-r|uudecode)
    install      (?<=^|[^[:alnum:]_-])(pip[23]?|npm|yarn|apt-get|apt|yum|dnf|apk|brew|conda|gem|cargo|go)[[:space:]]+(install|add|get)(?=[^[:alnum:]_./-]|$)
    interpreter  (?<=^|[^[:alnum:]_-])(python[23]?|perl|ruby|node|osascript|powershell|pwsh)(?=[^[:alnum:]_./-]|$)
    persistence  (\.bashrc|\.bash_profile|\.bash_login|\.bash_logout|\.profile|\.zshrc|\.zprofile|\.zshenv|\.cshrc|\.Rprofile|\.Renviron|crontab|LaunchAgents|LaunchDaemons|/etc/cron|/etc/systemd|\.config/systemd|/etc/rc\.local)
    rscript      (?<=^|[^[:alnum:]_-])Rscript(?=(\.exe)?([^[:alnum:]_./-]|$))
    socket       (?<=^|[^[:alnum:]_-])(nc|ncat|netcat|socat|telnet)(?=[[:space:]])|/dev/(tcp|udp)/
    transfer     (?<=^|[^[:alnum:]_-])(scp|sftp|ftp|rsync|svn)(?=[^[:alnum:]_./-]|$)|(?<=^|[^[:alnum:]_-])git[[:space:]]+clone(?=[^[:alnum:]_./-]|$)
    wget         (?<=^|[^[:alnum:]_-])wget(?=(\.exe)?([^[:alnum:]_./-]|$))

## Lifecycle Phases

Every file and code context declares the phases of the package lifecycle
in which its code runs. Each finding carries one logical column per
phase, so findings can be filtered by when they execute, e.g.
`subset(result$patterns, at_install_src)`.

| Phase            | Code runs when                                         |
|------------------|--------------------------------------------------------|
| `at_autoconf`    | Autoconf is run to generate `configure` from its input |
| `at_build`       | `R CMD build`                                          |
| `at_check`       | `R CMD check`                                          |
| `at_install_src` | `R CMD INSTALL` from source                            |
| `at_install_bin` | a prebuilt binary package is installed                 |
| `at_load`        | the namespace is loaded                                |
| `at_attach`      | the package is attached to the search path             |
| `at_unload`      | the namespace is unloaded                              |
| `at_detach`      | the package is detached from the search path           |

Phase assignments were established by running `R CMD build`,
`R CMD check`, and `R CMD INSTALL` against instrumented packages rather
than read from documentation. A rule can belong to several phases, and
the Phases column below reads `none` for code that runs at no phase at
all.

## File Contexts

File contexts are files that R executes at build-, check-, or
install-time.

The Type column determines how a matched file is read. Files typed `R`
are parsed and scanned for patterns; `Rd` files have their `\examples{}`
and `\Sexpr{}` code extracted and scanned for patterns; `shell` and
`make` files are matched against the rules listed under
[Matches](#matches).

The Report column separates being scanned from being reported. Every
rule tells the scan which files to read; only a reporting rule
contributes a row to the `file_contexts` findings frame.

`report` is `TRUE` for a file that meets two conditions: it executes
automatically during at least one lifecycle phase, and its contents are
matched as text rather than parsed. Together those mean pkgaudit cannot
tell a reviewer what the file does, only that it runs – so the file
itself is the finding, and someone has to read it. In practice that is
the shell scripts and Make-like files: `configure`, `cleanup`,
`src/Makevars` and their variants.

Everything else is scanned just as thoroughly. A pattern in a vignette
or a test file is reported with its context and phases whether or not
the file itself is. What `report` withholds is the row asserting the
file exists – which, for a file whose contents are parsed, the findings
already tell you.

`src/install.libs.R` is the one exception: it is R, and parsed, but its
presence replaces R’s default handling of compiled artifacts, a
structural change that follows from the file existing rather than from
anything written in it.

| Rule | File Context | Type | Report | Phases | Description |
|----|----|----|----|----|----|
| [R_scripts](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_R_scripts.yaml) | `R/*.[RrSsq]` | `R` | no | `at_build`, `at_check`, `at_install_src` | R source files in R are evaluated when the package is installed from source, when the lazy-load database is built. They are scanned for code contexts and patterns; the files themselves are not a finding, which is why this rule does not report. |
| [R_scripts_unix](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_R_scripts_unix.yaml) | `R/unix/*.[RrSsq]` | `R` | no | `at_build`, `at_check`, `at_install_src` | R source files in R/unix are evaluated when the package is installed from source, when the lazy-load database is built. They are scanned for code contexts and patterns; the files themselves are not a finding, which is why this rule does not report. |
| [R_scripts_windows](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_R_scripts_windows.yaml) | `R/windows/*.[RrSsq]` | `R` | no | `at_build`, `at_check`, `at_install_src` | R source files in R/windows are evaluated when the package is installed from source, when the lazy-load database is built. They are scanned for code contexts and patterns; the files themselves are not a finding, which is why this rule does not report. |
| [cleanup](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_cleanup.yaml) | `cleanup` | `shell` | yes | `at_build` | cleanup is a shell script run on Unix-like systems at the end of R CMD build, and during installation from source only under R CMD INSTALL –clean or –preclean. It can execute arbitrary shell commands. |
| [cleanup_ucrt](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_cleanup_ucrt.yaml) | `cleanup.ucrt` | `shell` | yes | `at_build` | cleanup.ucrt is a shell script run on the Windows UCRT toolchain at the end of R CMD build, and during installation from source only under R CMD INSTALL –clean or –preclean; it takes precedence over cleanup.win when present. It can execute arbitrary shell commands. |
| [cleanup_win](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_cleanup_win.yaml) | `cleanup.win` | `shell` | yes | `at_build` | cleanup.win is a shell script run on Windows at the end of R CMD build, and during installation from source only under R CMD INSTALL –clean or –preclean. It can execute arbitrary shell commands. |
| [configure](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_configure.yaml) | `configure` | `shell` | yes | `at_build`, `at_check`, `at_install_src` | configure is a shell script used for system-dependent configuration when packages are installed from source, including the installs performed by R CMD check and by R CMD build when a package has vignettes. It can execute arbitrary shell commands. |
| [configure_ac](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_configure_ac.yaml) | `configure.ac` | `shell` | yes | `at_autoconf` | configure.ac is an Autoconf input file that does not itself execute; it is processed by Autoconf to generate the configure script, which executes shell commands when a package is installed from source. |
| [configure_in](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_configure_in.yaml) | `configure.in` | `shell` | yes | `at_autoconf` | configure.in is a legacy-named Autoconf input file that does not itself execute; it is processed by Autoconf to generate the configure script, which executes shell commands when a package is installed from source. |
| [configure_ucrt](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_configure_ucrt.yaml) | `configure.ucrt` | `shell` | yes | `at_build`, `at_check`, `at_install_src` | configure.ucrt is a shell script for system-dependent configuration on the Windows UCRT toolchain, executed when a package is installed from source, including the installs performed by R CMD check and by R CMD build when a package has vignettes; it takes precedence over configure.win when present. |
| [configure_win](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_configure_win.yaml) | `configure.win` | `shell` | yes | `at_build`, `at_check`, `at_install_src` | configure.win is a shell script for system-dependent configuration on Windows, executed when a package is installed from source, including the installs performed by R CMD check and by R CMD build when a package has vignettes. |
| [data_scripts](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_data_scripts.yaml) | `data/*.[RrSsq]` | `R` | no | `at_build`, `at_install_src` | A .R file under data/ is R code that runs when the package’s data is prepared. R CMD build evaluates it to produce the .rda it ships, and installation from a source directory evaluates it too, so it executes arbitrary R before the package is ever loaded. It does not survive into a source tarball: build replaces it with its own output. |
| [data_serialized](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_data_serialized.yaml) | `data/*.(rda\|RData\|Rdata\|rdata\|rds\|RDS\|Rds)` | `other` | no | `at_check`, `at_install_src`, `at_load` | A serialized R object under data/ is restored when the package’s data is loaded. Deserializing an .rda or .rds can execute arbitrary code, and pkgaudit cannot inspect one, so it is recorded rather than passed over as inert data. |
| [demo_scripts](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_demo_scripts.yaml) | `demo/*.[RrSsq]` | `R` | no | none | A demo runs when a user calls demo(). No build, check or install command reaches it, but it ships in the installed package and runs with the user’s privileges when invoked. |
| [description](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_description.yaml) | `DESCRIPTION` | `other` | no | `at_build`, `at_check` | DESCRIPTION is not inert. Its <Authors@R> field is R code, which R parses and evaluates when the package is built and checked. pkgaudit does not read the file, so the row records that it executes and was not examined. |
| [exec_other](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_exec_other.yaml) | `exec/*.(py\|pl\|rb\|bat\|ps1\|tcl\|lua)` | `other` | no | none | A script under exec/ in a language pkgaudit does not read. R installs exec/ verbatim and marks its contents executable, so this ships as a runnable program, but nothing runs it during a lifecycle phase. |
| [exec_scripts_R](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_exec_scripts_R.yaml) | `exec/*.[RrSsq]` | `R` | no | none | R scripts under exec/ ship in the installed package and are marked executable. No lifecycle command runs them, but they execute with the user’s privileges when invoked. Over half the files CRAN packages put in exec/ are R, so they are parsed rather than matched as text. |
| [exec_scripts_shell](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_exec_scripts_shell.yaml) | `exec/*.(sh\|bash\|ksh\|zsh\|csh)` | `shell` | no | none | Shell scripts under exec/ ship in the installed package and are marked executable. No lifecycle command runs them, but they execute arbitrary shell with the user’s privileges when invoked. Only sh-family extensions are claimed; exec/ also holds Perl, Python, batch and other files this rule does not match, and extensionless scripts whose language is known only from a shebang. |
| [inst_citation](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_inst_citation.yaml) | `inst/CITATION` | `R` | no | `at_check` | inst/CITATION is R code that utils::readCitationFile() evaluates. R CMD check reads it, and so does any user who calls citation() on the installed package. A plain .R file under inst/ is never sourced, so this is specific to the CITATION filename. |
| [inst_tests](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_inst_tests.yaml) | `inst/tests/*.[RrSsq]` | `R` | no | `at_check` | Older versions of testthat kept tests under inst/tests/, which R CMD check runs through a runner in tests/. Unlike tests/, inst/ is copied into the installed package, so this code also ships to the user. |
| [inst_tinytest](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_inst_tinytest.yaml) | `inst/tinytest/*.[RrSsq]` | `R` | no | `at_check` | tinytest keeps its tests under inst/tinytest/, which R CMD check runs through a runner in tests/. Unlike tests/, inst/ is copied into the installed package, so this code also ships to the user and can be run again after installation. |
| [inst_unittests](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_inst_unittests.yaml) | `inst/unitTests/*.[RrSsq]` | `R` | no | `at_check` | RUnit keeps its tests under inst/unitTests/, which R CMD check runs through a runner in tests/. Unlike tests/, inst/ is copied into the installed package, so this code also ships to the user. |
| [inst_web](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_inst_web.yaml) | `inst/*.(js\|mjs\|ts)` | `other` | no | none | JavaScript shipped under inst/ runs in a browser when a user renders the widget or app it belongs to, not at any package lifecycle phase. It is still code the package ships and pkgaudit does not read, so it is recorded and can be exported. |
| [man_pages](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_man_pages.yaml) | `man/*.[Rr]d` | `Rd` | no | `at_build`, `at_check`, `at_install_src` | Help files in man carry R code in two places: , which R CMD check runs, and , which is evaluated when the help page is rendered during R CMD build and installation from source. They are scanned for patterns; the files themselves are not a finding, which is why this rule does not report. |
| [man_pages_unix](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_man_pages_unix.yaml) | `man/unix/*.[Rr]d` | `Rd` | no | `at_build`, `at_check`, `at_install_src` | Help files in man/unix carry R code in two places: , which R CMD check runs, and , which is evaluated when the help page is rendered during R CMD build and installation from source. They are scanned for patterns; the files themselves are not a finding, which is why this rule does not report. |
| [man_pages_windows](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_man_pages_windows.yaml) | `man/windows/*.[Rr]d` | `Rd` | no | `at_build`, `at_check`, `at_install_src` | Help files in man/windows carry R code in two places: , which R CMD check runs, and , which is evaluated when the help page is rendered during R CMD build and installation from source. They are scanned for patterns; the files themselves are not a finding, which is why this rule does not report. |
| [r_sysdata](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_r_sysdata.yaml) | `R/sysdata.rda` | `other` | no | `at_check`, `at_install_src`, `at_load` | R/sysdata.rda holds a package’s internal objects and is restored into the namespace when the package loads. Deserializing it can execute arbitrary code, and pkgaudit cannot inspect it. |
| [rprofile](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_rprofile.yaml) | `.Rprofile` | `R` | no | `at_build`, `at_install_src` | R evaluates a .Rprofile found in the working directory when it starts, so a .Rprofile at the package root runs whenever a lifecycle command starts an R process inside the package. It runs before any package is loaded, earlier than any other R in the package. |
| [src_compiled](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_src_compiled.yaml) | `src/*.(c\|cc\|cpp\|cxx\|C\|h\|hpp\|hxx\|ipp\|f\|f90\|f95\|f03\|f77\|for\|m\|mm\|rs\|java)` | `other` | no | `at_check`, `at_install_src`, `at_load` | Compiled source is built into a package’s shared object by R CMD INSTALL and loaded with the namespace. pkgaudit does not read it; the row exists so the file is accounted for, and export_unscanned() can hand it to a tool that does. The extensions are listed rather than left to the directory, so that compiled source shipped anywhere else – a header library under inst/include/, say – is accounted for too. |
| [src_install_libs_R](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_src_install_libs_R.yaml) | `src/install.libs.R` | `R` | yes | `at_build`, `at_check`, `at_install_src` | src/install.libs.R is an R script used in some packages to install executable programs and other binaries during installation from source, including the installs performed by R CMD check and by R CMD build when a package has vignettes. It can run arbitrary R code. |
| [src_makefile](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_src_makefile.yaml) | `src/Makefile` | `make` | yes | `at_build`, `at_check`, `at_install_src` | src/Makefile is a makefile used to compile code in src/ when a package is installed from source, replacing R’s default make rules; the installs performed by R CMD check and by R CMD build also use it, and R CMD build runs its clean target. It is read by make and its recipes execute arbitrary shell commands. |
| [src_makefile_ucrt](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_src_makefile_ucrt.yaml) | `src/Makefile.ucrt` | `make` | yes | `at_build`, `at_check`, `at_install_src` | src/Makefile.ucrt is a makefile used to compile code in src/ on the Windows UCRT toolchain when a package is installed from source, replacing R’s default make rules; the installs performed by R CMD check and by R CMD build also use it, and R CMD build runs its clean target. It is read by make and its recipes execute arbitrary shell commands. |
| [src_makefile_win](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_src_makefile_win.yaml) | `src/Makefile.win` | `make` | yes | `at_build`, `at_check`, `at_install_src` | src/Makefile.win is a makefile used to compile code in src/ on Windows when a package is installed from source, replacing R’s default make rules; the installs performed by R CMD check and by R CMD build also use it, and R CMD build runs its clean target. It is read by make and its recipes execute arbitrary shell commands. |
| [src_makevars](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_src_makevars.yaml) | `src/Makevars` | `make` | yes | `at_build`, `at_check`, `at_install_src` | src/Makevars sets make variables used to compile code in src/ when a package is installed from source, including the installs performed by R CMD check and by R CMD build; R CMD build also reads it when cleaning src/. It is read by make and can execute shell via make constructs such as \$(shell …). |
| [src_makevars_in](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_src_makevars_in.yaml) | `src/Makevars.in` | `make` | yes | `at_build`, `at_check`, `at_install_src` | src/Makevars.in is a template that does not itself execute; it is processed by the configure script to generate src/Makevars, whose contents are then read by make to compile code in src/ when a package is installed from source, including the installs performed by R CMD check and by R CMD build. |
| [src_makevars_ucrt](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_src_makevars_ucrt.yaml) | `src/Makevars.ucrt` | `make` | yes | `at_build`, `at_check`, `at_install_src` | src/Makevars.ucrt sets make variables used to compile code in src/ on the Windows UCRT toolchain when a package is installed from source, including the installs performed by R CMD check and by R CMD build; it takes precedence over Makevars.win, and R CMD build also reads it when cleaning src/. It is read by make and can execute shell via make constructs such as \$(shell …). |
| [src_makevars_win](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_src_makevars_win.yaml) | `src/Makevars.win` | `make` | yes | `at_build`, `at_check`, `at_install_src` | src/Makevars.win sets make variables used to compile code in src/ on Windows when a package is installed from source, including the installs performed by R CMD check and by R CMD build; R CMD build also reads it when cleaning src/. It is read by make and can execute shell via make constructs such as \$(shell …). |
| [src_other](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_src_other.yaml) | `src/*.` | `other` | no | `at_check`, `at_install_src`, `at_load` | A file under src/ in no language pkgaudit recognises. Everything in src/ is handed to the compiler, so an extension nobody listed is still part of what gets built; the row exists so it is accounted for rather than passed over. |
| [tests_scripts](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_tests_scripts.yaml) | `tests/*.[RrSsq]` | `R` | no | `at_check` | R CMD check runs every .R file directly under tests/. This is the entry point of whatever testing framework the package uses, and it executes arbitrary R during checking. |
| [tests_testthat](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_tests_testthat.yaml) | `tests/testthat/*.[RrSsq]` | `R` | no | `at_check` | testthat sources the files directly under tests/testthat/ when R CMD check runs the package’s tests. Subdirectories are not sourced – tests/testthat/ fixtures/ holds inert data – so only the top level is scanned. |
| [tools_scripts](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_tools_scripts.yaml) | `tools/*.[RrSsq]` | `R` | no | none | tools/ holds helper scripts that nothing runs on its own. It is reached only if configure or a Makevars invokes it, in which case that invocation is reported where it appears and carries that file’s phases. The code is scanned here so a reviewer can read what would run. |
| [vignettes_qmd](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_vignettes_qmd.yaml) | `vignettes/*.qmd` | `qmd` | no | `at_build`, `at_check` | A Quarto vignette carries executable chunks, in the same fenced syntax as R Markdown. Vignette code runs when the vignette is rendered: during R CMD build, and again under R CMD check, which rebuilds it. It executes arbitrary R with the package loaded, before anyone reads the rendered document. |
| [vignettes_rmd](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_vignettes_rmd.yaml) | `vignettes/*.[Rr]md` | `Rmd` | no | `at_build`, `at_check` | An R Markdown vignette carries executable chunks. Vignette code runs when the vignette is rendered: during R CMD build, and again under R CMD check, which rebuilds it. It executes arbitrary R with the package loaded, before anyone reads the rendered document. |
| [vignettes_rnw](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_vignettes_rnw.yaml) | `vignettes/*.[Rr]nw` | `Rnw` | no | `at_build`, `at_check` | A Sweave or knitr vignette carries executable chunks between \<\<\>\>= and @, and inline macros. Vignette code runs when the vignette is rendered: during R CMD build, and again under R CMD check, which rebuilds it. It executes arbitrary R with the package loaded, before anyone reads the rendered document. |
| [vignettes_rsp](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/file_contexts/file_vignettes_rsp.yaml) | `vignettes/*.rsp` | `rsp` | no | `at_build`, `at_check` | An R.rsp vignette is a template: everything is output except the R between \<% and %\>. R.rsp builds it during R CMD build, and again under R CMD check, so the code executes with the package loaded before anyone reads the rendered document. |

## Code Contexts

Code contexts are lifecycle hooks whose bodies run automatically when a
namespace is loaded, attached, unloaded, or detached. These rules are
applied only where a package’s R code becomes its namespace – `R/`,
`R/unix/`, `R/windows/`. A `.onLoad` defined anywhere else ships as an
ordinary object and is never called, so attributing it to a hook would
be a false reading rather than a cautious one.

| Rule | Code Context | Phases | Description |
|----|----|----|----|
| [LastLib_base](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/code_contexts/code_lastlib.yaml) | `.Last.lib()` | `at_check`, `at_detach` | .Last.lib() executes arbitrary code when a package is detached from the R search path, e.g., by calling detach(); it does not run on unloadNamespace(). It runs only if the package exports it and does not define .onDetach(), which supersedes it; R CMD check reports “NB: .Last.lib will not be used unless it is exported”. R CMD check detaches the package while checking that it can be unloaded cleanly, so .Last.lib() runs during checking without any call from a user. |
| [onAttach_base](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/code_contexts/code_onattach.yaml) | `.onAttach()` | `at_build`, `at_check`, `at_install_src`, `at_attach` | .onAttach() executes arbitrary code when a package is attached to the R search path by library() or require(); attach() does not trigger it. R CMD INSTALL, R CMD build, and R CMD check attach the package while testing that it loads, so .onAttach() runs during those phases without any call from a user. |
| [onDetach_base](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/code_contexts/code_ondetach.yaml) | `.onDetach()` | `at_check`, `at_detach` | .onDetach() executes arbitrary code when a package is detached from the R search path, e.g., by calling detach(); it takes precedence over .Last.lib() when both are defined. R CMD check detaches the package while checking that it can be unloaded cleanly, so .onDetach() runs during checking without any call from a user. |
| [onLoad_base](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/code_contexts/code_onload.yaml) | `.onLoad()` | `at_build`, `at_check`, `at_install_src`, `at_load` | .onLoad() executes arbitrary code when a package namespace is loaded, e.g., by calling library(), require(), or loadNamespace(), or by accessing the namespace with ::. R CMD INSTALL, R CMD build, and R CMD check all load the package, so .onLoad() runs during those phases without any call from a user. |
| [onUnload_base](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/code_contexts/code_onunload.yaml) | `.onUnload()` | `at_check`, `at_unload` | .onUnload() executes arbitrary code when a package namespace is unloaded, e.g., by calling unloadNamespace() or detach(unload=TRUE). R CMD check unloads the namespace while checking that it can be unloaded cleanly, so .onUnload() runs during checking without any call from a user. |
| [on_load_rlang](https://github.com/tylerjssmith/pkgaudit/blob/main/inst/rules/code_contexts/code_onload_rlang.yaml) | [`rlang::on_load()`](https://rlang.r-lib.org/reference/on_load.html) | `at_build`, `at_check`, `at_install_src`, `at_load` | rlang::on_load() registers arbitrary code to execute when a package namespace is loaded, e.g., by calling library(), require(), or loadNamespace(), or by accessing the namespace with ::. R CMD INSTALL, R CMD build, and R CMD check all load the package, so the registered code runs during those phases without any call from a user. on_load() requires .onLoad() to contain rlang::run_on_load(). |

## Computed Contexts

Every pattern is attributed to the code context that contains it. Most
of those contexts are computed rather than matched by a rule, and so
have phases but no rule of their own. `R` and `Other` are computed from
where a pattern sits in the parse tree. The `Rd_` contexts come from
which part of a help file the code was extracted from, one per `\Sexpr`
stage, because the stages do not share a phase profile. The rest are
named for where the file sits – `data`, `tests`, `vignettes` – because
`R`’s phases are right for `R/` and wrong everywhere else. They are
defined under
[inst/rules/phases/](https://github.com/tylerjssmith/pkgaudit/tree/main/inst/rules/phases).

| Context | Phases | Description |
|----|----|----|
| `R` | `at_build`, `at_check`, `at_install_src` | Top-level code in an R script is evaluated once, when the lazy-load database is built during installation from source, which R CMD check and R CMD build also perform. It is not re-evaluated when the namespace is loaded: loading restores the values from that database. |
| `Other` | none | Code inside an ordinary function definition runs at no lifecycle phase. It executes only if something calls that function, never as a consequence of building, installing, checking, or loading the package. This holds for a function defined in a help-file example too. |
| `Rd_examples` | `at_check` | Code in an block of a help file is run by R CMD check, and by a user who calls example(). Building or installing the package renders the help page but never evaluates its examples. |
| `Rd_Sexpr_build` | `at_build`, `at_check`, `at_install_src` | A macro declaring stage=build is evaluated when R CMD build renders the help page, and when the package is installed from a source directory or checked. It is not reached when a source tarball is installed: build already evaluated it and froze the result into the Rd. |
| `Rd_Sexpr_install` | `at_build`, `at_check`, `at_install_src` | A macro declaring stage=install, or declaring no stage at all, which Writing R Extensions gives install as the default for. Evaluated whenever the page is rendered from source: build, either install, and check. Not when a prebuilt binary is installed. |
| `Rd_Sexpr_render` | `at_build`, `at_check` | A macro declaring stage=render is evaluated when the page is rendered for display: during R CMD build and R CMD check, and when a user calls help(). It does not run at either install. |
| `data` | `at_build`, `at_install_src` | A .R file under data/ is evaluated when R CMD build converts data/ to a lazy-load database, and when the package is installed from a source directory. It does not survive into a source tarball: build replaces it with the .rda it produced. |
| `demo` | none | A demo runs only when a user calls demo(). No lifecycle command reaches it, though it ships in the installed package. |
| `exec` | none | R code under exec/ runs only when a user invokes the script. R CMD INSTALL copies exec/ into the installed package and marks its contents executable, but no lifecycle command runs them. |
| `tests` | `at_check` | Test code, whether under tests/, tests/testthat/ or inst/tinytest/, is run by R CMD check and by nothing else. All three are reached through a runner in tests/. |
| `tools` | none | tools/ holds helper scripts that nothing runs on its own. They are reached only if configure or a Makevars invokes them, which is reported where that invocation appears. |
| `citation` | `at_check` | inst/CITATION is R code that utils::readCitationFile() evaluates. R CMD check reads it, as does any user who calls citation(). A plain .R file under inst/ is never sourced. |
| `Rprofile` | `at_build`, `at_install_src` | A .Rprofile at the package root is evaluated whenever a lifecycle command starts an R process inside the package: R CMD build, and installation from a source directory. It runs before any package is loaded. |
| `vignettes` | `at_build`, `at_check` | Vignette code runs when the vignette is rendered: during R CMD build, and again under R CMD check, which rebuilds it. Shared by Rmd, qmd and Rnw – the format decides how the code is extracted, not when it runs. |
