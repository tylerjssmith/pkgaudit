# pkgaudit 0.3.0.9000

* This is the development version for a major redesign coming with version
0.3.0. A major difference is that, rather than a single set of rules matching
specific function calls inside lifecycle hooks (e.g., `system()` in `.onLoad()`),
pkgaudit 0.3.0 will scan for files that may execute at build, check, or install
(*file_contexts*), code hooks that may execute at namespace load, attach,
unload, or detach (*code_contexts*), and syntactic patterns that should be
manually reviewed (*patterns*). This means a user will be able to see, for
example, all `system()` calls but stratify by those in specific hooks, in 
top-level code, or in regular functions.
