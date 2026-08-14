# inst/

pkgaudit rules are defined by YAML files available in [rules/](rules/). These
are loaded into a SQLite database, available in [db/](db/), by functions
defined in [scripts/build_db.R](scripts/build_db.R).

Each file- and code-context rule declares the lifecycle phases in which its
code runs. The two computed contexts, `top_level` and `in_function`, are not
rules and carry no phases of their own: they inherit from the file context they
sit in.

Separately, [extdata/untrustedpkg](extdata/untrustedpkg) contains an example
package for use for vignettes.
