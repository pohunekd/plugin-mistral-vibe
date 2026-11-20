#!/usr/bin/env bash
# mkprofile.sh <rig-root> <name> <vibe-home-dir> <extra-toml-lines...>
# Writes a host profile over `vibe` inside the rig root. No host paths:
# every path derives from the rig root on argv. Ports travel in the
# extra TOML lines (proxy env), never spliced into code here.
# Prints the profile path.
set -u
R="${1:?mkprofile.sh: rig root required}"
NAME="${2:?mkprofile.sh: profile name required}"
VHOME="${3:?mkprofile.sh: vibe home dir name required}"
shift 3
D="$R/xdg-config/pohunek/agents"
mkdir -p -m 700 "$R/xdg-config/pohunek"
mkdir -p "$D"
F="$D/$NAME.toml"
{
  printf 'base = "vibe"\n'
  printf 'package = "pohunek.runtime.vibe"\n'
  printf 'digest = "%s"\n' "${PROFILE_DIGEST:?mkprofile.sh: PROFILE_DIGEST required}"
  printf '\n[env]\n'
  printf 'VIBE_HOME = "%s"\n' "$R/$VHOME/.vibe"
  printf 'VIBE_ENABLE_TELEMETRY = "false"\n'
  printf 'VIBE_ENABLE_UPDATE_CHECKS = "false"\n'
  for line in "$@"; do printf '%s\n' "$line"; done
} > "$F"
chmod 600 "$F"
echo "$F"
