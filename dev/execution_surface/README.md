
<!-- README.md is generated from README.Rmd. Please edit that file. -->

# Mapping an R Package’s Execution Surface

The purpose of this project is to determine when code (R, Bash) in an R
package executes.

The method is direct measurement rather than reading the manual. `foo/`
is an instrumented probe package: every place a package can carry
executable code holds a marker that appends one line to a log when it
runs. `run_foo.sh` runs a single command with that log named, and
`drive_foo.sh` runs every command in `experiments.csv` in turn. A site
that fires during `R CMD INSTALL` runs at install; a site that never
fires anywhere runs at no lifecycle phase at all.

Every marker line is `<time>\t<site>\t<pid>`. The pid matters because
`R CMD INSTALL` and `R CMD build` do parts of their work in
subprocesses, and a site firing in a subprocess is still a site that
fired.

## Running the experiments

``` sh
./drive_foo.sh experiments.csv      # everything
./run_foo.sh -e "R CMD INSTALL foo/" -o logs/install_src.log   # one command
```

Logs are written to `logs/`. Build artifacts are confined to `build/`,
where `foo` is a symlink to the package: `R CMD build`,
`R CMD INSTALL --build` and `R CMD check` all write to the working
directory and offer no flag to redirect it, so the working directory is
what moves. Packages install into `lib/` rather than the real user
library.

`run_foo.sh` points `R_LIBS_USER` at `lib/`, which *replaces* the user
library rather than adding to it. The testing frameworks the probe
exercises — `testthat`, `tinytest` and `RUnit` — therefore have to be
installed there too, or their rows measure nothing. `lib/` is not
tracked: when it is absent, `run_foo.sh` rebuilds it by running
`make_lib.R`, which installs every package in `lib.lock` from CRAN and
reports any version that differs from the lock, the record of the
library the shipped logs were measured against.

## The probe package

    foo/.Rprofile
    foo/cleanup
    foo/configure
    foo/data/probe.R
    foo/demo/00Index
    foo/demo/probe.R
    foo/DESCRIPTION
    foo/exec/probe.R
    foo/exec/probe.sh
    foo/inst/CITATION
    foo/inst/probe.R
    foo/inst/tinytest/test_probe.R
    foo/inst/unitTests/runit.probe.R
    foo/man/probe_examples.Rd
    foo/man/probe_sexpr.Rd
    foo/man/probe_wrappers.Rd
    foo/man/unix/probe_unix_examples.Rd
    foo/man/unix/probe_unix_sexpr.Rd
    foo/man/windows/probe_windows_examples.Rd
    foo/man/windows/probe_windows_sexpr.Rd
    foo/NAMESPACE
    foo/R/probe.R
    foo/R/unix/probe.R
    foo/R/windows/probe.R
    foo/src/install.libs.R
    foo/src/Makevars
    foo/src/probe.c
    foo/tests/probe.R
    foo/tests/runit.R
    foo/tests/testthat.R
    foo/tests/testthat/helper-probe.R
    foo/tests/testthat/test-probe.R
    foo/tests/tinytest.R
    foo/tools/probe.R
    foo/vignettes/probe.Rnw

Files are named `probe.*`, or `probe_*.*` where more than one sits in
the same directory, **except** where R expects a particular name:
`DESCRIPTION`, `NAMESPACE`, `configure`, `cleanup`, `.Rprofile`,
`src/Makevars`, `src/install.libs.R`, `demo/00Index` and
`inst/CITATION`.

Two naming details are load-bearing:

- `man/unix/` and `man/windows/` are merged into `man/` at install time,
  so a shared basename silently overwrites the base page. The first run
  of this experiment lost `man/probe_examples.Rd` entirely to
  `man/unix/` before the files were given distinct names.
- `inst/probe.R` is a control. `inst/` is copied verbatim into the
  installed package, so a plain R script there should never be sourced;
  it exists to show that whatever `inst/CITATION` does is specific to
  `CITATION`.

## Experiments

| Command (`-e`) | Log (`-o`) |
|:---|:---|
| R CMD build foo/ | logs/build.log |
| R CMD build –no-build-vignettes foo/ | logs/build_novignette.log |
| R CMD INSTALL foo/ | logs/install_src.log |
| R CMD INSTALL foo_0.1.0.tar.gz | logs/install_tarball.log |
| R CMD check –no-manual foo_0.1.0.tar.gz | logs/check.log |
| R CMD check –no-manual –as-cran foo_0.1.0.tar.gz | logs/check_ascran.log |
| R CMD INSTALL –build foo/ | logs/binary_make.log |
| R CMD INSTALL foo_0.1.0.tgz | logs/install_bin.log |
| Rscript -e ‘loadNamespace(“foo”)’ | logs/load.log |
| Rscript -e ‘library(foo)’ | logs/attach.log |
| Rscript -e ‘library(foo); detach(package:foo)’ | logs/detach.log |
| Rscript -e ‘library(foo); detach(package:foo, unload=TRUE)’ | logs/unload.log |
| Rscript -e ‘citation(“foo”)’ | logs/citation.log |
| Rscript -e ‘demo(probe, package=“foo”)’ | logs/demo.log |
| Rscript -e ‘data(probe_data, package=“foo”)’ | logs/data.log |
| Rscript foo/tools/probe.R | logs/tools.log |
| sh ../lib/foo/exec/probe.sh | logs/exec.log |
| Rscript ../lib/foo/exec/probe.R | logs/exec_R.log |
| Rscript -e ‘print(help(probe_sexpr, package = “foo”))’ | logs/help_render.log |

Row order matters. `R CMD build` has to run before anything that
installs or checks the tarball it produces, and `R CMD INSTALL --build`
before the binary is installed. `drive_foo.sh` clears `build/` first, so
a command that fails before writing its tarball cannot leave the
previous one behind for later rows to test silently.

## Results

    LOG                         EXIT  SITES
    logs/build.log              0     makevars cleanup rprofile rprofile_fn_called configure install_libs install_libs_fn_called data_R data_fn_called top_level r_fn_called r_unix r_unix_fn_called rd_sexpr_build rd_sexpr_build_fn_called rd_sexpr_install rd_sexpr_install_fn_called rd_sexpr_nostage rd_unix_sexpr_nostage onLoad onAttach rd_sexpr_render rd_sexpr_render_fn_called rd_windows_sexpr_nostage vignette vignette_fn_called
    logs/build_novignette.log   0     makevars cleanup rprofile rprofile_fn_called configure install_libs install_libs_fn_called data_R data_fn_called top_level r_fn_called r_unix r_unix_fn_called rd_sexpr_build rd_sexpr_build_fn_called rd_sexpr_install rd_sexpr_install_fn_called rd_sexpr_nostage rd_unix_sexpr_nostage onLoad onAttach rd_sexpr_render rd_sexpr_render_fn_called rd_windows_sexpr_nostage
    logs/install_src.log        0     configure makevars install_libs install_libs_fn_called data_R data_fn_called rprofile rprofile_fn_called top_level r_fn_called r_unix r_unix_fn_called rd_sexpr_build rd_sexpr_build_fn_called rd_sexpr_install rd_sexpr_install_fn_called rd_sexpr_nostage rd_unix_sexpr_nostage onLoad onAttach
    logs/install_tarball.log    0     configure makevars install_libs install_libs_fn_called top_level r_fn_called r_unix r_unix_fn_called rd_sexpr_install rd_sexpr_install_fn_called rd_sexpr_nostage rd_unix_sexpr_nostage onLoad onAttach
    logs/check.log              0     configure makevars install_libs install_libs_fn_called top_level r_fn_called r_unix r_unix_fn_called rd_sexpr_install rd_sexpr_install_fn_called rd_sexpr_nostage rd_unix_sexpr_nostage onLoad onAttach citation citation_fn_called onDetach onUnload rd_sexpr_build rd_sexpr_build_fn_called rd_sexpr_render rd_sexpr_render_fn_called rd_windows_sexpr_nostage rd_examples rd_examples_fn_called rd_unix_examples rd_unwrapped rd_dontshow rd_testonly tests_R tests_fn_called runit_test runit_fn_called runit_fn_framework_called testthat_helper testthat_helper_fn_called testthat_test testthat_fn_called testthat_in_test_that tinytest_test tinytest_fn_called vignette vignette_fn_called
    logs/check_ascran.log       0     citation citation_fn_called configure makevars install_libs install_libs_fn_called top_level r_fn_called r_unix r_unix_fn_called rd_sexpr_install rd_sexpr_install_fn_called rd_sexpr_nostage rd_unix_sexpr_nostage onLoad onAttach onDetach onUnload rd_sexpr_build rd_sexpr_build_fn_called rd_sexpr_render rd_sexpr_render_fn_called rd_windows_sexpr_nostage rd_examples rd_examples_fn_called rd_unix_examples rd_unwrapped rd_dontshow rd_testonly rd_donttest tests_R tests_fn_called runit_test runit_fn_called runit_fn_framework_called testthat_helper testthat_helper_fn_called testthat_test testthat_fn_called testthat_in_test_that tinytest_test tinytest_fn_called vignette vignette_fn_called
    logs/binary_make.log        0     configure makevars install_libs install_libs_fn_called data_R data_fn_called rprofile rprofile_fn_called top_level r_fn_called r_unix r_unix_fn_called rd_sexpr_build rd_sexpr_build_fn_called rd_sexpr_install rd_sexpr_install_fn_called rd_sexpr_nostage rd_unix_sexpr_nostage onLoad onAttach
    logs/install_bin.log        0     <none>
    logs/load.log               0     onLoad
    logs/attach.log             0     onLoad onAttach
    logs/detach.log             0     onLoad onAttach onDetach
    logs/unload.log             0     onLoad onAttach onDetach onUnload
    logs/citation.log           0     citation citation_fn_called
    logs/demo.log               0     demo_R demo_fn_called
    logs/data.log               0     <none>
    logs/tools.log              0     tools_R tools_fn_called
    logs/exec.log               0     exec_sh
    logs/exec_R.log             0     exec_R exec_fn_called
    logs/help_render.log        0     rd_sexpr_render rd_sexpr_render_fn_called

    drive_foo.sh: 19 experiments, 0 failed

Read as a site-by-command matrix, with lifecycle commands first and the
user-invoked controls after:

| site | build | build_novignette | install_src | install_tarball | check | check_ascran | binary_make | install_bin | load | attach | detach | unload |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|:---|:---|:---|:---|
| makevars | x | x | x | x | x | x | x |  |  |  |  |  |
| cleanup | x | x |  |  |  |  |  |  |  |  |  |  |
| rprofile | x | x | x |  |  |  | x |  |  |  |  |  |
| rprofile_fn_called | x | x | x |  |  |  | x |  |  |  |  |  |
| configure | x | x | x | x | x | x | x |  |  |  |  |  |
| install_libs | x | x | x | x | x | x | x |  |  |  |  |  |
| install_libs_fn_called | x | x | x | x | x | x | x |  |  |  |  |  |
| data_R | x | x | x |  |  |  | x |  |  |  |  |  |
| data_fn_called | x | x | x |  |  |  | x |  |  |  |  |  |
| top_level | x | x | x | x | x | x | x |  |  |  |  |  |
| r_fn_called | x | x | x | x | x | x | x |  |  |  |  |  |
| r_unix | x | x | x | x | x | x | x |  |  |  |  |  |
| r_unix_fn_called | x | x | x | x | x | x | x |  |  |  |  |  |
| rd_sexpr_build | x | x | x |  | x | x | x |  |  |  |  |  |
| rd_sexpr_build_fn_called | x | x | x |  | x | x | x |  |  |  |  |  |
| rd_sexpr_install | x | x | x | x | x | x | x |  |  |  |  |  |
| rd_sexpr_install_fn_called | x | x | x | x | x | x | x |  |  |  |  |  |
| rd_sexpr_nostage | x | x | x | x | x | x | x |  |  |  |  |  |
| rd_unix_sexpr_nostage | x | x | x | x | x | x | x |  |  |  |  |  |
| onLoad | x | x | x | x | x | x | x |  | x | x | x | x |
| onAttach | x | x | x | x | x | x | x |  |  | x | x | x |
| rd_sexpr_render | x | x |  |  | x | x |  |  |  |  |  |  |
| rd_sexpr_render_fn_called | x | x |  |  | x | x |  |  |  |  |  |  |
| rd_windows_sexpr_nostage | x | x |  |  | x | x |  |  |  |  |  |  |
| vignette | x |  |  |  | x | x |  |  |  |  |  |  |
| vignette_fn_called | x |  |  |  | x | x |  |  |  |  |  |  |
| citation |  |  |  |  | x | x |  |  |  |  |  |  |
| citation_fn_called |  |  |  |  | x | x |  |  |  |  |  |  |
| onDetach |  |  |  |  | x | x |  |  |  |  | x | x |
| onUnload |  |  |  |  | x | x |  |  |  |  |  | x |
| rd_examples |  |  |  |  | x | x |  |  |  |  |  |  |
| rd_examples_fn_called |  |  |  |  | x | x |  |  |  |  |  |  |
| rd_unix_examples |  |  |  |  | x | x |  |  |  |  |  |  |
| rd_unwrapped |  |  |  |  | x | x |  |  |  |  |  |  |
| rd_dontshow |  |  |  |  | x | x |  |  |  |  |  |  |
| rd_testonly |  |  |  |  | x | x |  |  |  |  |  |  |
| tests_R |  |  |  |  | x | x |  |  |  |  |  |  |
| tests_fn_called |  |  |  |  | x | x |  |  |  |  |  |  |
| runit_test |  |  |  |  | x | x |  |  |  |  |  |  |
| runit_fn_called |  |  |  |  | x | x |  |  |  |  |  |  |
| runit_fn_framework_called |  |  |  |  | x | x |  |  |  |  |  |  |
| testthat_helper |  |  |  |  | x | x |  |  |  |  |  |  |
| testthat_helper_fn_called |  |  |  |  | x | x |  |  |  |  |  |  |
| testthat_test |  |  |  |  | x | x |  |  |  |  |  |  |
| testthat_fn_called |  |  |  |  | x | x |  |  |  |  |  |  |
| testthat_in_test_that |  |  |  |  | x | x |  |  |  |  |  |  |
| tinytest_test |  |  |  |  | x | x |  |  |  |  |  |  |
| tinytest_fn_called |  |  |  |  | x | x |  |  |  |  |  |  |
| rd_donttest |  |  |  |  |  | x |  |  |  |  |  |  |
| demo_R |  |  |  |  |  |  |  |  |  |  |  |  |
| demo_fn_called |  |  |  |  |  |  |  |  |  |  |  |  |
| tools_R |  |  |  |  |  |  |  |  |  |  |  |  |
| tools_fn_called |  |  |  |  |  |  |  |  |  |  |  |  |
| exec_sh |  |  |  |  |  |  |  |  |  |  |  |  |
| exec_R |  |  |  |  |  |  |  |  |  |  |  |  |
| exec_fn_called |  |  |  |  |  |  |  |  |  |  |  |  |

| site                       | citation | demo | data | tools | exec | exec_R | help_render |
|:---------------------------|:---------|:-----|:-----|:------|:-----|:-------|:------------|
| makevars                   |          |      |      |       |      |        |             |
| cleanup                    |          |      |      |       |      |        |             |
| rprofile                   |          |      |      |       |      |        |             |
| rprofile_fn_called         |          |      |      |       |      |        |             |
| configure                  |          |      |      |       |      |        |             |
| install_libs               |          |      |      |       |      |        |             |
| install_libs_fn_called     |          |      |      |       |      |        |             |
| data_R                     |          |      |      |       |      |        |             |
| data_fn_called             |          |      |      |       |      |        |             |
| top_level                  |          |      |      |       |      |        |             |
| r_fn_called                |          |      |      |       |      |        |             |
| r_unix                     |          |      |      |       |      |        |             |
| r_unix_fn_called           |          |      |      |       |      |        |             |
| rd_sexpr_build             |          |      |      |       |      |        |             |
| rd_sexpr_build_fn_called   |          |      |      |       |      |        |             |
| rd_sexpr_install           |          |      |      |       |      |        |             |
| rd_sexpr_install_fn_called |          |      |      |       |      |        |             |
| rd_sexpr_nostage           |          |      |      |       |      |        |             |
| rd_unix_sexpr_nostage      |          |      |      |       |      |        |             |
| onLoad                     |          |      |      |       |      |        |             |
| onAttach                   |          |      |      |       |      |        |             |
| rd_sexpr_render            |          |      |      |       |      |        | x           |
| rd_sexpr_render_fn_called  |          |      |      |       |      |        | x           |
| rd_windows_sexpr_nostage   |          |      |      |       |      |        |             |
| vignette                   |          |      |      |       |      |        |             |
| vignette_fn_called         |          |      |      |       |      |        |             |
| citation                   | x        |      |      |       |      |        |             |
| citation_fn_called         | x        |      |      |       |      |        |             |
| onDetach                   |          |      |      |       |      |        |             |
| onUnload                   |          |      |      |       |      |        |             |
| rd_examples                |          |      |      |       |      |        |             |
| rd_examples_fn_called      |          |      |      |       |      |        |             |
| rd_unix_examples           |          |      |      |       |      |        |             |
| rd_unwrapped               |          |      |      |       |      |        |             |
| rd_dontshow                |          |      |      |       |      |        |             |
| rd_testonly                |          |      |      |       |      |        |             |
| tests_R                    |          |      |      |       |      |        |             |
| tests_fn_called            |          |      |      |       |      |        |             |
| runit_test                 |          |      |      |       |      |        |             |
| runit_fn_called            |          |      |      |       |      |        |             |
| runit_fn_framework_called  |          |      |      |       |      |        |             |
| testthat_helper            |          |      |      |       |      |        |             |
| testthat_helper_fn_called  |          |      |      |       |      |        |             |
| testthat_test              |          |      |      |       |      |        |             |
| testthat_fn_called         |          |      |      |       |      |        |             |
| testthat_in_test_that      |          |      |      |       |      |        |             |
| tinytest_test              |          |      |      |       |      |        |             |
| tinytest_fn_called         |          |      |      |       |      |        |             |
| rd_donttest                |          |      |      |       |      |        |             |
| demo_R                     |          | x    |      |       |      |        |             |
| demo_fn_called             |          | x    |      |       |      |        |             |
| tools_R                    |          |      |      | x     |      |        |             |
| tools_fn_called            |          |      |      | x     |      |        |             |
| exec_sh                    |          |      |      |       | x    |        |             |
| exec_R                     |          |      |      |       |      | x      |             |
| exec_fn_called             |          |      |      |       |      | x      |             |

## What the results establish

**A function body runs when something calls it, and not otherwise — in
every context.** Each file context carries a pair of sites:
`*_fn_called`, a function invoked by top-level code in the same file,
and `*_fn_uncalled`, one only defined. Across all nineteen pairs,
`*_fn_called` fires in exactly the set of commands its context’s
top-level site fires in, and no `*_fn_uncalled` site fires anywhere.

So there is nothing special about a function body’s *position*. Whether
it runs is decided by whether it is reached, and the two bounds —
reached from top level, never reached — are the widest and narrowest
readings available for code whose call graph has not been traced. Both
are measurements here rather than inferences, which is what lets a
scanner report one of them and say which.

**A framework can supply the caller.** `runit_fn_framework_called` sits
inside `test.probe()`, a function `inst/unitTests/runit.probe.R` defines
and never calls — and it fires during `R CMD check`, because RUnit calls
it by name. The uncalled bound is therefore not a floor in a test
directory: a function that looks unreached from inside the file may be
reached from outside it.

**A lifecycle hook outside `R/` is not a hook.** `.onLoad` defined in
`data/probe.R` and in `tests/probe.R` never fires, in any command. Only
code that becomes the package namespace can supply one; elsewhere the
same definition ships as an ordinary object that nothing calls.

**The three testing layouts behave alike.** `tests/testthat/` — both a
`helper-*.R` file and a `test-*.R` file — `inst/tinytest/` and
`inst/unitTests/` all fire during `R CMD check` and nowhere else,
matching plain `tests/*.R`. Code inside a `test_that()` block fires with
the rest of its file, as expected: the block is a braced argument, not a
function definition.

**Binary installation executes nothing.** `install_bin` is the only
command that fires no site at all.

**`src/Makevars` is the only unconditional build-time site.** It fires
during `R CMD build` even with `--no-build-vignettes`, because build
runs make over `src/` to clean object files before packaging, and a `:=`
assignment is evaluated while make parses the file. No compilation is
involved.

**Everything else at build time is conditional on there being something
to evaluate.** With neither vignettes nor `\Sexpr`, `R CMD build`
reaches only `makevars` and `cleanup`. Add a vignette, or a help page
containing `\Sexpr`, and build installs and loads the package, reaching
`configure`, `install_libs`, `top_level`, `.onLoad` and the rest. Since
both are common, the conservative reading is that these contexts do run
at build.

**A failed build is not a safety property.** Before TeX was available
here, the vignette step failed and `R CMD build` exited non-zero — after
firing every one of those sites. Code runs before the failure.

**`data/*.R` does not survive `R CMD build`.** It is evaluated at build
time and replaced by `data/probe.rda` in the tarball. It fires when
installing from a source *directory* and never when installing from the
tarball, because by then the R file is gone.

**`\Sexpr` stages differ, and no stage means install.** The unlabelled
`\Sexpr` is identical to `stage=install` across every experiment, as
Writing R Extensions says. `stage=render` does not run at either
install; `stage=build` does not run when installing a tarball, its
result having been frozen into the Rd at build time — the same
evaluate-and-freeze pattern as `data/*.R`.

**`\examples` is check-only,** and the wrappers inside it divide three
ways. `\dontshow` and `\testonly` fire wherever the unwrapped code does.
`\donttest` is skipped by a plain `R CMD check` but fires under
`--as-cran`, the check CRAN performs, so it is not code that goes unrun.
`\dontrun` fires nowhere.

**`inst/CITATION` runs during `R CMD check`,** and on `citation()`. The
control, `inst/probe.R`, never fires anywhere, so this is specific to
the `CITATION` filename and not a property of `inst/`.

**`demo/`, `tools/` and `exec/` run at no lifecycle phase.** Each fires
only under direct invocation, `exec/` for both the shell script and the
R file. The controls matter: without them, a silent log cannot
distinguish “never reached” from “instrumentation broken”.

**`.Rprofile` at the package root fires** during `R CMD build` and
installation from a source directory — R picks it up when a process
starts with its working directory inside the package.

**`R/unix/` behaves exactly like `R/`; `R/windows/` never fires.** As
expected on a Unix-alike.

**`man/windows/` is not inert on Unix.** `rd_windows_sexpr_nostage`
fires during `R CMD build` and `R CMD check` even though the page is
never installed here: both process every Rd file under `man/`, including
platform subdirectories. `man/windows/`’s `\examples` never fires,
because examples only run for installed pages.

## `.Last.lib` and `.onDetach` are mutually exclusive

`.Last.lib` never appears in these logs, and that is the finding rather
than a gap. It is defined in `R/probe.R` alongside `.onDetach`, is
exported, and is present in both the package environment and the
namespace — and `detach()` still does not call it.

An isolated two-package experiment settles it:

| package defines             | fires on `detach()` |
|-----------------------------|---------------------|
| `.Last.lib` only            | `.Last.lib`         |
| `.Last.lib` and `.onDetach` | `.onDetach` only    |

So the two occupy the same phase and the same trigger — detaching an
attached package — but R calls only one, and `.onDetach` wins.
`.Last.lib` is an alternative, not a duplicate, which means a scan that
looks only for `.onDetach` misses the detach-time execution site of any
package that defines just `.Last.lib`.

## What was deliberately not tested

**`autoconf` / the `at_autoconf` phase.** R never runs `autoconf`;
regenerating `configure` from `configure.ac` is something a maintainer
does, not something that happens to a package a user installs. Probing
it would measure a different kind of event from every other phase here.

**`src/Makefile`.** R uses `src/Makefile` *instead of* R’s default make
process, so it cannot coexist with `src/Makevars` in one package and
would need a second probe package. Assumed to execute at the same phases
as `src/Makevars`: both are make fragments R invokes at the same points
in build, check and installation from source.

**Windows variants** — `configure.win`, `configure.ucrt`, `cleanup.win`,
`cleanup.ucrt`, `Makevars.win`, `Makevars.ucrt`, `Makefile.win`,
`Makefile.ucrt`. These cannot be reached from a Unix-alike. Each is
assumed to execute at the same phases as its Unix counterpart, being the
same mechanism selected by platform. `R/windows/` and `man/windows/`
*are* included above, because their directories exist in a package built
anywhere and their behavior on Unix is itself worth knowing.

**`R_init_foo()`**, the load-time site belonging to compiled code.
`src/probe.c` exists only so that R runs make; it is not instrumented,
because compiling is not executing.

**`po/`.** Message catalogues are translation data, not code. There is
no evaluation step to instrument.
