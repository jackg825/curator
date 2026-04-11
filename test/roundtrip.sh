#!/usr/bin/env bash
# test/roundtrip.sh — full curator lifecycle smoke test.
# Uses the mock MCP server; no real MemPalace required.
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
export CURATOR_MEMPALACE_URL="mock://$REPO_ROOT/test/fixtures/mock-mempalace.sh"
export MOCK_MCP_LOG="$PLAYGROUND/mcp.log"
export MOCK_MCP_MODE=ok

mkdir -p "$CLAUDE_HOME" "$CURATOR_STATE" "$CLAUDE_PROJECT_ROOT/memory"
echo '{"hooks":{}}' > "$CLAUDE_HOME/settings.json"

echo "== 1. Install =="
"$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
[ -f "$CURATOR_STATE/install-receipt.json" ] || { echo "FAIL: no install receipt"; exit 1; }

echo "== 2. SessionStart hook =="
"$REPO_ROOT/core/hooks/session-start.sh"
[ -f "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md" ] || { echo "FAIL: MEMORY.md not created"; exit 1; }
grep -q "source=fresh" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md" || { echo "FAIL: not fresh"; exit 1; }

echo "== 3. Capture a memory (via direct lib call, simulating /curator:capture) =="
source "$REPO_ROOT/core/lib/common.sh"
source "$REPO_ROOT/core/lib/journal.sh"
source "$REPO_ROOT/core/lib/mcp-client.sh"
journal_append "feedback" '{"text":"use pnpm not npm in this repo"}'
# Verify journal has entry
[ "$(wc -l < "$CURATOR_STATE/pending_sync.jsonl")" -ge 1 ] || { echo "FAIL: journal empty"; exit 1; }

echo "== 4. Stop hook flushes pending =="
"$REPO_ROOT/core/hooks/stop.sh"
pending=$(jq -s 'map(select(.pending | length > 0)) | length' "$CURATOR_STATE/pending_sync.jsonl")
[ "$pending" = "0" ] || { echo "FAIL: still $pending pending"; exit 1; }

echo "== 5. Second session: reconcile on SessionStart is a no-op =="
export CLAUDE_SESSION_ID="roundtrip-2"
"$REPO_ROOT/core/hooks/session-start.sh"
# proposal_count reset
count=$(jq -r .proposal_count "$CURATOR_STATE/session-state.json")
[ "$count" = "0" ] || { echo "FAIL: proposal_count not reset"; exit 1; }

echo "== 6. Pattern proposal pipeline (simulated candidate) =="
# Pre-emptive fix: the echo below runs BEFORE user-prompt-submit.sh (which does the mkdir),
# so we must create the dir ourselves to avoid "No such file or directory" under set -e.
mkdir -p "$CURATOR_STATE/pattern-candidates"
echo "prefer pnpm over npm" > "$CURATOR_STATE/pattern-candidates/roundtrip-2.txt"
output=$("$REPO_ROOT/core/hooks/user-prompt-submit.sh" 2>&1 || true)
[[ "$output" == *"pattern"* ]] || { echo "FAIL: proposal not emitted: $output"; exit 1; }
# Verify one-per-session cap
output2=$("$REPO_ROOT/core/hooks/user-prompt-submit.sh" 2>&1 || true)
[ -z "$output2" ] || [[ "$output2" != *"pattern"* ]] || { echo "FAIL: HR-2 violated"; exit 1; }

echo "== 7. Uninstall =="
"$REPO_ROOT/core/scripts/uninstall.sh" --keep-state
# Curator hooks gone from settings.json
curator_hook_count=$(jq '[.hooks.Stop[]?.hooks[0].command] | map(select(contains("curator"))) | length' "$CLAUDE_HOME/settings.json")
[ "$curator_hook_count" = "0" ] || { echo "FAIL: curator hooks remain after uninstall"; exit 1; }

echo
echo "ROUNDTRIP OK"
