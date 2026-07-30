# inst/

pkgaudit rules are defined by YAML files available in [rules/](rules/). These
are loaded into a SQLite database, available in [db/](db/), by functions
defined in [scripts/build_db.R](scripts/build_db.R).

Each file- and code-context rule declares the lifecycle phases in which its
code runs. The two computed contexts, `Top-level` and `Other`, are not rules
and carry phases only; they are defined in [rules/phases/](rules/phases/).

Separately, [extdata/untrustedpkg](extdata/untrustedpkg) contains an example
package for use for vignettes.
