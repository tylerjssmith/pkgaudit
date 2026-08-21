#!/bin/sh
# Instrumented probe site: exec/. Installed and marked executable, but nothing
# in the lifecycle invokes it.
if [ -n "${FOO_LOG:-}" ]; then
  printf '%s\t%s\t%s\n' "$(date '+%H:%M:%S')" "exec_sh" "$$" >> "$FOO_LOG"
fi
