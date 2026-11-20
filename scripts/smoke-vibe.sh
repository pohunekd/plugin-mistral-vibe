#!/usr/bin/env bash
# Vibe runtime smoke script (V3 + V5-core): runs inside the kit's live
# isolated root after the generic smoke checks pass. The kit kills the
# script after 60s (`COMMAND_TIMEOUT` in crates/plugin-kit/src/isolated.rs),
# so this script holds only the fast checks: V3 range equality, the version
# probe, a poll to activity=blocked on the welcome frame, an unconditional
# refusal round trip while blocked (no detach step). The full V5 (a)-(g)
# with 20 attach answers is `scripts/e2e-v5.sh` on a rig root.
# Temp files via mktemp under TMPDIR when the kit provides one; the kit
# clears the environment, so otherwise the scratch dir is
# `<repository root>/.tmp-smoke-vibe` (gitignored) and the trap removes it.
set -euo pipefail

if [ -z "${POHUNEK_SMOKE_SESSION:-}" ]; then
  echo "smoke-vibe.sh: POHUNEK_SMOKE_SESSION is unset" >&2
  exit 1
fi
session="$POHUNEK_SMOKE_SESSION"

here="$(cd "$(dirname "$0")/.." && pwd)"
# The kit runs the script with a cleared environment (no TMPDIR); fall back
# to a gitignored scratch dir under the repository root and remove it.
tmpdir="${TMPDIR:-$here/.tmp-smoke-vibe}"
mkdir -p "$tmpdir"
out="$(mktemp "$tmpdir/smoke-vibe-out.XXXXXX")"
trap 'rm -f "$out"; [ -n "${TMPDIR:-}" ] || rm -rf "$tmpdir"' EXIT

fail() { echo "smoke-vibe: FAIL $1" >&2; [ -n "${2:-}" ] && printf '%s\n' "$2" >&2; exit 1; }
ok() { echo "smoke-vibe: ok $1"; }

# V3: the descriptor's [min, below) range equals the lock's supported block.
min="$(sed -n 's/^min = "\(.*\)"/\1/p' "$here/package/runtime.toml")"
below="$(sed -n 's/^below = "\(.*\)"/\1/p' "$here/package/runtime.toml")"
lock_min="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["supported"]["min"])' "$here/compat/compatibility-lock.json")"
lock_below="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["supported"]["below"])' "$here/compat/compatibility-lock.json")"
[ "$min" = "$lock_min" ] || fail "lock-range" "min $min != lock $lock_min"
[ "$below" = "$lock_below" ] || fail "lock-range" "below $below != lock $lock_below"
ok "lock-range ($min / $below)"

# V3 version probe: the installed upstream answers with the locked release.
locked="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["upstream"]["release"])' "$here/compat/compatibility-lock.json")"
probed="$(vibe --version)"
[ "$probed" = "vibe $locked" ] || fail "version-probe" "got '$probed', want 'vibe $locked'"
ok "version-probe ($probed)"

activity_of() { # <session>
  pohunek session list --json >"$out" 2>&1 || fail "list" "$(cat "$out")"
  SID="$1" python3 -c 'import json,os,sys; print(next(s["activity"] for s in json.load(open(sys.argv[1]))["ok"] if s["id"] == os.environ["SID"]))' "$out"
}
screen_of() { # <session>
  pohunek session screen "$1" --json >"$out" 2>&1 || fail "screen" "$(cat "$out")"
  python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["ok"]["visible_lines"]))' "$out"
}

# V5-core: the fresh smoke session starts on the plugin's welcome frame and
# reads blocked there; poll until the screen evidence confirms, inside the
# 60 s script budget.
activity=""
screen=""
end=$((SECONDS + 50))
while [ $SECONDS -lt $end ]; do
  activity="$(activity_of "$session")"
  screen="$(screen_of "$session")"
  if [ "$activity" = blocked ] && printf '%s' "$screen" | grep -q "Welcome to Mistral"; then break; fi
  sleep 2
done
[ "$activity" = blocked ] || fail "welcome-blocked" "activity=$activity (want blocked)"
printf '%s' "$screen" | grep -q "Welcome to Mistral" || fail "welcome-frame" "welcome title not on screen"
ok "welcome-blocked"

# The refusal branch always runs: while blocked, session input is refused.
if printf 'x\n' | pohunek session input "$session" --stdin >"$out" 2>&1; then fail "refusal" "session input accepted while blocked"; fi
grep -qi "session_input_blocked" "$out" || fail "refusal" "$(cat "$out")"
ok "refusal (session_input_blocked)"

ok "v5-core-done"
