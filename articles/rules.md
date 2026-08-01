# pkgaudit Rule Coverage

pkgaudit v0.3.0 separates *when* code executes from *what* code does
using three categories of rules: file contexts, code contexts, and
patterns. Each rule is defined in a YAML file under
[inst/rules/](https://github.com/tylerjssmith/pkgaudit/tree/master/inst/rules)
and compiled into the SQLite database at `inst/db/rules.db`. The Rule
columns below link to the defining YAML files.

This vignette is generated from that database, at rules v0.3.0.

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

| Rule | File Context | Phases | Description |
|----|----|----|----|
| [cleanup](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_cleanup.yaml) | `cleanup` | `at_build` | cleanup is a shell script run on Unix-like systems at the end of R CMD build, and during installation from source only under R CMD INSTALL –clean or –preclean. It can execute arbitrary shell commands. |
| [cleanup_ucrt](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_cleanup_ucrt.yaml) | `cleanup.ucrt` | `at_build` | cleanup.ucrt is a shell script run on the Windows UCRT toolchain at the end of R CMD build, and during installation from source only under R CMD INSTALL –clean or –preclean; it takes precedence over cleanup.win when present. It can execute arbitrary shell commands. |
| [cleanup_win](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_cleanup_win.yaml) | `cleanup.win` | `at_build` | cleanup.win is a shell script run on Windows at the end of R CMD build, and during installation from source only under R CMD INSTALL –clean or –preclean. It can execute arbitrary shell commands. |
| [configure](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_configure.yaml) | `configure` | `at_build`, `at_check`, `at_install_src` | configure is a shell script used for system-dependent configuration when packages are installed from source, including the installs performed by R CMD check and by R CMD build when a package has vignettes. It can execute arbitrary shell commands. |
| [configure_ac](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_configure_ac.yaml) | `configure.ac` | `at_autoconf` | configure.ac is an Autoconf input file that does not itself execute; it is processed by Autoconf to generate the configure script, which executes shell commands when a package is installed from source. |
| [configure_in](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_configure_in.yaml) | `configure.in` | `at_autoconf` | configure.in is a legacy-named Autoconf input file that does not itself execute; it is processed by Autoconf to generate the configure script, which executes shell commands when a package is installed from source. |
| [configure_ucrt](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_configure_ucrt.yaml) | `configure.ucrt` | `at_build`, `at_check`, `at_install_src` | configure.ucrt is a shell script for system-dependent configuration on the Windows UCRT toolchain, executed when a package is installed from source, including the installs performed by R CMD check and by R CMD build when a package has vignettes; it takes precedence over configure.win when present. |
| [configure_win](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_configure_win.yaml) | `configure.win` | `at_build`, `at_check`, `at_install_src` | configure.win is a shell script for system-dependent configuration on Windows, executed when a package is installed from source, including the installs performed by R CMD check and by R CMD build when a package has vignettes. |
| [src_install_libs_R](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_src_install_libs_R.yaml) | `src/install.libs.R` | `at_build`, `at_check`, `at_install_src` | src/install.libs.R is an R script used in some packages to install executable programs and other binaries during installation from source, including the installs performed by R CMD check and by R CMD build when a package has vignettes. It can run arbitrary R code. |
| [src_makefile](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_src_makefile.yaml) | `src/Makefile` | `at_build`, `at_check`, `at_install_src` | src/Makefile is a makefile used to compile code in src/ when a package is installed from source, replacing R’s default make rules; the installs performed by R CMD check and by R CMD build also use it, and R CMD build runs its clean target. It is read by make and its recipes execute arbitrary shell commands. |
| [src_makefile_ucrt](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_src_makefile_ucrt.yaml) | `src/Makefile.ucrt` | `at_build`, `at_check`, `at_install_src` | src/Makefile.ucrt is a makefile used to compile code in src/ on the Windows UCRT toolchain when a package is installed from source, replacing R’s default make rules; the installs performed by R CMD check and by R CMD build also use it, and R CMD build runs its clean target. It is read by make and its recipes execute arbitrary shell commands. |
| [src_makefile_win](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_src_makefile_win.yaml) | `src/Makefile.win` | `at_build`, `at_check`, `at_install_src` | src/Makefile.win is a makefile used to compile code in src/ on Windows when a package is installed from source, replacing R’s default make rules; the installs performed by R CMD check and by R CMD build also use it, and R CMD build runs its clean target. It is read by make and its recipes execute arbitrary shell commands. |
| [src_makevars](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_src_makevars.yaml) | `src/Makevars` | `at_build`, `at_check`, `at_install_src` | src/Makevars sets make variables used to compile code in src/ when a package is installed from source, including the installs performed by R CMD check and by R CMD build; R CMD build also reads it when cleaning src/. It is read by make and can execute shell via make constructs such as \$(shell …). |
| [src_makevars_in](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_src_makevars_in.yaml) | `src/Makevars.in` | `at_build`, `at_check`, `at_install_src` | src/Makevars.in is a template that does not itself execute; it is processed by the configure script to generate src/Makevars, whose contents are then read by make to compile code in src/ when a package is installed from source, including the installs performed by R CMD check and by R CMD build. |
| [src_makevars_ucrt](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_src_makevars_ucrt.yaml) | `src/Makevars.ucrt` | `at_build`, `at_check`, `at_install_src` | src/Makevars.ucrt sets make variables used to compile code in src/ on the Windows UCRT toolchain when a package is installed from source, including the installs performed by R CMD check and by R CMD build; it takes precedence over Makevars.win, and R CMD build also reads it when cleaning src/. It is read by make and can execute shell via make constructs such as \$(shell …). |
| [src_makevars_win](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/file_contexts/file_src_makevars_win.yaml) | `src/Makevars.win` | `at_build`, `at_check`, `at_install_src` | src/Makevars.win sets make variables used to compile code in src/ on Windows when a package is installed from source, including the installs performed by R CMD check and by R CMD build; R CMD build also reads it when cleaning src/. It is read by make and can execute shell via make constructs such as \$(shell …). |

## Code Contexts

Code contexts are lifecycle hooks whose bodies run automatically when a
namespace is loaded, attached, unloaded, or detached.

| Rule | Code Context | Phases | Description |
|----|----|----|----|
| [LastLib_base](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/code_contexts/code_lastlib.yaml) | `.Last.lib()` | `at_check`, `at_detach` | .Last.lib() executes arbitrary code when a package is detached from the R search path, e.g., by calling detach(); it does not run on unloadNamespace(). It runs only if the package exports it and does not define .onDetach(), which supersedes it; R CMD check reports “NB: .Last.lib will not be used unless it is exported”. R CMD check detaches the package while checking that it can be unloaded cleanly, so .Last.lib() runs during checking without any call from a user. |
| [onAttach_base](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/code_contexts/code_onattach.yaml) | `.onAttach()` | `at_build`, `at_check`, `at_install_src`, `at_attach` | .onAttach() executes arbitrary code when a package is attached to the R search path by library() or require(); attach() does not trigger it. R CMD INSTALL, R CMD build, and R CMD check attach the package while testing that it loads, so .onAttach() runs during those phases without any call from a user. |
| [onDetach_base](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/code_contexts/code_ondetach.yaml) | `.onDetach()` | `at_check`, `at_detach` | .onDetach() executes arbitrary code when a package is detached from the R search path, e.g., by calling detach(); it takes precedence over .Last.lib() when both are defined. R CMD check detaches the package while checking that it can be unloaded cleanly, so .onDetach() runs during checking without any call from a user. |
| [onLoad_base](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/code_contexts/code_onload.yaml) | `.onLoad()` | `at_build`, `at_check`, `at_install_src`, `at_load` | .onLoad() executes arbitrary code when a package namespace is loaded, e.g., by calling library(), require(), or loadNamespace(), or by accessing the namespace with ::. R CMD INSTALL, R CMD build, and R CMD check all load the package, so .onLoad() runs during those phases without any call from a user. |
| [onUnload_base](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/code_contexts/code_onunload.yaml) | `.onUnload()` | `at_check`, `at_unload` | .onUnload() executes arbitrary code when a package namespace is unloaded, e.g., by calling unloadNamespace() or detach(unload=TRUE). R CMD check unloads the namespace while checking that it can be unloaded cleanly, so .onUnload() runs during checking without any call from a user. |
| [on_load_rlang](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/code_contexts/code_onload_rlang.yaml) | [`rlang::on_load()`](https://rlang.r-lib.org/reference/on_load.html) | `at_build`, `at_check`, `at_install_src`, `at_load` | rlang::on_load() registers arbitrary code to execute when a package namespace is loaded, e.g., by calling library(), require(), or loadNamespace(), or by accessing the namespace with ::. R CMD INSTALL, R CMD build, and R CMD check all load the package, so the registered code runs during those phases without any call from a user. on_load() requires .onLoad() to contain rlang::run_on_load(). |

## Computed Contexts

Every pattern is attributed to the code context that contains it. Two of
those contexts are computed rather than matched by a rule, and so have
phases but no rule of their own. They are defined under
[inst/rules/phases/](https://github.com/tylerjssmith/pkgaudit/tree/master/inst/rules/phases).

| Context | Phases | Description |
|----|----|----|
| `Top-level` | `at_build`, `at_check`, `at_install_src` | Top-level code in an R script is evaluated once, when the lazy-load database is built during installation from source, which R CMD check and R CMD build also perform. It is not re-evaluated when the namespace is loaded: loading restores the values from that database. |
| `Other` | none | Code inside an ordinary function definition runs at no lifecycle phase. It executes only if something calls that function, never as a consequence of building, installing, checking, or loading the package. |

## Patterns

Patterns are security-relevant function calls. Each pattern finding is
attributed to the code context it executes in, so a
[`system()`](https://rdrr.io/r/base/system.html) call inside `.onLoad`
is distinguished from one inside an ordinary function (“Other”) or at
top level (“Top-level”). Qualified (`pkg::fn()`) and unqualified
(`fn()`) call forms are both detected. Pattern rules carry [MITRE
ATT&CK](https://attack.mitre.org/) technique labels.

A pattern rule declares no phases of its own: a pattern inherits them
from the code context it sits in, listed in the two tables above.

| Rule | Pattern | Description |
|----|----|----|
| [curl](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_curl.yaml) | `curl()`, `curl_fetch_memory()`, `curl_fetch_disk()`, `curl_fetch_stream()`, `curl_fetch_multi()`, `curl_download()`, `curl_upload()`, `multi_download()`, `multi_run()`, `send_mail()` | A curl network call sends an outbound HTTP request or opens a connection to a remote host. A request may be used to exfiltrate credentials or other data, or to fetch a remote payload. |
| [decoding](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_decoding.yaml) | `base64decode()`, `base64_dec()`, `base64_decode()`, [`memDecompress()`](https://rdrr.io/r/base/memCompress.html), `rawToChar(as.raw())` | These functions decode or decompress data. Payloads may be encoded (e.g., as base64) to evade static detection and decoded at runtime. |
| [deserialization](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_deserialization.yaml) | [`readRDS()`](https://rdrr.io/r/base/readRDS.html), [`load()`](https://rdrr.io/r/base/load.html), [`unserialize()`](https://rdrr.io/r/base/serialize.html), [`dget()`](https://rdrr.io/r/base/dput.html) | readRDS(), load(), unserialize(), and dget() deserialize R objects or code, which can enable arbitrary code execution (CVE-2024-27322 for RDS). |
| [download_file](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_download_file.yaml) | [`download.file()`](https://rdrr.io/r/utils/download.file.html), [`url()`](https://rdrr.io/r/base/connections.html) | download.file() and url() retrieve or open a connection to a remote resource. This can stage a payload for execution via source() or system() in a two-stage attack. |
| [dynload](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_dynload.yaml) | [`dyn.load()`](https://rdrr.io/r/base/dynload.html), [`library.dynam()`](https://rdrr.io/r/base/library.dynam.html) | dyn.load() and library.dynam() load compiled code from a shared object, which executes outside the visible R source. |
| [eval_parse](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_eval_parse.yaml) | [`eval()`](https://rdrr.io/r/base/eval.html)/[`evalq()`](https://rdrr.io/r/base/eval.html) over [`parse()`](https://rdrr.io/r/base/parse.html), [`str2lang()`](https://rdrr.io/r/base/parse.html), or [`str2expression()`](https://rdrr.io/r/base/parse.html), when combined with a decoding call | eval() applied to parse(), str2lang(), or str2expression() constructs and evaluates code at runtime. Here code is produced by decoding or decompression, a classic shape for executing an obfuscated payload. |
| [httr](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_httr.yaml) | `GET()`, `POST()`, `PUT()`, `PATCH()`, `DELETE()`, `HEAD()`, `VERB()` | An httr HTTP call sends an outbound request. A request may be used to exfiltrate credentials or other data, or to fetch a remote payload. |
| [httr2](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_httr2.yaml) | `req_perform()`, `req_perform_iterative()`, `req_perform_parallel()`, `req_perform_sequential()`, `req_perform_stream()`, `req_perform_connection()`, `req_perform_promise()` | An httr2 HTTP call sends an outbound request. A request may be used to exfiltrate credentials or other data. |
| [indirection](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_indirection.yaml) | [`do.call()`](https://rdrr.io/r/base/do.call.html), [`match.fun()`](https://rdrr.io/r/base/match.fun.html), [`getFromNamespace()`](https://rdrr.io/r/utils/getFromNamespace.html), [`getExportedValue()`](https://rdrr.io/r/base/ns-reflect.html), [`getAnywhere()`](https://rdrr.io/r/utils/getAnywhere.html), `getFunction()`, when the first argument is a string literal | These functions resolve a function by name at runtime. A string-literal target is not a call site, so it evades pattern matching, and the namespace accessors additionally reach functions a package does not export. |
| [install](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_install.yaml) | [`install.packages()`](https://rdrr.io/r/utils/install.packages.html), `install_github()`, `install_gitlab()`, `install_bitbucket()`, `install_git()`, `install_url()`, `install_version()`, `install_local()`, `install_bioc()`, `install_dev()`, `install_cran()`, `pak()`, `pkg_install()`, `local_install()`, `lockfile_install()`, `BiocManager::install()`, [`renv::install()`](https://rstudio.github.io/renv/reference/install.html), `devtools::install()` | These functions install packages, optionally from a specified or remote source. A non-default source can introduce attacker-controlled code. |
| [options_repos](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_options_repos.yaml) | `options(repos = )` | options(repos = …) replaces the CRAN mirror for the R session. Subsequent install.packages() calls will fetch packages from the configured repository. If set to an attacker-controlled server, this poisons the installation source. |
| [rcurl](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_rcurl.yaml) | `getURL()`, `getURI()`, `getForm()`, `postForm()`, `curlPerform()` | An RCurl network call sends an outbound HTTP request. A request may be used to exfiltrate credentials or other data, or to fetch a remote payload. |
| [socket](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_socket.yaml) | [`socketConnection()`](https://rdrr.io/r/base/connections.html), [`make.socket()`](https://rdrr.io/r/utils/make.socket.html), [`serverSocket()`](https://rdrr.io/r/base/connections.html), [`socketAccept()`](https://rdrr.io/r/base/connections.html) | These functions open a raw network socket, which may be used to exfiltrate data or receive a remote payload outside the usual HTTP clients. |
| [source](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_source.yaml) | [`source()`](https://rdrr.io/r/base/source.html) | source() can fetch and execute local and remote R scripts. |
| [system](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_system.yaml) | [`system()`](https://rdrr.io/r/base/system.html), [`system2()`](https://rdrr.io/r/base/system2.html), `shell()`, [`pipe()`](https://rdrr.io/r/base/connections.html) | system(), system2(), shell() (on Windows), and pipe() execute arbitrary shell commands. |
| [system_callr](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_system_callr.yaml) | [`callr::r()`](https://callr.r-lib.org/reference/r.html), `r_bg()`, `r_safe()`, `r_copycat()`, `r_vanilla()`, [`callr::rcmd()`](https://callr.r-lib.org/reference/rcmd.html), `rcmd_bg()`, `rcmd_safe()`, `rcmd_copycat()`, `rscript()`, `r_session$new()`, `r_process$new()`, `rcmd_process$new()`, `rscript_process$new()` | These callr functions start a separate R session or run an R CMD command, which may be used to execute arbitrary R code or shell commands outside the visible R source. |
| [system_processx](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_system_processx.yaml) | [`processx::run()`](http://processx.r-lib.org/reference/run.md), [`processx::pipeline()`](http://processx.r-lib.org/reference/pipeline.md), `process$new()` | These processx functions run an external process, which may be used to execute arbitrary shell commands outside the visible R source. |
| [system_sys](https://github.com/tylerjssmith/pkgaudit/blob/master/inst/rules/patterns/pattern_system_sys.yaml) | `exec_wait()`, `exec_background()`, `exec_internal()`, `eval_safe()`, `eval_fork()`, `r_background()`, `r_internal()`, `r_wait()` | These sys functions run an external process or fork the R session, which may be used to execute arbitrary shell commands or a second R session outside the visible R source. |
