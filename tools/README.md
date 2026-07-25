# tools/

[`download_cran.R`](download_cran.R) and [`audit_cran.R`](audit_cran.R) contain 
functions used to run pkgaudit on many (often all) packages hosted by CRAN. This
is done to evaluate new and existing rules. It is not expected that most 
pkgaudit users will ever call these functions, so they are provided here and may
be defined by calling `source()` on the scripts.

**IMPORTANT: Respect your CRAN mirror's bandwidth.** Run `download_cran()` 
infrequently and use `pause` > 0 (default is 0.5) to rate-limit the downloads. 
For more frequent downloads, use `rsync` to host a mirror as described by 
[CRAN](https://cran.r-project.org/mirror-howto.html).

