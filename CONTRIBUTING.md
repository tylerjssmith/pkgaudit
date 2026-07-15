# Contributing to pkgaudit

Thank you for your interest in contributing to pkgaudit. This document describes how to propose and implement new rules. Please read it carefully before opening an issue or pull request.

## Understanding the threat model

pkgaudit's rules are grounded in a documented threat model. Before proposing a rule, read [THREATMODEL.md](THREATMODEL.md) to understand the assets, threats, and attack surface pkgaudit is designed to address. Proposed rules should fit within this threat model or make a clear case for extending it.

## Proposing a rule

Open an issue before writing any code. Use the following structure:

**Pattern.** What code pattern does the rule detect? Be specific about syntax and context. A pattern like "`eval(parse())` anywhere in package source" is different from "`eval(parse())` inside `.onLoad()` or `.onAttach()`."

**Threat model fit.** How does this pattern relate to the threat model? Which asset does it threaten? Which adversary capability does it enable? At which point in the attack surface does it occur?

**ATT&CK mapping.** Which MITRE ATT&CK technique or techniques does this pattern map to? See the [ATT&CK framework](https://attack.mitre.org/) for the full taxonomy. If no mapping exists, explain why the pattern is still worth detecting.

**Positive case.** A minimal code example that should trigger the rule. Keep it as short as possible while remaining realistic.

**Negative case.** A minimal code example that should not trigger the rule, illustrating the most likely false positive scenario.

**Legitimate uses.** What are the known legitimate uses of this pattern in R packages? How common are they? How does the rule distinguish malicious from legitimate use, or does it flag both and rely on manual review?

Rules that do not include a documented negative case and legitimate use analysis will not be accepted, regardless of how clearly malicious the pattern appears. This discipline is what separates pkgaudit from naive pattern matching.

## Implementing a rule

Once a rule proposal is accepted in an issue, implementation follows these steps.

**1. Write the YAML file.** Create `inst/rules/<rule_name>.yaml` following the schema below. The rule name should be descriptive and end in `_rule`, following the convention of existing rules. `example_positive` and `example_negative` will be used in unit tests.

```yaml
name: your_rule_name_rule
version: "0.1.0"
type: warning
attck:
  - T0000.000
message: >-
  A concise description of the pattern and why it is security-relevant.
  This is shown to the user in findings output.
description: >-
  A one-sentence description of what the rule flags. Used internally.
xpath: >-
  //expr[
    ...
  ]
example_positive: |
  # Code that should trigger the rule
  .onLoad <- function(libname, pkgname) {
    ...
  }
example_negative: |
  # Code that should not trigger the rule
  .onLoad <- function(libname, pkgname) {
    packageStartupMessage("Loaded.")
  }
```

**2. Develop the XPath expression.** R code is parsed using `parse()` and converted to XML using `xmlparsedata::xml_parse_data()`. To inspect the parse tree for a code snippet:

```r
library(xml2)
library(xmlparsedata)

code <- '.onLoad <- function(libname, pkgname) {
  system("id")
}'

xml <- read_xml(xml_parse_data(parse(text = code, keep.source = TRUE)))
cat(as.character(xml))
```

XPath expressions are evaluated against this XML representation using `xml2::xml_find_all()`. Study the parse tree carefully before writing the XPath. The existing rules in `inst/rules/` are the best reference for XPath patterns that work in practice. For example:

``` r
xpath = "
  //expr[
    LEFT_ASSIGN
    and expr[1]/SYMBOL[text() = '.onLoad' or text() = '.onAttach']
    and expr[FUNCTION]/descendant::SYMBOL_FUNCTION_CALL[
      text() = 'system' or text() = 'system2'
    ]
  ]
"

xml2::xml_find_all(xml, xpath)
```

The line1 and col1 attributes of matching nodes provide the line and column numbers reported in findings.

**3. Open a pull request.** 

The pull request should include: `inst/rules/<rule_name>.yaml`.

Do not modify any other files unless the pull request description explains why.

## Adhering to quality standards

1. **Precision over recall.** A rule that fires rarely but reliably is more valuable than one that fires often but requires extensive manual triage. If your rule has a high false positive rate in legitimate packages, narrow the XPath expression or restrict the context before submitting.

2. **Context matters.** A pattern that is suspicious in a lifecycle hook may be unremarkable elsewhere. Prefer rules that are scoped to the contexts where the pattern is most likely to be malicious.

3. **Combinations are stronger than individual patterns.** A rule that matches the combination of a filesystem read followed by a network call in a hook is more diagnostic than either alone. If your pattern is weak in isolation, consider whether it belongs as a compound rule.

4. **The negative case is not optional.** Every rule must have a documented negative case that represents a realistic false positive scenario. If you cannot construct a plausible negative case, the pattern may be strong enough to warrant automatic flagging rather than a review recommendation — but that determination should be made explicitly in the issue discussion, not by omission.

## Asking questions

If you are unsure whether a pattern fits the threat model, open an issue and ask before investing time in implementation. It is much easier to refine a rule proposal than to revise a completed implementation.
