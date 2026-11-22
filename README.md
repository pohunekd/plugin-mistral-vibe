# plugin-mistral-vibe

Pohunek plugin for the Mistral Vibe upstream (detection-only, v0.1.0).

| | |
|---|---|
| Repository | `pohunekd/plugin-mistral-vibe` (created on admission) |
| Package id | `pohunek.runtime.vibe` |
| Runtime id (`--agent`) | `vibe` |
| Upstream | Mistral Vibe release pinned in `compat/RELEASE` |
| Status | **detection-only**: screen + program-status detection, no resume |

## Install

```bash
pohunek plugin install pohunek.runtime.vibe
```

The install is a two-step review: the command above runs a dry run and prints
what the package declares together with the resolved `<package-id>@<version>`;
repeat the printed command with `--yes` to install it from the official plugin
index. Vibe 0.1.0 is admitted in the official plugin index.

## Scope of v0.1.0

- Detection only: the descriptor sets `[resume] supported = false` and
  `[native_reference] strategy = "none"`. Resume stays unsupported until a
  hook integration exists (separate core issue); `detect-composer-absent-v1`
  is deliberately not used — the idle rule reads the composer frame, not
  the prompt-box fact.
- Linux x86_64 only; telemetry is left to the user's own Vibe `config.toml`
  (the plugin passes no telemetry variables).
- `prompt_arg = false`: the prompt travels as terminal input. Switching to
  `true` needs the core dash-paste handling (shipped as core feature
  `prompt-arg-dash-paste-v1`, merged in 67935b062, #2426); a V5(e) revert
  proof on the pre-fix core was retired, see the evidence file.
- `--trust`: the descriptor declares `trusted_checkout_args = ["--trust"]`.
  Core drops an equal run from profile args by design and adds the flag only
  for GitHub origins; the positive path (a trust prompt answered inside the
  plugin) was not measurable in isolation, so the trust rules are anchored
  on the captured dialogs and the flag is kept as declared.
- The working rules carry no `overrides_program_status`: while skills load
  the record reads `idle` and while the context compacts it reads `done`,
  so a live session with a held record reads those two states as idle.
  The screen alone (no record: startup, replay, `detect-check`) reads them
  as working.
- On a static trust page the live activity stays `working` (the page
  sends no interleaving bytes, so the byte-activity fallback never
  settles), and `session input` is not refused there until the core gap
  https://github.com/zajca/pohunek/issues/2447 is fixed. The corpus
  `blocked` expects still hold: they come from `detect-check` replay of
  the settled screen, not from live activity.
- The full V5 E2E runs as `scripts/e2e-v5.sh` outside the kit script
  because the kit kills scripts after 60 s (core limitation,
  https://github.com/zajca/pohunek/issues/2446). The kit script keeps V3
  plus the V5 core only. The kit clears the script environment, so
  `scripts/smoke-vibe.sh` falls back to a scratch dir
  `<repository root>/.tmp-smoke-vibe` (gitignored) when `TMPDIR` is unset
  and removes it on exit.
- The capture and live rig lives in-tree under `scripts/rig/`: `up.sh`
  (stub, proxy, daemon, `package/` link — the link target is the
  `package/` subdirectory only, because the daemon archives the target
  and the corpus beside it would exceed the 512-file package limit —
  enable, select, profile bind, migrate; it validates every input before
  starting anything and stops what it started on failure), `cli.sh
  <rig-root> <args>` (root-pinned CLI wrapper: `HOME`/`VIBE_HOME`/sockets
  under the rig root, never /tmp), `cli-for.sh` (same CLI with the root in
  `RIG_ROOT`, the single path `e2e-v5.sh` and `answer1.py` call),
  `mkprofile.sh` (profile from `PROFILE_DIGEST`, no silent default),
  `down.sh` (signals a recorded PID only when its `/proc` cmdline is the
  rig's own `pohunekd`/`stub.py`/`proxy.py` and exits non-zero when one
  survives). The stub also serves `[[ASK3]]` and `[[ASK4]]` (3 and 4
  option questions under another title).
  `REL=<release> scripts/e2e-v5.sh <rig-root> <cols> <rows>` drives the
  real package (a)-(g) with `--input` first prompts, 20 attach answers
  that each assert the input rc, `blocked/question/screen`, the stub's
  ASK count rising by one and a non-empty `idle/` or `working/` reading
  (logged as `ok c-clears-<n> (<reading>)`), recorded-PID survival
  after stop and SIGKILL, placement `clean`, `HOME`/`VIBE_HOME`/cwd under
  the rig root while the sessions live; every argument and `REL` are
  required and `TMPDIR` must point under the rig root.
- Dialogs are answered in an attached terminal (PTY `attach` + key +
  detach), never through `session input` while blocked: `session input`
  to a blocked session fails with `session_input_blocked` by design
  (`refuse_while_blocked`), the answer goes through the attach path.
- Trust in a subdirectory that holds its own `AGENTS.md` reads `blocked`:
  a fresh trust dialog appears for the subdirectory checkout.
- What is verified: see `compat/compatibility-lock.json` `verified_with`
  (S1 captures and measurements on core f6f12ad9, S2 gates and the live
  V5 E2E on core 717a31ce0, what ran, what was reduced, the unmeasured
  positive `--trust` path).
- Supply the key through the profile `[env]` or a secret, never in the
  repository; no key material is committed.

## Detection anchors

Every blocked and working rule is one ordered multi-line `regex` over its
frame; no dialog or page is matched by a bare `contains` bag. Narrow
screens (down to 20 columns) slice and wrap every dialog line, so each
pattern matches only short width-stable fragments (option numbers and row
heads, wrapping mid-word titles) between the border lines, in order, with
at most the status footer before the screen end. A transcript quote of this
file, of `package/detect.toml`, or of a raw corpus screen holds the same
words but never the ordered box frame, so it matches no rule and keeps the
byte-activity fallback.

- Approval (`bottom_non_empty_lines(16)`, blocked, visible blocker): `┌…┐`
  top border, `│ Permission for` title, option rows in order (`1. Allow
  once` first, `4. Deny` last, heads only), `↑↓/jk navigate` key hint, `└…┘`
  bottom border, then at most the footer before `\z`.
- Question (`bottom_non_empty_lines(32)`, blocked): same `┌…┘` frame; the `1. ` option row,
  the numbered `Type your a…` answer row (its number is the option count
  plus one, so 3 for two options, 4 for three; truncated even at 60
  columns), the navigate hint, the bottom border, then at most the
  footer. The per-question title is never matched.
- Trust folder / repository (whole screen, blocked): `╭…╮` top, the
  `Malicio…us` warning heading, the centred `Trust this fol…` /
  `Trust folder o…` title, the option row (`1. Trust fold…`; repository
  also carries the `git…reposit…` detail rows), the `↑↓/jk scroll` hint,
  `╰…╯` plus the `▁` status rule at the bottom.
- Onboarding (one frame-anchored rule per wizard step, whole screen,
  blocked): welcome `╭…╮` + `Welcome to Mistral` + `╰…╯` (plus `Enter
  continue` when the rows fit; the height-cropped L4 screens end at the
  bottom border); theme `Select your preferre` heading + the auto/preview
  `╭…╰` boxes; sign-in the `Launch browser` / `Use an API key` rows inside
  `┌… Recommended …┐` box and `┌…┐` rows (the heading-and-hint L4 crops
  match the heading plus the `↑↓/jk navigate` hint); provider `Where do
  you sign` + the `┌… Recommended …┐` box with `Mistral AI` / `Sign in to
  a` (plus the labelled L4 variant); browser `Launch browser` + the
  `┌…┐` panels with `Waiting for au` and `Finished setup`; API key the
  `chat.mistr…` help URL + the contiguous `┌─ Paste API key …┐` / `│` /
  `└…┘` input box. Every onboarding tail after the closing border admits
  only blank lines and lines that start with a space or tab, so a rule
  can never reach a composer (`─` or `>` at column 0).
- Enlarge terminal (whole screen, blocked): matches only when the whole
  visible text is `Enlarge terminal to continue`. The page waits for a
  resize rather than an answer. A quote of that sentence in the transcript
  never matches; a screen cropped so short that the page is the only text
  is the single shape this rule accepts.
- Working: the live spinner frame (multi-line `regex`, bottom 16: a
  two-column braille spinner field, then `Generating|Thinking|Initializing|
  Retrying|Running command|Loading skills|User input required` at column 3
  + `…`, the composer top rule on the next line, then a composer that runs
  to the screen end). Assistant text is indented two columns, so an
  indented spinner quote, a quote followed by more transcript and a `cat`
  of a generating screen match no rule. Residual: a spinner-shaped line at
  column 0 that is the last transcript line above the live composer still
  reads working. And the
  `■/□ Compacting…` transcript line followed only by its wrapped
  continuation, blank lines and spinner lines before the composer. A
  transcript line that merely mentions a Compacting entry matches no rule.
- A capture whose rendered screen is blank has no frame and no rule
  matches it; the kit reports the byte-activity fallback there, so such a
  capture is not a corpus case.
- Idle: the agent-independent composer frame — the full-width `─` top rule
  with the agent label between the runs, the `> ` composer line, the
  closing rule, and a footer holding `ctx`. No agent name is matched, so
  every builtin agent (`ask`, `accept-edits`, `smart-approve`,
  `auto-approve`) reads idle from the same rule. `exit` and `fatal_cwd`
  are stream text without a terminal frame and match no rule (corpus cases
  with `expect` read from the screen); the failed-compaction tail reads
  idle.

## Measurements behind the descriptor

- `vibe --version` prints `vibe 3.1.3`, exit 0, 12-19 ms (10 runs each).
- Cold start to the first idle record: p50 ~1.7 s, p95 ~1.8 s;
  `startup_grace_ms = 20000` is margin above twice p95.
- Smallest lossless `submit_delay_ms` is 0; the descriptor keeps 150 ms
  (the Pi value) as unmeasured margin.
- `input.ready = "screen_idle"`: the idle rule reads the screen region,
  so strict sessions gate the first input on the composer.
- The `ctx` footer carries no digits at 20-50 columns, so the idle rule
  matches `ctx` without a meter.

## Local checks

Run these from the repository root (a checkout of the core tag under
`../core` provides the kit and the daemon binaries the smoke reads;
build them first, as the CI does):

```sh
(cd ../core && cargo build --locked -p pohunek-plugin-kit --features daemon)
(cd ../core && cargo build --locked -p pohunek-cli -p pohunek-daemon -p pohunek-session-worker)
export UPSTREAM_BIN="$PWD/upstream-bin"
bash scripts/install-upstream.sh
../core/target/debug/pohunek-plugin-kit lint --dir package
rm -rf build-one build-two dist release-dir
mkdir -p build-one build-two dist
../core/target/debug/pohunek-plugin-kit build --dir package --output-dir build-one
../core/target/debug/pohunek-plugin-kit build --dir package --output-dir build-two
cmp build-one/*.tar.zst build-two/*.tar.zst
cp build-one/*.tar.zst dist/
archive="$(echo dist/*.tar.zst)"
../core/target/debug/pohunek-plugin-kit verify --dir package --archive "$archive" \
  --sha256 "sha256:$(shasum -a 256 "$archive" | cut -d' ' -f1)"
../core/target/debug/pohunek-plugin-kit detect-check --dir package --corpus corpus
python3 -I -B scripts/path-check.py
mkdir -p release-dir
cp ../core/target/debug/pohunek ../core/target/debug/pohunekd \
  ../core/target/debug/pohunek-sessiond release-dir/
../core/target/debug/pohunek-plugin-kit smoke --dir package --release-dir release-dir \
  --upstream "$UPSTREAM_BIN" --json
```

`scripts/path-check.py` (python3 standard library only) renders every corpus
screen at its case width, strips box characters, `…` and all whitespace and
exits 1, listing the file and token, when operator path material is left.
It searches the final frame, the frame standing before every full-screen
erase, the rows that scrolled off, and the raw bytes with every escape
sequence (CSI, string and two-byte forms) removed. A path that a narrow
terminal wrapped across box rows, that was drawn in cursor-addressed pieces
and then erased, or that a footer cut with a leading `…` keeps a whole token
is found the same way as an unbroken one; a cut that leaves no whole token
is not detected. Screens keep the neutral `/work/...` placeholders.

The generic tokens are built in: absolute `/mnt/`, `/home/<user>` and `/tmp/`
prefixes, the capture directory prefix and the owner's account name outside
the public repository URL. Host-specific path fragments do not ship: they
live one per line in the gitignored `scripts/path-tokens.local`, which the
check requires. With neither that file nor `--generic-only` it exits 2 with a
named error. The CI has no local file and runs `--generic-only` in its own
`path-check` job, so a CI pass covers the generic tokens only; run the check
with the local file before adding or changing a screen. In the command list
above, the check runs without a flag and needs the local file.

The CI (`plugin-ci.yml`, `upstream-install: scripts/install-upstream.sh`) runs
the other steps of that list, except the `release` row downloads the attested daemon archive
of the core tag instead of copying local debug binaries.
