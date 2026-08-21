#!/usr/bin/env bash
#
# Run one probe command against the instrumented package in foo/ and record
# which of its execution sites fired.
#
# The package appends a marker line to $FOO_LOG whenever an instrumented site
# runs. This script points FOO_LOG at the log named by -o, runs the command
# given by -e, and brackets the markers with a header and footer recording what
# was run and how it exited. Comparing logs across commands is what establishes
# which phase reaches which site.
#
# Usage:
#   ./run_foo.sh -e <command> -o <logfile>
#
#   -e   Shell command to run, as one string. Run from build/, where foo/ is a
#        symlink to the package, so a command can say foo/ and mean the real
#        one while every artifact R writes to the working directory -- the
#        source tarball, the binary, the .Rcheck tree -- is left in build/.
#   -o   Log file to create, relative to this directory. Parent directories are
#        created as needed. Truncated if it already exists.
#
# Examples:
#   ./run_foo.sh -e "R CMD INSTALL foo/"                  -o logs/install_src.log
#   ./run_foo.sh -e "R CMD build foo/"                    -o logs/build.log
#   ./run_foo.sh -e "Rscript -e 'loadNamespace(\"foo\")'" -o logs/load.log
#   ./run_foo.sh -e "Rscript -e 'library(foo)'"           -o logs/attach.log
#
# Packages are installed into ./lib rather than the real user library, so
# repeated probe runs leave no trace outside this directory. Add an explicit
# -l to the command if you want somewhere else.

set -euo pipefail

usage() {
  sed -n '3,27p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'
  exit "${1:-2}"
}

COMMAND=""
LOGNAME=""

while getopts ":e:o:h" opt; do
  case "$opt" in
    e) COMMAND="$OPTARG" ;;
    o) LOGNAME="$OPTARG" ;;
    h) usage 0 ;;
    :) echo "run_foo.sh: -$OPTARG requires an argument" >&2; exit 2 ;;
    \?) echo "run_foo.sh: unknown option -$OPTARG" >&2; exit 2 ;;
  esac
done

[ -n "$COMMAND" ] || { echo "run_foo.sh: -e is required" >&2; usage; }
[ -n "$LOGNAME" ] || { echo "run_foo.sh: -o is required" >&2; usage; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Absolute paths, because R CMD INSTALL and R CMD build run parts of their work
# in other directories and relative ones would follow them there.
LOG="$HERE/$LOGNAME"
LIB="$HERE/lib"
BUILD="$HERE/build"

# lib/ is not tracked. When it is absent -- a fresh clone -- it is rebuilt from
# lib.lock so the matrix can run; see make_lib.R for what a rebuild pins.
[ -d "$LIB" ] || Rscript "$HERE/make_lib.R"

mkdir -p "$LIB" "$BUILD" "$(dirname "$LOG")"

# R CMD build and R CMD INSTALL --build write their output to the working
# directory and offer no flag to redirect it, and R CMD check writes its .Rcheck
# tree there too. Running from build/ is what puts all three there. The package
# is reached through a relative symlink so the command's own text needs no
# change, and so the tree stays movable.
ln -sfn ../foo "$BUILD/foo"
cd "$BUILD"

export FOO_LOG="$LOG"
export R_LIBS_USER="$LIB"

# TinyTeX installs its binaries here but does not always register them on PATH,
# and R CMD build needs texi2pdf to finish a Sweave vignette. Prepended when
# present, ignored when not. Remove this once `tlmgr path add` has created the
# usual symlinks -- it is a convenience, not part of what the probe measures.
for d in "$HOME/Library/TinyTeX/bin"/*; do
  if [ -d "$d" ]; then
    PATH="$d:$PATH"
    export PATH
  fi
done

: > "$LOG"
{
  echo "# command:  $COMMAND"
  echo "# started:  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "# workdir:  $BUILD"
  echo "# library:  $LIB"
  echo "# log:      $LOG"
  # Recorded because it decides whether a vignette can finish: without it the
  # code still runs and the markers still land, but the command exits non-zero.
  # pdflatex rather than texi2pdf -- R drives the former through
  # tools::texi2pdf(), and TinyTeX ships no texi2pdf binary at all.
  echo "# pdflatex: $(command -v pdflatex || echo none)"
} >> "$LOG"

set +e
eval "$COMMAND"
STATUS=$?
set -e

{
  echo "# exit:     $STATUS"
  echo "# finished: $(date '+%Y-%m-%d %H:%M:%S')"
} >> "$LOG"

# Sites fired, in first-seen order, for reading at a glance. The log itself
# keeps every firing with its time and pid.
#
# grep's own exit status is swallowed: a command that fires no sites is a
# result, not a failure, and under pipefail it would otherwise abort the script
# before it could report the command's real exit status.
SITES="$({ grep -v '^#' "$LOG" || true; } | cut -f2 | awk '!seen[$0]++' | paste -sd' ' -)"

echo
echo "run_foo.sh: exit $STATUS, log $LOGNAME"
echo "run_foo.sh: sites fired: ${SITES:-<none>}"

exit "$STATUS"
