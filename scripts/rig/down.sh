#!/usr/bin/env bash
# Rig down: stops the processes a rig root recorded in <root>/pids.
# A recorded PID is signalled only when its /proc/<pid>/cmdline still has
# the exact identity up.sh started: the rig's `bin/pohunekd --local-only`,
# or `stub.py`/`proxy.py` with `--log <root>/logs/<name>.log`. A PID whose
# cmdline differs (reuse after a reboot) is reported and left alone.
# Exits non-zero when a PID of the rig is still alive after the wait.
# Usage: down.sh <rig-root>
set -u
set -o pipefail
R="${1:?down.sh: rig root required: down.sh <rig-root>}"
[ -d "$R" ] || { echo "down.sh: rig root not a directory: $R" >&2; exit 2; }
R="$(cd "$R" && pwd)"
PIDS="$R/pids"
[ -f "$PIDS" ] || { echo "down.sh: no pids file: $PIDS (nothing to stop)"; exit 0; }

is_rig() { # <name> <cmdline>
  case "$1" in
    daemon) case "$2" in "$R/bin/pohunekd --local-only"*) return 0;; esac ;;
    stub) case "$2" in *"/stub.py --port "*" --log $R/logs/stub.log"*) return 0;; esac ;;
    proxy) case "$2" in *"/proxy.py --port "*" --log $R/logs/proxy.log"*) return 0;; esac ;;
  esac
  return 1
}

ours=""
while read -r name pid; do
  [ -n "$pid" ] || continue
  if [ ! -d "/proc/$pid" ]; then echo "down.sh: $name $pid already gone"; continue; fi
  cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
  if is_rig "$name" "$cmd"; then
    if kill "$pid" 2>/dev/null; then echo "down.sh: stopped $name $pid"; else echo "down.sh: $name $pid already gone"; fi
    ours="$ours $name:$pid"
  else
    echo "down.sh: SKIP $name $pid (cmdline is not the rig's: $cmd)"
  fi
done < "$PIDS"

left=""
for i in $(seq 1 10); do
  left=""
  for entry in $ours; do
    [ -d "/proc/${entry#*:}" ] && left="$left $entry"
  done
  [ -z "$left" ] && break
  sleep 1
done
if [ -n "$left" ]; then
  echo "down.sh: SURVIVORS after 10 s:$left" >&2
  exit 1
fi
echo "down.sh: done"
