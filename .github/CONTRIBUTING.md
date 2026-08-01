# Contributing to pkgaudit

Thank you for your interest in pkgaudit. The most valuable contribution to this
package is a rule: a new file context, code context, or pattern worth flagging,
or a revision to one that already exists.

Two things are out of scope here:

- A vulnerability **in pkgaudit itself** should be reported privately, not in a
  public issue. See [SECURITY.md](SECURITY.md).
- Malicious or vulnerable code in **some other R package** is not a pkgaudit
  issue. Contact that package's maintainer, and CRAN
  ([cran@r-project.org](mailto:cran@r-project.org)) if it is distributed there.

Rules are proposed, discussed, and drafted in GitHub issues. Contributions are
YAML files exchanged in an issue thread; the maintainer is responsible for
incorporating a finalized rule into the package, rebuilding the rules database
and test fixtures, and running the test suite and package check.

## Proposing a new or revised rule

### 1. Open an issue

Open a [GitHub issue](https://github.com/tylerjssmith/pkgaudit/issues)
proposing the change and explaining the security rationale:

- What the file, hook, or function call does.
- What an attacker gains by using it, and when it runs — for example, at build, 
  check, or install time, when a namespace is loaded, or only when a user calls 
  something.
- For a revision, what the current rule misses or over-matches.

Please also say whether you are proposing to **write the YAML file yourself** or
would like **someone else to write it**. Both are welcome. A well-argued
proposal with no YAML is a real contribution: deciding what is worth flagging,
and why, is the harder half of the work.

### 2. Discussion

The proposal is discussed and refined in the issue thread. This is where the
scope of a rule usually gets settled: which category it belongs to, exactly
which paths or function names it should cover, which related-but-different cases
it must *not* match, and whether it overlaps a rule that already exists.

### 3. Drafting

The rule is drafted as a YAML file and posted in the issue thread, either by the
person who proposed it or by someone else. See
[Writing the YAML](#writing-the-yaml) below for what it should contain.

The draft is reviewed in the thread, and that review covers the positive and
negative examples as much as the matching logic itself. The examples are where a
rule's boundary is actually decided, and they become the rule's tests.

### 4. CRAN-scale evaluation

A drafted rule is evaluated against a large sample of CRAN source packages,
ideally all of them, on two measures:

- **Precision** — of the findings the rule produces, what proportion really are
  the context or pattern it targets? A rule that fires on things it did not mean
  to catch teaches reviewers to ignore it.
- **Prevalence** — what proportion of CRAN packages have the context or pattern
  at all? A rule matching a large share of CRAN is not so much wrong as useless:
  it tells a reviewer nothing about the package in front of them.

pkgaudit aims for **precision above 0.95** and **prevalence below 0.05**, so
that a finding is worth a reviewer's attention. A rule that misses these targets
is not automatically rejected, but it needs a reason.

[tools/](../tools/) contains the functions used for these runs: `download_cran()`
to fetch source tarballs and `audit_cran()` to audit them in bulk. The 
maintainer will use them to evaluate proposed rules. If you run them yourself, 
please read [tools/README.md](../tools/README.md) first — it asks you to rate-limit 
downloads out of respect for CRAN mirror bandwidth.

### 5. Results and refinement

Results are posted in the issue thread, and the rule may be refined in light of
them. Steps 4 and 5 repeat as needed until the rule is finalized. It is normal
for a rule to go around this loop more than once; the first draft of a pattern
rule usually catches something it should not.

## Writing the YAML

A rule is data, not code, so contributing one means writing a YAML file rather
than R. The clearest starting point is an existing rule in the same category
under [inst/rules/](../inst/rules/). The
[How pkgaudit Works](../vignettes/how-it-works.Rmd) vignette walks
through one rule of each category and explains how its fields are used.

**Categories.** A rule is a file context (a file R executes during build, check,
or install), a code context (a lifecycle hook whose body runs when a namespace
is loaded, attached, unloaded, or detached), or a pattern (a security-relevant
function call).

**Names.** The YAML file name is prefixed with the rule's category —
`file_`, `code_`, or `pattern_` — but the `name` field inside it is not: the
category is already known from where the rule lives, and the name is what a
finding reports. A code context is named for the hook it matches and the package
that defines it, joined by an underscore, following their own capitalization and
separators (`onLoad_base`, `on_load_rlang`). A pattern that covers one package's
functions carries that package's name (`system_callr`), so a finding points at
the calls behind it.

**Fields.** Every rule has `name`, `version`, `type`, `message`,
`positive_examples`, and `negative_examples`. Beyond those:

- a **file context** rule adds `path` (directory to search, relative to the
  package root), `recursive`, and `pattern` (a regular expression matched
  against file names);
- a **code context** rule adds `xpath`;
- a **pattern** rule adds `xpath` and `attck` (MITRE ATT&CK technique IDs).

`type` is the language or format of what the rule matches, not a severity. A
file context rule is `R`, `shell`, `make`, or `other`; a code context or pattern
rule is always `R`, since both are matched against R's parse tree. How much a
finding matters is a property of the pattern together with the context it was
found in, which a rule cannot know, so no rule declares one.

**Phases.** A file or code context rule must also declare, as `TRUE` or `FALSE`,
each of the nine lifecycle phases in which its code runs: `at_autoconf`,
`at_build`, `at_check`, `at_install_src`, `at_install_bin`, `at_load`,
`at_attach`, `at_unload`, and `at_detach`. All nine are required, and the
database will not build without them. A pattern rule declares none: a pattern
inherits the phases of the code context it sits in.

Claim a phase only where the behavior has been observed. The existing
assignments were established by running `R CMD build`, `R CMD check`, and
`R CMD INSTALL` against instrumented packages rather than read from
documentation, and several are narrower than the documentation implies. Say in
the issue thread how you determined yours.

The two computed contexts, `Top-level` and `Other`, are not rules and are
authored separately under [inst/rules/phases/](../inst/rules/phases/).

`message` is shown to the user with every finding. It should be 1-2 short 
sentences. Write it so that someone who has never read the rule understands what 
was found and why it matters.

**Examples.** `positive_examples` are code or paths the rule must flag;
`negative_examples` are ones it must not. Both are required, and both are
reviewed. Write negatives that pin the boundary you care about rather than
obviously unrelated code: if a pattern rule should ignore `foo$system()`, that
is the negative worth having. Once a rule is merged these become test fixtures,
and the test suite requires that every positive is flagged and no negative is.

**Pattern rule conventions.** Match `SYMBOL_FUNCTION_CALL` so that a reference to
a function is not mistaken for a call to it, and exclude calls preceded by `$`
so that a list element or an object's method of the same name is not flagged.
Qualified (`pkg::fn()`) and unqualified (`fn()`) call forms should both match.

## Credit

Contributors of accepted rules are credited in `DESCRIPTION` as contributors
(`ctb`), whether they proposed the rule, drafted the YAML, or both. This
requires a name you are willing to have published, so it is opt-in — say in the
issue thread how you would like to be credited, or if you would prefer not to
be. If you would rather not appear in `DESCRIPTION`, a credit in `NEWS.md` is an
alternative.
