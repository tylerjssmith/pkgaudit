
``` r
library(tidyverse)
library(pkgaudit)

source("scripts/download_cran.R")
source("scripts/survey_cran.R")
source("scripts/survey_tarballs.R")

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
It checks whether the MD5 hash claimed by the mirror matches the MD5
hash of the downloaded file, and adds the more secure
(collision-resistant) SHA-256 hash.

The snapshot is large (~18 GB) and was saved outside of the package
directory at the path stored in `SNAPSHOT_DIR`.

``` r
downloaded = download_cran(
  pkgs       = available, 
  dir        = SNAPSHOT_DIR, 
  check_md5  = TRUE, 
  add_sha256 = TRUE,
  pause      = 0.2
)
write_csv(downloaded, "results/downloaded_packages.csv")
```

The following code loads the list of downloaded packages.

``` r
downloaded_saved = read_csv("results/downloaded_packages.csv",
  show_col_types = FALSE)
head(downloaded_saved[, c("package","version","md5_matches","sha256_local")])
#> # A tibble: 6 × 4
#>   package       version md5_matches sha256_local                                
#>   <chr>         <chr>   <lgl>       <chr>                                       
#> 1 a11yShiny     0.1.4   TRUE        c25b78c48c6c110f1f79cc3061c29b8c3827d1b9d00…
#> 2 a5R           0.5.0   TRUE        4345751e0d0a53b7723002915a4129e56fe7043cbbf…
#> 3 aae.pop       0.2.0   TRUE        b9268f69f3346fcfae5751d4e58144a5619f7b896a3…
#> 4 AalenJohansen 1.0     TRUE        240ef5cabcd7e9aeb2b4ad117a4a4b681386d3ea6d5…
#> 5 aamatch       0.4.5   TRUE        482f7161b6af4ff05925c3f5ff62227694de4a21799…
#> 6 AATtools      0.0.3   TRUE        89d64a7ee0b8057475dce349c258522169aac03707a…
```

We assert that every available package was downloaded, that no extra
package was downloaded, and that the MD5 hashes claimed by the mirror
match the hashes of the downloaded files.

``` r
# downloaded packages match available packages
expected = paste0(available_saved$Package, "_", available_saved$Version, ".tar.gz")
actual   = list.files(SNAPSHOT_DIR, pattern = "\\.tar\\.gz")

length(setdiff(expected, actual)) == 0
#> [1] TRUE
length(setdiff(actual, expected)) == 0
#> [1] TRUE

# MD5 checksums consistent
sum(downloaded_saved$md5_matches) == nrow(downloaded_saved)
#> [1] TRUE
```

## Survey CRAN

The following code runs `pkgaudit::audit_tarball` on every downloaded
package, combines the `pkgaudit` data frames across packages, and adds
`package` and `version` columns to the data frames to distinguish the
results.

``` r
findings = survey_cran(SNAPSHOT_DIR, rules = pkgaudit::load_rules())
write_rds(findings, "results/findings.rds", compress = "gz")
```

The following code loads the survey results, extracts the data frames,
defines the total number of tarballs surveyed as the denominator, and
defines two functions used to summarize the results. The first function
summarizes findings as proportions of findings; the second function
summarizes findings as proportions of packages.

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
    as.data.frame() %>%
    arrange(desc(n))
}
```

### File Contexts

``` r
file_contexts %>%
  get_proportion_hits(file_context)
#>          file_context    n           p
#> 1        src/Makevars 2494 34.78382148
#> 2    src/Makevars.win 2031 28.32635983
#> 3           configure  664  9.26080893
#> 4             cleanup  572  7.97768480
#> 5       configure.win  456  6.35983264
#> 6     src/Makevars.in  443  6.17852162
#> 7        configure.ac  226  3.15202232
#> 8         cleanup.win  111  1.54811715
#> 9   src/Makevars.ucrt   99  1.38075314
#> 10 src/install.libs.R   43  0.59972106
#> 11       src/Makefile   13  0.18131102
#> 12   src/Makefile.win   12  0.16736402
#> 13     configure.ucrt    4  0.05578801
#> 14       cleanup.ucrt    2  0.02789400
file_contexts %>%
  get_proportion_pkgs(file_context)
#>          file_context    n      n/24741
#> 1        src/Makevars 2494 10.080433289
#> 2    src/Makevars.win 2031  8.209045714
#> 3           configure  664  2.683804212
#> 4             cleanup  572  2.311951821
#> 5       configure.win  456  1.843094459
#> 6     src/Makevars.in  443  1.790550099
#> 7        configure.ac  226  0.913463482
#> 8         cleanup.win  111  0.448647993
#> 9   src/Makevars.ucrt   99  0.400145507
#> 10 src/install.libs.R   43  0.173800574
#> 11       src/Makefile   13  0.052544360
#> 12   src/Makefile.win   12  0.048502486
#> 13     configure.ucrt    4  0.016167495
#> 14       cleanup.ucrt    2  0.008083748
```

### Shell/Make-like Matches

``` r
matches %>%
  get_proportion_hits(rule)
#>          rule    n          p
#> 1     rscript 2857 70.1965602
#> 2       chmod  524 12.8746929
#> 3 interpreter  251  6.1670762
#> 4     install  183  4.4963145
#> 5        curl  109  2.6781327
#> 6        wget   47  1.1547912
#> 7 credentials   46  1.1302211
#> 8    transfer   46  1.1302211
#> 9 persistence    7  0.1719902
matches %>%
  get_proportion_pkgs(rule)
#>          rule   n    n/24741
#> 1     rscript 725 2.93035851
#> 2 interpreter 236 0.95388222
#> 3       chmod 227 0.91750536
#> 4        curl  58 0.23442868
#> 5     install  52 0.21017744
#> 6    transfer  18 0.07275373
#> 7        wget  15 0.06062811
#> 8 credentials   6 0.02425124
#> 9 persistence   4 0.01616750
```

### R Patterns

``` r
patterns %>%
  get_proportion_hits(rule)
#>               rule     n          p
#> 1  deserialization 18233 28.6407691
#> 2           system  6095  9.5741506
#> 3             httr  5954  9.3526649
#> 4        namespace  5795  9.1029044
#> 5           source  5422  8.5169884
#> 6          install  5170  8.1211417
#> 7      credentials  4085  6.4168015
#> 8    download_file  3284  5.1585743
#> 9            httr2  2986  4.6904698
#> 10            curl  1257  1.9745213
#> 11     persistence   914  1.4357299
#> 12          python   838  1.3163475
#> 13    system_callr   788  1.2378065
#> 14        decoding   685  1.0760120
#> 15 system_processx   513  0.8058309
#> 16           rcurl   308  0.4838127
#> 17           chmod   305  0.4791002
#> 18         dynload   291  0.4571087
#> 19      system_sys   249  0.3911343
#> 20   options_repos   237  0.3722844
#> 21          socket   150  0.2356231
#> 22              fs    92  0.1445155
#> 23      eval_parse    10  0.0157082
patterns %>%
  get_proportion_pkgs(rule)
#>               rule    n     n/24741
#> 1  deserialization 3002 12.13370519
#> 2          install 2175  8.79107554
#> 3           system 1438  5.81221454
#> 4    download_file 1291  5.21805909
#> 5           source 1084  4.38139121
#> 6        namespace 1001  4.04591569
#> 7             httr  988  3.99337133
#> 8      credentials  575  2.32407744
#> 9            httr2  487  1.96839255
#> 10            curl  329  1.32977648
#> 11        decoding  290  1.17214341
#> 12     persistence  228  0.92154723
#> 13         dynload  217  0.87708662
#> 14    system_callr  193  0.78008165
#> 15           chmod  144  0.58202983
#> 16          python  134  0.54161109
#> 17 system_processx  102  0.41227113
#> 18           rcurl   87  0.35164302
#> 19   options_repos   66  0.26676367
#> 20          socket   65  0.26272180
#> 21      system_sys   30  0.12125621
#> 22              fs   14  0.05658623
#> 23      eval_parse    5  0.02020937
```

## Tarballs

The following code runs `survey_structure()` and `survey_expansion()` on
every downloaded package, providing empirical support for the defaults
implemented in `validate_tarball()`.

``` r
structure <- survey_dir(SNAPSHOT_DIR, survey_structure)
write_rds(structure, "results/tarball_structure.rds")
expansion <- survey_dir(SNAPSHOT_DIR, survey_expansion)
write_rds(expansion, "results/tarball_expansion.rds")
```

``` r
saved_structure <- read_rds("results/tarball_structure.rds")
saved_expansion <- read_rds("results/tarball_expansion.rds")
```

The defaults `max_entries = 100000L` and `max_bytes = 2 * 1024^3` (2 GB)
provide considerable room above the empirical maxima.

``` r
# max_entries
quantile(saved_structure$n_entries,  c(.5, .9, .99, .999, 1))
#>      50%      90%      99%    99.9%     100% 
#>    50.00   160.00   519.00  1676.04 13624.00

# max_bytes
quantile(saved_structure$bytes_read, c(.5, .9, .99, .999, 1))
#>       50%       90%       99%     99.9%      100% 
#>    431616   3879424  11274445  34597376 217626624
```

The default `max_ratio = 256` likewise provides considerable room above
the empirical maximum.

``` r
# exclude capped and errored rows, if present, as ratios are lower bounds
ok <- subset(saved_expansion, !cap_hit & is.na(error))
round(nrow(ok) / nrow(saved_expansion) * 100, 4)
#> [1] 100

# max_ratio
quantile(ok$ratio, c(.5, .9, .99, .999, 1))
#>       50%       90%       99%     99.9%      100% 
#>  3.017969  6.643311 10.282761 19.571948 84.684243
```

We can confirm the absence of various threat indicators in CRAN packages
such that the presence of any one justifies failing closed.

``` r
sum(saved_structure$n_symlink > 0)
#> [1] 0
sum(saved_structure$n_hardlink > 0)
#> [1] 0
sum(saved_structure$n_other_type > 0)
#> [1] 0
sum(saved_structure$n_traversal > 0)
#> [1] 0
sum(saved_structure$n_absolute > 0)
#> [1] 0
table(saved_structure$n_toplevel)
#> 
#>     1 
#> 24741
sum(saved_structure$n_backslash > 0)
#> [1] 0
sum(saved_structure$n_control > 0)
#> [1] 0
sum(saved_structure$n_empty > 0)
#> [1] 0
sum(saved_structure$n_bad_size > 0)
#> [1] 0
```

The scans did not raise errors.

``` r
subset(saved_structure, truncated | !is.na(error))
#>  [1] file            compressed_size n_entries       bytes_read     
#>  [5] max_entry_size  n_bad_size      max_path_nchar  max_path_depth 
#>  [9] n_symlink       n_hardlink      n_other_type    n_nul_typeflag 
#> [13] n_traversal     n_absolute      n_backslash     n_control      
#> [17] n_empty         n_toplevel      truncated       cap_hit        
#> [21] error          
#> <0 rows> (or 0-length row.names)
subset(saved_expansion, cap_hit | !is.na(error))
#> [1] file              compressed_size   uncompressed_size ratio            
#> [5] cap_hit           error            
#> <0 rows> (or 0-length row.names)
```
