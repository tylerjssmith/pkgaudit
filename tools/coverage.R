#!/usr/bin/env Rscript
cov <- covr::package_coverage(quiet = FALSE)
pct <- covr::percent_coverage(cov)
cat(sprintf("Coverage: %.2f%%\n", pct))

color <- if (pct >= 90) "#4c1"    else
         if (pct >= 80) "#97ca00" else
         if (pct >= 60) "#dfb317" else
         if (pct >= 40) "#fe7d37" else "#e05d44"

label <- "coverage"
value <- sprintf("%.0f%%", pct)
lw <- 7 * nchar(label) + 10
vw <- 7 * nchar(value) + 10
w  <- lw + vw

svg <- paste0(
  '<svg xmlns="http://www.w3.org/2000/svg" width="', w, '" height="20" ',
  'role="img" aria-label="', label, ': ', value, '">',
  '<title>', label, ': ', value, '</title>',
  '<linearGradient id="s" x2="0" y2="100%">',
  '<stop offset="0" stop-color="#bbb" stop-opacity=".1"/>',
  '<stop offset="1" stop-opacity=".1"/></linearGradient>',
  '<clipPath id="r"><rect width="', w, 
  '" height="20" rx="3" fill="#fff"/></clipPath>',
  '<g clip-path="url(#r)">',
  '<rect width="', lw, '" height="20" fill="#555"/>',
  '<rect x="', lw, '" width="', vw, '" height="20" fill="', color, '"/>',
  '<rect width="', w, '" height="20" fill="url(#s)"/></g>',
  '<g fill="#fff" text-anchor="middle" ',
  'font-family="Verdana,DejaVu Sans,Geneva,sans-serif" font-size="11">',
  '<text x="', lw / 2, '" y="15" fill="#010101" fill-opacity=".3">', label, 
  '</text>', '<text x="', lw / 2, '" y="14">', label, '</text>',
  '<text x="', lw + vw / 2, '" y="15" fill="#010101" fill-opacity=".3">', 
  value, '</text>', '<text x="', lw + vw / 2, '" y="14">', value, '</text>',
  '</g></svg>'
)

dir.create("public", showWarnings = FALSE)
writeLines(svg, "public/coverage.svg")

# Fail the build if test coverage <80%
if (pct < 80) stop(sprintf("Coverage %.2f%% is below the 80%% threshold", pct))