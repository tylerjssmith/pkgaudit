#!/usr/bin/env bash
#
# Run every experiment in a CSV file through run_foo.sh and summarise which
# execution sites each command reached.
#
# The CSV needs a header row with columns named e and o, matching run_foo.sh's
# flags: e is the shell command, o is the log file to write. Any other columns
# are ignored, so a phase or notes column can be added freely.
#
# Rows run in file order, and that order matters: R CMD build has to run before
# anything that installs or checks the tarball it produces, and R CMD INSTALL
# --build has to run before the binary is installed. A failing row does not stop
# the run, so one broken command still leaves you the rest of the matrix.
#
# Usage:
#   ./drive_foo.sh [-v] <experiments.csv>
#
#   -v   Stream each command's own output. Off by default; the per-command log
#        holds what matters either way.
#
# Exits non-zero if any command did.

set -euo pipefail

usage() {
  sed -n '3,22p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'
  exit "${1:-2}"
}

VERBOSE=0
while getopts ":vh" opt; do
  case "$opt" in
    v) VERBOSE=1 ;;
    h) usage 0 ;;
    \?) echo "drive_foo.sh: unknown option -$OPTARG" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

CSV="${1:-}"
[ -n "$CSV" ] || { echo "drive_foo.sh: a CSV file is required" >&2; usage; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

[ -f "$CSV" ] || { echo "drive_foo.sh: no such file: $CSV" >&2; exit 2; }
[ -x ./run_foo.sh ] || { echo "drive_foo.sh: ./run_foo.sh is missing or not executable" >&2; exit 2; }

# Artifacts from an earlier run must not survive into this one. A command that
# fails before writing its tarball would otherwise leave the previous one in
# place, and every row downstream would test a stale package while reporting a
# clean exit. The symlink and the library are left alone; both are rebuilt or
# reused harmlessly.
rm -rf build/*.tar.gz build/*.tgz build/*.Rcheck

# Parsed with R rather than cut or awk because the commands contain commas and
# quotes, and read.csv already implements the quoting rules correctly. Emitted
# as alternating lines, which is safe here because a command with an embedded
# newline is rejected up front.
PAIRS="$(mktemp)"
trap 'rm -f "$PAIRS"' EXIT

Rscript -e '
  a <- commandArgs(trailingOnly = TRUE)
  d <- utils::read.csv(a[1], stringsAsFactors = FALSE)
  if (!all(c("e", "o") %in% names(d))) stop("CSV needs columns named e and o")
  if (nrow(d) == 0L) stop("CSV has no rows")
  if (any(grepl("\n", c(d$e, d$o), fixed = TRUE))) stop("embedded newline in CSV")
  for (i in seq_len(nrow(d))) cat(d$e[i], "\n", d$o[i], "\n", sep = "")
' "$CSV" > "$PAIRS"

printf '%-27s %-5s %s\n' "LOG" "EXIT" "SITES"

ROWS=0
FAILED=0
while IFS= read -r cmd && IFS= read -r out; do
  ROWS=$((ROWS + 1))

  set +e
  if [ "$VERBOSE" -eq 1 ]; then
    ./run_foo.sh -e "$cmd" -o "$out"
  else
    ./run_foo.sh -e "$cmd" -o "$out" >/dev/null 2>&1
  fi
  STATUS=$?
  set -e

  [ "$STATUS" -eq 0 ] || FAILED=$((FAILED + 1))

  SITES="$({ grep -v '^#' "$out" 2>/dev/null || true; } | cut -f2 | awk '!seen[$0]++' | paste -sd' ' -)"
  printf '%-27s %-5s %s\n' "$out" "$STATUS" "${SITES:-<none>}"
done < "$PAIRS"

echo
echo "drive_foo.sh: $ROWS experiments, $FAILED failed"

[ "$FAILED" -eq 0 ]
