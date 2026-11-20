#!/usr/bin/env bash
# Full V5 E2E for the Vibe runtime package (plan-mistral-vibe.md V5 (a)-(g)).
# Runs outside the kit script because the kit kills scripts after 60s
# (`COMMAND_TIMEOUT` in crates/plugin-kit/src/isolated.rs); the 20 attach
# answers alone exceed that budget.
#
# Usage: REL=<3.1.3|3.1.2> scripts/e2e-v5.sh <rig-root> <cols> <rows>
# The rig root comes from `scripts/rig/up.sh`. The CLI is the in-tree
# `scripts/rig/cli-for.sh` (it pins HOME/VIBE_HOME/sockets under the rig
# root); the attach helper is the in-tree `scripts/answer1.py`.
# Every argument and `REL` is required; no silent defaults, no host paths.
# TMPDIR must point under the rig root (exported before calling); nothing
# is written to /tmp. Every session id is recorded in the parent shell when
# `session new` returns; an EXIT trap (also run on INT and TERM) stops and
# removes every recorded session that is still live.
# Every check output is capped (head -c) so logs stay bounded.
#
# (a) first prompt via `session new --input` (paste path, prompt_arg=false),
#     idle observed via the program-status record plus probe fields, the
#     runtime version equals REL.
# (b) approval dialog: blocked/permission/screen, refusal, answer, idle.
# (c) 20 ask-user rounds; every round asserts the input rc, blocked/
#     question/screen, the stub's tool-result ASK count rising by exactly
#     one, the answer rc and the cleared state.
# (d) trust dialogs: shown dialog plus the live `working` arbitration.
# (e) `-p x` stays text: transcript shows it, the stub logged it as text,
#     and no process of the recorded tree carries it in /proc cmdline.
# (f) recorded PIDs (session inspect pid tree) leave nothing behind after
#     `session stop`, and nothing after SIGKILL of the PTY root;
#     placement outcome is clean; HOME and VIBE_HOME of the root PID and
#     its cwd stay under the rig root while the sessions live.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
R="${1:?e2e-v5: rig root required}"
COLS="${2:?e2e-v5: cols required}"
ROWS="${3:?e2e-v5: rows required}"
REL="${REL:?e2e-v5: REL required (3.1.3|3.1.2)}"
[ -d "$R" ] || { echo "e2e-v5: rig root not a directory: $R" >&2; exit 2; }
R="$(cd "$R" && pwd)"
C="$HERE/rig/cli-for.sh"
ANSWER="$HERE/answer1.py"
[ -x "$C" ] || { echo "e2e-v5: CLI wrapper not executable: $C" >&2; exit 2; }
[ -f "$ANSWER" ] || { echo "e2e-v5: answer helper missing: $ANSWER" >&2; exit 2; }
case "$TMPDIR" in "$R"/*) ;; *) echo "e2e-v5: TMPDIR must point under the rig root (got ${TMPDIR:-unset})" >&2; exit 2;; esac
export RIG_ROOT="$R" REL
LOG="${E2E_LOG:-$R/logs/e2e-v5.log}"
mkdir -p "$(dirname "$LOG")" "$R/work" "$R/logs"
rm -f "$LOG"
fails=0
SIDS=""
STOPLOG="$R/logs/v5-stop-rm.txt"
: >"$STOPLOG"
note() { echo "$*" | tee -a "$LOG"; }
cap() { head -c 300; }
stop_rm() { # <sid>: stop and remove, failures are logged
  "$C" session stop "$1" >>"$STOPLOG" 2>&1 || note "WARN stop $1 failed (see $STOPLOG)"
  "$C" session rm "$1" >>"$STOPLOG" 2>&1 || note "WARN rm $1 failed (see $STOPLOG)"
  SIDS="$(printf '%s' "$SIDS" | tr ' ' '\n' | grep -vx "$1" | tr '\n' ' ')"
}
cleanup() { for s in $SIDS; do stop_rm "$s"; done; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
check() { # <name> <got> <want-substring>
  if printf '%s' "$2" | grep -qF -- "$3"; then note "ok $1 ($2)"; else note "FAIL $1 got=[$(printf '%s' "$2" | cap)] want=[$3]"; fails=$((fails + 1)); fi
}
check_eq() { # <name> <got> <want-exact>
  if [ "$2" = "$3" ]; then note "ok $1 ($2)"; else note "FAIL $1 got=[$(printf '%s' "$2" | cap)] want=[$3]"; fails=$((fails + 1)); fi
}
check_ge1() { # <name> <count>
  if [ "${2:-0}" -ge 1 ] 2>/dev/null; then note "ok $1 ($2)"; else note "FAIL $1 count=[$2] want>=1"; fails=$((fails + 1)); fi
}
det() { "$C" session list --json 2>/dev/null | SID="$1" python3 -I -c 'import json,os,sys; s=next(x for x in json.load(sys.stdin)["ok"] if x["id"]==os.environ["SID"]); print(str(s.get("activity",""))+"/"+str(s.get("blocked_kind",""))+"/"+str(s.get("state_source","")))'; }
rec() { "$C" session detection "$1" --json 2>/dev/null | python3 -I -c 'import json,sys; s=json.load(sys.stdin)["ok"]["status"]; print(str(s.get("record_present"))+"/"+str(s.get("record_state")))'; }
scr() { "$C" session screen "$1" --json 2>/dev/null | python3 -I -c 'import json,sys; print("\n".join(json.load(sys.stdin)["ok"]["visible_lines"]))'; }
insp() { "$C" session inspect "$1" --json 2>/dev/null | python3 -I -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["ok"]))'; }
jget() { python3 -I -c 'import json,sys; d=json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d = d.get(k, "") if isinstance(d, dict) else ""
print(d)' "$1"; }
wait_idle() { # <sid> <timeout>: idle composer observed (record idle fresh, done after a prompt)
  local end=$((SECONDS + $2))
  while [ $SECONDS -lt $end ]; do
    case "$(rec "$1")" in True/idle|True/done) return 0;; esac
    sleep 2
  done
  return 1
}
wait_screen() { # <sid> <needle> <timeout>
  local end=$((SECONDS + $3))
  while [ $SECONDS -lt $end ]; do
    scr "$1" | grep -qiF -- "$2" && return 0
    sleep 2
  done
  return 1
}
wait_det() { # <sid> <want-substring> <timeout>: prints the last reading
  local end=$((SECONDS + $3)) d=""
  while [ $SECONDS -lt $end ]; do
    d="$(det "$1")"
    case "$d" in *"$2"*) printf '%s' "$d"; return 0;; esac
    sleep 1
  done
  printf '%s' "$d"
  return 1
}
wait_cleared() { # <sid> <timeout>: prints the last reading; ok only for a non-empty idle/ or working/ reading
  local end=$((SECONDS + $2)) d=""
  while [ $SECONDS -lt $end ]; do
    d="$(det "$1")"
    case "$d" in idle/*|working/*) printf '%s' "$d"; return 0;; esac
    sleep 1
  done
  printf '%s' "$d"
  return 1
}
stub_asks() { grep -c 'last_role=tool marker=ASK ' "$R/logs/stub.log" 2>/dev/null || true; }
alive() { # <pid>: running process (a zombie awaiting its parent's wait counts as gone)
  local st
  st="$(cut -d' ' -f3 "/proc/$1/stat" 2>/dev/null)" || return 1
  [ -n "$st" ] && [ "$st" != Z ]
}
wait_gone() { # <pids> <timeout>: prints the pids still alive after the timeout
  local end=$((SECONDS + $2)) left p
  while :; do
    left=""
    for p in $1; do alive "$p" && left="$left $p"; done
    if [ -z "$left" ] || [ $SECONDS -ge $end ]; then break; fi
    sleep 1
  done
  printf '%s' "$left"
}
NEW_SID=""
new_session() { # <name> <cwd> [extra...]; sets NEW_SID in the calling shell and records it for the trap
  local name="$1" cwd="$2"; shift 2
  mkdir -p "$cwd"
  NEW_SID=""
  local sid
  "$C" session new --agent vibe-rig --cwd "$cwd" --cols "$COLS" --rows "$ROWS" --json "$@" >"$R/logs/v5-$name-out.txt" 2>"$R/logs/v5-$name-err.txt"
  sid="$(python3 -I -B -c 'import json,sys; print(json.load(open(sys.argv[1]))["ok"]["id"])' "$R/logs/v5-$name-out.txt" 2>/dev/null)"
  [ -n "$sid" ] || { echo "FAIL $name-new out=[$(cap < "$R/logs/v5-$name-out.txt")] err=[$(cap < "$R/logs/v5-$name-err.txt")]" >>"$LOG"; echo "FAIL $name-new (see log)" >&2; fails=$((fails + 1)); return 1; }
  SIDS="$SIDS $sid"
  NEW_SID="$sid"
  echo "$name sid=$sid" >>"$LOG"
  echo "$name sid=$sid" >&2
}
procs_under() { # <root-pid>: pids of the recorded tree (root + descendants)
  python3 -I -c '
import subprocess,sys
root=sys.argv[1]
rows={}
for l in subprocess.run(["ps","-eo","pid=,ppid=,args="],capture_output=True,text=True).stdout.splitlines():
    p=l.split(None,2)
    if len(p)>=2: rows[p[0]]=(p[1],p[2] if len(p)>2 else "")
keep={root}; ch=True
while ch:
    ch=False
    for pid,(ppid,a) in rows.items():
        if ppid in keep and pid not in keep: keep.add(pid); ch=True
print(" ".join(sorted(keep,key=int)))' "$1"
}
root_pid() { insp "$1" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d.get("pid") or d.get("session_pid") or "")'; }

note "== (a) first prompt via session new, idle observed"
new_session a "$R/work/e2e-plugin" --input '[[PLAIN]] hi' || exit 1
SID_A="$NEW_SID"
wait_idle "$SID_A" 150 || { note "FAIL a-idle no idle composer"; fails=$((fails + 1)); }
D_A="$(det "$SID_A") / rec=$(rec "$SID_A")"; note "during idle: $D_A"
check "a-record" "$D_A" "True/done"
check "a-probe" "$("$C" session detection "$SID_A" --json 2>/dev/null | jget ok.status.probe_answered)" "True"
check_eq "a-version" "$("$C" session detection "$SID_A" --json 2>/dev/null | jget ok.status.gate.runtime_version)" "$REL"
check_ge1 "a-screen" "$(scr "$SID_A" | grep -ci 'accept edits')"
stop_rm "$SID_A"

note "== (b) approval dialog, per-round blocked"
new_session b "$R/work/e2e-plugin" --input '[[BASH]] go' || exit 1
SID_B="$NEW_SID"
# No idle wait here: the BASH input drives straight into the approval
# dialog. Idle-after is asserted after the answer clears the dialog.
wait_screen "$SID_B" "Permission for the" 150 || { note "FAIL b-shown"; fails=$((fails + 1)); }
D_B="$(wait_det "$SID_B" "blocked/permission/screen" 30)"; note "during dialog: $D_B"
check "b-blocked" "$D_B" "blocked/permission/screen"
if printf 'x\n' | "$C" session input "$SID_B" --stdin >"$R/logs/v5b-refuse.txt" 2>&1; then
  note "FAIL b-refusal accepted"; fails=$((fails + 1))
elif grep -qi session_input_blocked "$R/logs/v5b-refuse.txt"; then
  note "ok b-refusal"
else
  note "FAIL b-refusal $(cap < "$R/logs/v5b-refuse.txt")"; fails=$((fails + 1))
fi
if ! python3 -I "$ANSWER" "$SID_B" "$C" "$COLS" "$ROWS" 2>"$R/logs/v5b-answer-err.txt"; then note "FAIL b-answer $(cap < "$R/logs/v5b-answer-err.txt")"; fails=$((fails + 1)); fi
if wait_screen "$SID_B" "ran touch approved" 180; then note "ok b-clears"; else note "FAIL b-clears"; fails=$((fails + 1)); fi
if wait_idle "$SID_B" 150; then note "ok b-idle-after ($(rec "$SID_B"))"; else note "FAIL b-idle-after ($(rec "$SID_B"))"; fails=$((fails + 1)); fi
stop_rm "$SID_B"

note "== (c) 20 ask-user answers, every round asserted"
new_session c "$R/work/e2e-plugin" || exit 1
SID_C="$NEW_SID"
wait_idle "$SID_C" 150 || { note "FAIL c-idle"; fails=$((fails + 1)); }
ANS_OK=0
for i in $(seq 1 20); do
  before="$(stub_asks)"
  printf '[[ASK]] go\n' | "$C" session input "$SID_C" --stdin >"$R/logs/v5c-input-$i.txt" 2>&1
  in_rc=$?
  check_eq "c-input-rc-$i" "$in_rc" "0"
  [ "$in_rc" = 0 ] || break
  wait_screen "$SID_C" "user input" 90 || { note "FAIL c-shown-$i"; fails=$((fails + 1)); break; }
  D_C="$(wait_det "$SID_C" "blocked/question/screen" 30)"
  check "c-blocked-$i" "$D_C" "blocked/question/screen"
  case "$D_C" in *"blocked/question/screen"*) ;; *) break;; esac
  if ! python3 -I "$ANSWER" "$SID_C" "$C" "$COLS" "$ROWS" 2>>"$R/logs/v5c-answer-err.txt"; then note "FAIL c-answer-$i $(tail -c 200 "$R/logs/v5c-answer-err.txt")"; fails=$((fails + 1)); break; fi
  end=$((SECONDS + 120)); after="$(stub_asks)"
  while [ "$after" -le "$before" ] && [ $SECONDS -lt $end ]; do sleep 2; after="$(stub_asks)"; done
  check_eq "c-stub-asks-$i" "$after" "$((before + 1))"
  [ "$after" = "$((before + 1))" ] || break
  D_AFTER="$(wait_cleared "$SID_C" 60)" || { note "FAIL c-clears-$i no idle/ or working/ reading, last=[$D_AFTER]"; fails=$((fails + 1)); break; }
  note "ok c-clears-$i ($D_AFTER)"
  ANS_OK=$i
done
check_eq "c-20-answers" "$ANS_OK" "20"
stop_rm "$SID_C"

note "== (d) trust dialogs (live arbitration: shown + working)"
for label in folder repo; do
  dpath="$R/work/e2e-trust-$label"
  rm -rf "$dpath"; mkdir -p "$dpath"; printf '# untrusted fixture\n' >"$dpath/AGENTS.md"
  if [ "$label" = repo ]; then
    {
      git init -q "$dpath" && git -C "$dpath" add -A \
        && git -C "$dpath" -c user.name=n -c user.email=n@e.test commit -qm init
    } >"$R/logs/v5-d-git.txt" 2>&1 || { note "FAIL d-repo-git $(cap < "$R/logs/v5-d-git.txt")"; fails=$((fails + 1)); }
    mkdir -p "$dpath/sub"; dpath="$dpath/sub"
  fi
  new_session "d-$label" "$dpath" || continue
  SID_D="$NEW_SID"
  wait_screen "$SID_D" "Malicious" 90 || { note "FAIL d-$label-shown"; fails=$((fails + 1)); }
  D_D=$(det "$SID_D"); note "d-$label: $D_D rec=$(rec "$SID_D")"
  # Live arbitration (no core change): the trust dialog is visible on
  # screen, but the daemon still reports working with no program-status
  # record (core gap #2447; corpus blocked expects come from detect-check
  # replay). Assert the shown dialog plus the working live state.
  SCR_D="$(scr "$SID_D" | tr '[:upper:]' '[:lower:]')"
  check_ge1 "d-$label-malicious" "$(printf '%s\n' "$SCR_D" | grep -c 'malicious')"
  if [ "$label" = repo ]; then
    check_ge1 "d-repo-git" "$(printf '%s\n' "$SCR_D" | grep -c 'git')"
    check_ge1 "d-repo-reposit" "$(printf '%s\n' "$SCR_D" | grep -c 'reposit')"
  fi
  check "d-$label-live" "$D_D" "working"
  stop_rm "$SID_D"
done

note "== (e) -p x stays text (transcript + stub log + recorded-tree cmdline)"
new_session e "$R/work/e2e-plugin" "--input=-p x" || exit 1
SID_E="$NEW_SID"
wait_screen "$SID_E" "-p x" 60 || { note "FAIL e-shown"; fails=$((fails + 1)); }
check_ge1 "e-transcript" "$(scr "$SID_E" | grep -cF -- '> -p x')"
# The prompt shows on screen before the turn is submitted: wait for the
# stub to log the request that carries it as plain text.
end=$((SECONDS + 60))
while [ $SECONDS -lt $end ] && ! grep -qF "text='-p x'" "$R/logs/stub.log" 2>/dev/null; do sleep 1; done
check "e-stub-log" "$(grep -hF "text='-p x'" "$R/logs/stub.log" 2>/dev/null | tail -n 1)" "text='-p x'"
ROOT_E="$(root_pid "$SID_E")"
if [ -z "$ROOT_E" ]; then
  note "FAIL e-pid no pid in inspect"; fails=$((fails + 1))
else
  TREE_E="$(procs_under "$ROOT_E")"
  note "e-tree: $TREE_E"
  E_SEEN=0; E_CLI=0
  for p in $TREE_E; do
    cmd="$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)"
    [ -n "$cmd" ] || continue
    case "$cmd" in *vibe*) E_SEEN=$((E_SEEN + 1));; esac
    case "$cmd" in *"-p x"*) E_CLI="$p";; esac
  done
  check_ge1 "e-vibe-procs-inspected" "$E_SEEN"
  if [ "$E_CLI" = 0 ]; then note "ok e-cmdline (no recorded-tree process carries -p x)"; else note "FAIL e-cmdline pid=$E_CLI carries -p x"; fails=$((fails + 1)); fi
fi
stop_rm "$SID_E"

note "== (f) recorded PIDs, placement, environ/cwd (sessions live)"
new_session f "$R/work/e2e-plugin" || exit 1
SID_F="$NEW_SID"
wait_idle "$SID_F" 150 || { note "FAIL f-idle"; fails=$((fails + 1)); }
ROOT_F="$(root_pid "$SID_F")"
[ -n "$ROOT_F" ] || { note "FAIL f-pid no pid in inspect"; fails=$((fails + 1)); ROOT_F=0; }
TREE_F="$(procs_under "$ROOT_F")"
note "f-tree: $TREE_F"
check_eq "f-placement" "$(insp "$SID_F" | jget placement.outcome)" "clean"
for var in HOME VIBE_HOME; do
  val="$(tr '\0' '\n' < "/proc/$ROOT_F/environ" 2>/dev/null | grep "^$var=" | head -n 1 | cut -d= -f2-)"
  case "$val" in "$R"/*) note "ok f-environ-$var ($val)";; *) note "FAIL f-environ-$var got=[$val] want under $R"; fails=$((fails + 1));; esac
done
CWD_F="$(readlink "/proc/$ROOT_F/cwd" 2>/dev/null || true)"
case "$CWD_F" in "$R"/*) note "ok f-cwd-under-root ($CWD_F)";; *) note "FAIL f-cwd got=[$CWD_F]"; fails=$((fails + 1));; esac
LIST_F="$("$C" session list --json 2>/dev/null | RIG_ROOT="$R" python3 -I -c 'import json,os,sys
rows=json.load(sys.stdin)["ok"]
bad=[x.get("cwd","?") for x in rows if not x.get("cwd","").startswith(os.environ["RIG_ROOT"]+"/")]
print(len(rows)); print(" ".join(bad))')"
LIVE_N="$(printf '%s\n' "$LIST_F" | sed -n 1p)"
LIVE_BAD="$(printf '%s\n' "$LIST_F" | sed -n 2p)"
check_ge1 "g-live-sessions" "$LIVE_N"
check_eq "g-cwd-under-root-live" "$LIVE_BAD" ""
"$C" session stop "$SID_F" >>"$STOPLOG" 2>&1 || note "WARN stop $SID_F failed"
sleep 3
LEFT_F="$(wait_gone "$TREE_F" 20)"
if [ -z "$LEFT_F" ]; then note "ok f-after-stop"; else note "FAIL f-after-stop survivors:$LEFT_F"; fails=$((fails + 1)); fi
stop_rm "$SID_F"

note "== (f2) SIGKILL of the recorded PTY root"
new_session g "$R/work/e2e-plugin" || exit 1
SID_G="$NEW_SID"
wait_idle "$SID_G" 150 || { note "FAIL g-idle"; fails=$((fails + 1)); }
ROOT_G="$(root_pid "$SID_G")"
if [ -z "$ROOT_G" ]; then
  note "FAIL g-pid no pid in inspect"; fails=$((fails + 1))
else
  TREE_G="$(procs_under "$ROOT_G")"
  note "g-tree: $TREE_G"
  if tr '\0' ' ' < "/proc/$ROOT_G/cmdline" 2>/dev/null | grep -q "venv-$REL\|$R/bin"; then kill -KILL "$ROOT_G"; note "ok g-sigkill $ROOT_G"; else note "FAIL g-cmdline (not the rig binary)"; fails=$((fails + 1)); fi
  LEFT_G="$(wait_gone "$TREE_G" 20)"
  if [ -z "$LEFT_G" ]; then note "ok g-after-sigkill"; else note "FAIL g-after-sigkill survivors:$LEFT_G"; fails=$((fails + 1)); fi
fi
stop_rm "$SID_G"

note "== (g) operator paths"
if [ -d "$R/home/.vibe" ]; then note "ok g-rig-home"; else note "FAIL g-rig-home missing $R/home/.vibe"; fails=$((fails + 1)); fi
if grep -q 'HOME="\$R/home"' "$HERE/rig/cli.sh" && grep -q 'VIBE_HOME="\$R/home/.vibe"' "$HERE/rig/cli.sh"; then note "ok g-cli-pins-home"; else note "FAIL g-cli-pins-home $HERE/rig/cli.sh"; fails=$((fails + 1)); fi

echo "fails=$fails" | tee -a "$LOG"
exit $((fails > 0))
