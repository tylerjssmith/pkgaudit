
``` r
library(tidyverse)
library(pkgaudit)

source("scripts/download_cran.R")
source("scripts/survey_tarballs.R")
source("scripts/survey_cran.R")

SNAPSHOT_DIR = "../../../snapshot"
```

# Survey of R Packages on CRAN

## Download CRAN

The following code obtain a list of available packages.

``` r
available = available.packages("https://cran.rstudio.com/src/contrib")
available = as.data.frame(available[, c("Package","Version","MD5sum")])
available = available[!duplicated(available), ]
write_csv(available, "results/available_packages.csv")
```

The following code loads the list of available packages we obtained.

``` r
available_saved = read_csv("results/available_packages.csv",
  show_col_types = FALSE)
head(available_saved)
#> # A tibble: 6 × 3
#>   Package       Version MD5sum                          
#>   <chr>         <chr>   <chr>                           
#> 1 a11yShiny     0.1.4   7d459dbea2fc8efaa5d670ba6433c558
#> 2 a5R           0.5.0   cee50e37bb14fc3ca2c864313e79dc63
#> 3 aae.pop       0.2.0   d45f2552ba2422102e0c8742fe576ee2
#> 4 AalenJohansen 1.0     d7eb2a6275daa6af43bf8a980398b312
#> 5 aamatch       0.4.5   1cc8c77839c24b9a8bb453aa7141df94
#> 6 AATtools      0.0.3   ea8127d953ca6a2f118ea49441772af6
```

The following code downloads the available packages as source tarballs.
It confirms that the MD5 hash claimed by the mirror matches the MD5 hash
of the downloaded file, and adds the more secure (collision-resistant)
SHA-256 hash.

The snapshot is large (~18 GB) and was saved outside of the package
directory at the path stored in `SNAPSHOT_DIR`.

``` r
downloaded = download_cran(
  pkgs       = available[sample(1:nrow(available), 20), ], 
  dir        = SNAPSHOT_DIR, 
  check_md5  = TRUE, 
  add_sha256 = TRUE,
  pause = 0
)
write_csv(downloaded, "results/downloaded_packages.csv")
```

The following code loads the list of downloaded packages.

``` r
downloaded_saved = read_csv("results/downloaded_packages.csv",
  show_col_types = FALSE)
head(downloaded_saved[, c("package","version","md5_matches","sha256_local")])
#> # A tibble: 6 × 4
#>   package    version md5_matches sha256_local                                   
#>   <chr>      <chr>   <lgl>       <chr>                                          
#> 1 lomb       2.5.0   TRUE        042ecac6edde322c000d521c0f25e41544813e0a7dd83f…
#> 2 reghelper  1.1.2   TRUE        2366ea49d1a928555a388a1a7ae19a0287aef6e8df54ff…
#> 3 kgen       1.1.1   TRUE        1674fb872d38b2006f0c57a636404a48d6c88d383fd688…
#> 4 TransModel 2.3     TRUE        aaec72e5e6f51d4ab61ed25bd8c7c6171f37e3f3085913…
#> 5 MCMCvis    0.16.5  TRUE        3264e35b42972b32118101b1634d6984218678308cf8e0…
#> 6 HTGM3D     1.0.3   TRUE        8c140c7c184fad5b3f63a6f7a2740b6b332f9a2bb8372e…
```

## Survey CRAN

The following code runs `pkgaudit::audit_tarball` on every downloaded
package, combines the `pkgaudit` data frames across packages, and adds
`package` and `version` columns to distinguish the results.

``` r
findings = survey_cran(SNAPSHOT_DIR, rules = pkgaudit::load_rules())
write_rds(findings, "results/findings.rds", compress = "gz")
```

The following code loads the survey results, extracts the data frames,
defines the total number of tarballs surveyed as the denominator, and
defines two functions used to summarize the results.

``` r
# Load Saved Results
saved_findings = read_rds("results/findings.rds")

file_contexts = saved_findings$file_contexts
patterns      = saved_findings$patterns
matches       = saved_findings$matches
coverage      = saved_findings$coverage
errors        = saved_findings$errors
provenance    = saved_findings$provenance

# Get Denominator
N = length(list.files(SNAPSHOT_DIR, pattern = "\\.tar\\.gz$"))

# Define Summary Functions
get_proportion_hits <- function(data, x) {
  data %>%
    count({{ x }}) %>%
    mutate(p = n / sum(n) * 100) %>%
    arrange(desc(n))
}

get_proportion_pkgs <- function(data, x) {
  data %>%
    group_by({{ x }}) %>%
    summarise(n = n_distinct(package)) %>%
    mutate(p = n / N * 100) %>%
    rename(!!sym(paste0("n/", N)) := p) %>%
    arrange(desc(n))
}
```

### File Contexts

``` r
file_contexts %>%
  get_proportion_hits(file_context)
#>       file_context n         p
#> 1          cleanup 2 16.666667
#> 2        configure 2 16.666667
#> 3     src/Makevars 2 16.666667
#> 4  src/Makevars.in 2 16.666667
#> 5 src/Makevars.win 2 16.666667
#> 6     configure.ac 1  8.333333
#> 7    configure.win 1  8.333333
file_contexts %>%
  get_proportion_pkgs(file_context)
#> # A tibble: 7 × 3
#>   file_context         n `n/37`
#>   <chr>            <int>  <dbl>
#> 1 cleanup              2   5.41
#> 2 configure            2   5.41
#> 3 src/Makevars         2   5.41
#> 4 src/Makevars.in      2   5.41
#> 5 src/Makevars.win     2   5.41
#> 6 configure.ac         1   2.70
#> 7 configure.win        1   2.70
```

### Shell/Make-like Matches

``` r
matches %>%
  get_proportion_hits(rule)
#>          rule n  p
#> 1       chmod 2 50
#> 2     install 1 25
#> 3 interpreter 1 25
matches %>%
  get_proportion_pkgs(rule)
#> # A tibble: 3 × 3
#>   rule            n `n/37`
#>   <chr>       <int>  <dbl>
#> 1 chmod           1   2.70
#> 2 install         1   2.70
#> 3 interpreter     1   2.70
```

### R Patterns

``` r
patterns %>%
  get_proportion_hits(rule)
#>              rule  n         p
#> 1 deserialization 15 53.571429
#> 2          system  4 14.285714
#> 3         install  3 10.714286
#> 4           httr2  2  7.142857
#> 5     credentials  1  3.571429
#> 6            httr  1  3.571429
#> 7       namespace  1  3.571429
#> 8          source  1  3.571429
patterns %>%
  get_proportion_pkgs(rule)
#> # A tibble: 8 × 3
#>   rule                n `n/37`
#>   <chr>           <int>  <dbl>
#> 1 deserialization     3   8.11
#> 2 install             3   8.11
#> 3 system              3   8.11
#> 4 credentials         1   2.70
#> 5 httr                1   2.70
#> 6 httr2               1   2.70
#> 7 namespace           1   2.70
#> 8 source              1   2.70
```

## Tarballs
