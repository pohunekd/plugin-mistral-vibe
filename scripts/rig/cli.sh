#!/usr/bin/env bash
# Rig CLI wrapper for the V5 E2E: runs the isolated CLI of a rig root.
# No host paths: the root comes from argv, never spliced into code. Fails
# closed (set -u, exit 2) when the root is missing. The environment is
# cleared; PATH is the rig `bin` plus the system directories only.
# Usage: cli.sh <rig-root> <args...>   (`cli-for.sh` takes RIG_ROOT instead)
set -u
R="${1:?cli.sh: rig root required: cli.sh <rig-root> <args...>}"
shift
[ -d "$R" ] || { echo "cli.sh: rig root not a directory: $R" >&2; exit 2; }
cd "$R/work" || exit 1
exec env -i HOME="$R/home" XDG_CONFIG_HOME="$R/xdg-config" XDG_CACHE_HOME="$R/xdg-cache" \
  XDG_DATA_HOME="$R/xdg-data" XDG_STATE_HOME="$R/xdg-state" XDG_RUNTIME_DIR="$R/xdg-runtime" \
  PATH="$R/bin:/usr/bin:/bin" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
  TERM=xterm-256color NO_COLOR=1 TMPDIR="$R/tmp" SHELL=/bin/sh POHUNEK_WORKER_LAUNCHER=subprocess \
  VIBE_HOME="$R/home/.vibe" VIBE_ENABLE_TELEMETRY=false VIBE_ENABLE_UPDATE_CHECKS=false \
  "$R/bin/pohunek" "$@"
