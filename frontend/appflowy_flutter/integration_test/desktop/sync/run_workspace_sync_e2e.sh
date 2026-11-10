#!/usr/bin/env bash
# Runs the workspace sync end-to-end steps against the real application and
# backend: one process per step, and each computer with its own HOME, so the
# two never share settings, data or their name in the sync folder.
#
#   integration_test/desktop/sync/run_workspace_sync_e2e.sh [root]
#
# Everything, including both fake homes, is kept under the root (a fresh
# temporary folder when none is given) for inspection afterwards.
set -euo pipefail

cd "$(dirname "$0")/../../.."
root="${1:-$(mktemp -d "${TMPDIR:-/tmp}/appflowy-sync-e2e.XXXXXX")}"
mkdir -p "$root/home-a" "$root/home-b"

run() {
  local home="$1" step="$2"
  echo "== step $step (HOME=$home)"
  env -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u XDG_CACHE_HOME HOME="$home" \
    flutter test integration_test/desktop/sync/workspace_sync_e2e_test.dart \
    -d linux \
    --dart-define=SYNC_E2E_STEP="$step" \
    --dart-define=SYNC_E2E_ROOT="$root"
}

run "$root/home-a" a1
run "$root/home-b" b1
run "$root/home-a" a2
run "$root/home-a" a3
run "$root/home-b" b2
echo "All steps passed. Everything is in $root"
