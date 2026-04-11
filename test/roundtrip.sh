#!/usr/bin/env bash
# test/roundtrip.sh — full curator lifecycle smoke test (v1.2).
# No real or mock MCP needed: v1.2 dropped the MCP write path entirely.
# Expected: prints "ROUNDTRIP OK" and exits 0 on success.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CURATOR_HOME="$REPO_ROOT"

# Isolated playground
PLAYGROUND="$(mktemp -d /tmp/curator-roundtrip.XXXXX)"
trap 'rm -rf "$PLAYGROUND"' EXIT

export CLAUDE_HOME="$PLAYGROUND/.claude"
export CURATOR_STATE="$PLAYGROUND/.curator"
export CLAUDE_PROJECT_ROOT="$PLAYGROUND/project"
export CLAUDE_SESSION_ID="roundtrip-1"
# v1.2 ignores any mempalace binary on PATH for hermetic test runs
export CURATOR_MEMPALACE_BIN="/nonexistent/path/mempalace"

mkdir -p "$CLAUDE_HOME" "$CURATOR_STATE" "$CLAUDE_PROJECT_ROOT/memory"
echo '{"hooks":{}}' > "$CLAUDE_HOME/settings.json"

echo "== 1. Install =="
"$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
[ -f "$CURATOR_STATE/install-receipt.json" ] || { echo "FAIL: no install receipt"; exit 1; }
[ "$(jq -r .version "$CURATOR_STATE/install-receipt.json")" = "1.2.0" ] \
  || { echo "FAIL: receipt version not 1.2.0"; exit 1; }

echo "== 2. SessionStart hook resets per-session state =="
"$REPO_ROOT/core/hooks/session-start.sh"
[ -f "$CURATOR_STATE/session-state.json" ] || { echo "FAIL: session-state.json not written"; exit 1; }
[ "$(jq -r .proposal_count "$CURATOR_STATE/session-state.json")" = "0" ] \
  || { echo "FAIL: proposal_count not 0"; exit 1; }

echo "== 3. Capture appends to local pattern-signal =="
ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
mkdir -p "$(dirname "$ps")"
echo "<!-- curator-pattern-signal schema_version=1 -->" > "$ps"
echo "- $(date -u +%Y-%m-%dT%H:%M:%SZ) | use pnpm not npm | device=test" >> "$ps"
[ -s "$ps" ] || { echo "FAIL: pattern-signal not written"; exit 1; }

echo "== 4. Stop hook prunes pattern-signal =="
"$REPO_ROOT/core/hooks/stop.sh"
grep -q "use pnpm" "$ps" || { echo "FAIL: fresh entry pruned"; exit 1; }

echo "== 5. Second session resets proposal_count =="
export CLAUDE_SESSION_ID="roundtrip-2"
"$REPO_ROOT/core/hooks/session-start.sh"
count=$(jq -r .proposal_count "$CURATOR_STATE/session-state.json")
[ "$count" = "0" ] || { echo "FAIL: proposal_count not reset"; exit 1; }

echo "== 6. Pattern proposal pipeline (simulated candidate) =="
mkdir -p "$CURATOR_STATE/pattern-candidates"
echo "prefer pnpm over npm" > "$CURATOR_STATE/pattern-candidates/roundtrip-2.txt"
output=$("$REPO_ROOT/core/hooks/user-prompt-submit.sh" 2>&1 || true)
[[ "$output" == *"pattern"* ]] || { echo "FAIL: proposal not emitted: $output"; exit 1; }
# Verify one-per-session cap (HR-2)
output2=$("$REPO_ROOT/core/hooks/user-prompt-submit.sh" 2>&1 || true)
[ -z "$output2" ] || [[ "$output2" != *"pattern"* ]] || { echo "FAIL: HR-2 violated"; exit 1; }

echo "== 7. Uninstall =="
"$REPO_ROOT/core/scripts/uninstall.sh" --keep-state
curator_hook_count=$(jq '[.hooks.Stop[]?.hooks[0].command] | map(select(contains("curator"))) | length' "$CLAUDE_HOME/settings.json")
[ "$curator_hook_count" = "0" ] || { echo "FAIL: curator hooks remain after uninstall"; exit 1; }

echo
echo "ROUNDTRIP OK"
