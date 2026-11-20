#!/usr/bin/env bash
# Rig up: brings a V5 E2E rig root up (stub, proxy, daemon, harness
# config, plugin link/enable/select, vibe-rig profile).
# No host paths: everything derives from the rig root and the release
# on argv. Fails closed: root, release, sources and binaries required.
# Usage: up.sh <rig-root> <release> <plugin-dir> <core-bin-dir> <upstream-venv-bin>
# Ports: stub/proxy derive from the release (3.1.3 -> 18841/18842,
# 3.1.2 -> 18851/18852); proxy stays loopback-only, egress refused.
set -u
set -o pipefail
R="${1:?up.sh: rig root required: up.sh <rig-root> <release> <plugin-dir> <core-bin-dir> <upstream-venv-bin>}"
REL="${2:?up.sh: release required (3.1.3|3.1.2)}"
PLUGIN="${3:?up.sh: plugin dir required}"
COREDIR="${4:?up.sh: core bin dir required}"
UPSTREAM="${5:?up.sh: upstream venv bin dir required}"
for d in "$PLUGIN" "$COREDIR" "$UPSTREAM"; do
  [ -d "$d" ] || { echo "up.sh: not a directory: $d" >&2; exit 2; }
done
case "$REL" in
  3.1.3) STUB_PORT=18841; PROXY_PORT=18842 ;;
  3.1.2) STUB_PORT=18851; PROXY_PORT=18852 ;;
  *) echo "up.sh: unknown release $REL" >&2; exit 2 ;;
esac
HERE="$(cd "$(dirname "$0")" && pwd)"
for b in pohunek pohunekd pohunek-sessiond; do
  [ -x "$COREDIR/$b" ] || { echo "up.sh: missing binary $COREDIR/$b" >&2; exit 2; }
done
[ -x "$UPSTREAM/vibe" ] || { echo "up.sh: missing upstream $UPSTREAM/vibe" >&2; exit 2; }
[ -d "$PLUGIN/package" ] || { echo "up.sh: package dir missing: $PLUGIN/package" >&2; exit 2; }
# The profile pins the kit build digest of the plugin tree (printed by
# `pohunek-plugin-kit build` as sha256:...); no silent default.
[ -n "${PROFILE_DIGEST:-}" ] || { echo "up.sh: PROFILE_DIGEST required (kit build digest)" >&2; exit 2; }

mkdir -p "$R"/{bin,home/.vibe,xdg-config,xdg-cache,xdg-data,xdg-state,xdg-runtime,tmp,work,logs}
chmod 700 "$R/xdg-runtime"
for b in pohunek pohunekd pohunek-sessiond; do cp "$COREDIR/$b" "$R/bin/$b"; done
ln -sf "$UPSTREAM/vibe" "$R/bin/vibe"
UP_OK=0
# Any exit before the last line stops the processes started so far.
trap 'rc=$?; if [ "$UP_OK" != 1 ]; then echo "up.sh: failed (rc=$rc), stopping the rig" >&2; "$HERE/down.sh" "$R"; fi' EXIT
export RIG_STUB_PORT="$STUB_PORT" RIG_PROXY_PORT="$PROXY_PORT"
nohup setsid env -i PATH=/usr/bin:/bin python3 -I "$HERE/stub.py" --port "$STUB_PORT" --log "$R/logs/stub.log" > "$R/logs/stub.out" 2>&1 &
echo "stub $!" >> "$R/pids"
nohup setsid env -i PATH=/usr/bin:/bin python3 -I "$HERE/proxy.py" --port "$PROXY_PORT" --log "$R/logs/proxy.log" > "$R/logs/proxy.out" 2>&1 &
echo "proxy $!" >> "$R/pids"

# Harness Vibe config: stub provider on loopback, no telemetry/updates.
cat > "$R/home/.vibe/config.toml" <<EOF
active_model = "stub"
enable_telemetry = false
enable_update_checks = false

[[providers]]
name = "stub"
api_base = "http://127.0.0.1:$STUB_PORT/v1"
api_key_env_var = ""
api_style = "openai"

[[models]]
name = "stub-model"
provider = "stub"
alias = "stub"
max_context_length = 60000
EOF
chmod 700 "$R/home/.vibe"
touch "$R/home/.vibe/trusted_folders.toml"
chmod 600 "$R/home/.vibe/trusted_folders.toml"

RIG_ENV=(
  "HOME=$R/home" "XDG_CONFIG_HOME=$R/xdg-config" "XDG_CACHE_HOME=$R/xdg-cache"
  "XDG_DATA_HOME=$R/xdg-data" "XDG_STATE_HOME=$R/xdg-state" "XDG_RUNTIME_DIR=$R/xdg-runtime"
  "PATH=$R/bin:/usr/bin:/bin" "LANG=C.UTF-8" "LC_ALL=C.UTF-8"
  "TERM=xterm-256color" "NO_COLOR=1" "TMPDIR=$R/tmp" "SHELL=/bin/sh"
  "POHUNEK_WORKER_LAUNCHER=subprocess"
  "VIBE_HOME=$R/home/.vibe"
  "VIBE_ENABLE_TELEMETRY=false" "VIBE_ENABLE_UPDATE_CHECKS=false"
  "HTTPS_PROXY=http://127.0.0.1:$PROXY_PORT" "HTTP_PROXY=http://127.0.0.1:$PROXY_PORT"
  "ALL_PROXY=http://127.0.0.1:$PROXY_PORT" "NO_PROXY=127.0.0.1"
  "https_proxy=http://127.0.0.1:$PROXY_PORT" "http_proxy=http://127.0.0.1:$PROXY_PORT"
  "all_proxy=http://127.0.0.1:$PROXY_PORT" "no_proxy=127.0.0.1"
)
cd "$R/work" || exit 1
nohup setsid env -i "${RIG_ENV[@]}" "$R/bin/pohunekd" --local-only > "$R/logs/daemon.log" 2>&1 &
echo "daemon $!" >> "$R/pids"

CLI="$HERE/cli.sh"
DAEMON_UP=0
for i in $(seq 1 60); do "$CLI" "$R" plugin list >/dev/null 2>&1 && { DAEMON_UP=1; break; }; sleep 1; done
[ "$DAEMON_UP" = 1 ] || { echo "up.sh: daemon did not answer within 60 s" >&2; exit 1; }
if ! "$CLI" "$R" plugin list 2>/dev/null | grep -q "pohunek.runtime.vibe"; then
  # Link target is <plugin-dir>/package only (runtime.toml + detect.toml):
  # the daemon archives the link target, and the corpus beside package/
  # would exceed the 512-file package limit.
  "$CLI" "$R" plugin link "$PLUGIN/package" --yes || exit 1
  "$CLI" "$R" plugin enable pohunek.runtime.vibe || exit 1
  "$CLI" "$R" plugin select pohunek.runtime.vibe || exit 1
fi
PROFILE_DIGEST="$PROFILE_DIGEST" "$HERE/mkprofile.sh" "$R" vibe-rig home \
  "HTTPS_PROXY = \"http://127.0.0.1:$PROXY_PORT\"" \
  "HTTP_PROXY = \"http://127.0.0.1:$PROXY_PORT\"" \
  "ALL_PROXY = \"http://127.0.0.1:$PROXY_PORT\"" \
  "https_proxy = \"http://127.0.0.1:$PROXY_PORT\"" \
  "http_proxy = \"http://127.0.0.1:$PROXY_PORT\"" \
  "all_proxy = \"http://127.0.0.1:$PROXY_PORT\"" \
  "NO_PROXY = \"127.0.0.1\"" \
  "no_proxy = \"127.0.0.1\"" > /dev/null || exit 1
"$CLI" "$R" plugin profile migrate vibe-rig --yes | tail -n 1
[ "${PIPESTATUS[0]}" = 0 ] || { echo "up.sh: plugin profile migrate failed" >&2; exit 1; }
"$CLI" "$R" plugin profile list --all || exit 1
UP_OK=1
echo "up $REL done at $R"
