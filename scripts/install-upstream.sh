#!/usr/bin/env bash
# Upstream install of the Mistral Vibe runtime plugin.
#
# Installs the release pinned in `compat/RELEASE` into `$UPSTREAM_BIN` by
# creating an isolated virtualenv (`$UPSTREAM_BIN/.vibe-venv`) and installing
# the fully hashed requirements from `compat/requirements-<release>.txt`
# with `--only-binary :all: --no-deps` (no network beyond the hashed PyPI
# downloads, no build from source). A `vibe` symlink next to the venv points
# at the installed entry point, so the isolated daemon resolves the
# descriptor's `[runtime] program` to this locked install.
#
# The CI smoke step runs this script with the repository root as the working
# directory and `UPSTREAM_BIN` set to an absolute directory; the local smoke
# check does the same (see "Local checks" in README.md). Requirements:
# a `python3` of at least 3.12 on PATH (the lock targets CPython 3.12 on
# x86_64-manylinux) and network access to PyPI for the hashed downloads.
set -euo pipefail

if [ -z "${UPSTREAM_BIN:-}" ]; then
  echo "install-upstream.sh: UPSTREAM_BIN is unset" >&2
  exit 1
fi
mkdir -p "$UPSTREAM_BIN"

version="$(sed -e 's/#.*//' compat/RELEASE | grep -v '^[[:space:]]*$' | tail -n 1 || true)"
if [ -z "$version" ]; then
  echo "install-upstream.sh: no release in compat/RELEASE" >&2
  exit 1
fi
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "install-upstream.sh: invalid release '$version' in compat/RELEASE (want MAJOR.MINOR.PATCH)" >&2
  exit 1
fi

requirements="compat/requirements-${version}.txt"
if [ ! -f "$requirements" ]; then
  echo "install-upstream.sh: missing lock file '$requirements'" >&2
  exit 1
fi

if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)'; then
  echo "install-upstream.sh: python3 is older than 3.12 ($(python3 --version 2>&1))" >&2
  exit 1
fi

python3 -m venv "$UPSTREAM_BIN/.vibe-venv"
"$UPSTREAM_BIN/.vibe-venv/bin/pip" install --require-hashes --only-binary :all: --no-deps \
  -r "$requirements"
ln -sf ".vibe-venv/bin/vibe" "$UPSTREAM_BIN/vibe"

if [ "$("$UPSTREAM_BIN/vibe" --version)" != "vibe $version" ]; then
  echo "install-upstream.sh: installed vibe does not report 'vibe $version'" >&2
  exit 1
fi
