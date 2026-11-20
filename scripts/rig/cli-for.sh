#!/usr/bin/env bash
# Single-path rig CLI for callers that cannot pass the rig root as the first
# argument (scripts/e2e-v5.sh, scripts/answer1.py): runs the isolated CLI of
# the rig root named by RIG_ROOT. Fails closed when RIG_ROOT is unset.
# Usage: RIG_ROOT=<rig-root> cli-for.sh <pohunek args...>
set -u
: "${RIG_ROOT:?cli-for.sh: RIG_ROOT required}"
exec "$(cd "$(dirname "$0")" && pwd)/cli.sh" "$RIG_ROOT" "$@"
