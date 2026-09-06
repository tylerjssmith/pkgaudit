#!/usr/bin/env Rscript
# Lint R/ and fail the build on any lint. Run from the package root.
#
# The linter set is confined to linters that read the parse tree and nothing
# else. lintr's evaluating linters are excluded on purpose: object_usage_linter()
# calls eval(), and sprintf_linter() evaluates each sprintf() call, which loads
# the namespace a qualified call names. This runs on pull requests, so nothing
# here may execute what it reads.
#
# parse_settings = FALSE for the same reason. lintr otherwise searches the tree
# for a configuration file and sources .lintr.R, or evaluates every field of a
# .lintr, before linting anything.

library(lintr)

# structure() is in lintr's default undesirable set for performance reasons. It
# is preferred here for readability.
undesirable_functions <- default_undesirable_functions[
  names(default_undesirable_functions) != "structure"
]

linters <- list(
  vector_logic_linter(),
  equals_na_linter(),
  class_equals_linter(),
  duplicate_argument_linter(),
  # The floor DESCRIPTION declares.
  backport_linter("4.1.0"),
  absolute_path_linter(),
  T_and_F_symbol_linter(),
  package_hooks_linter(),
  undesirable_operator_linter(),
  undesirable_function_linter(
    fun = undesirable_functions,
    symbol_is_undesirable = FALSE
  )
)

lints <- lint_dir(
  "R",
  linters = linters,
  pattern = "[.][Rr]$",
  parse_settings = FALSE
)

print(lints)

if (length(lints) > 0L) {
  stop("lintr reported ", length(lints), " lint(s) in R/.", call. = FALSE)
}
