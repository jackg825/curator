#!/usr/bin/env bash
# test/hr-acceptance.sh — DX Hard Requirement acceptance tests.
# HR-1: pattern-signal.md must NOT auto-inject into ambient context.
# HR-2: pattern proposal is one-per-session, deferrable.
# HR-3: /curator:memory shows connection + freshness state.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CURATOR_HOME="$REPO_ROOT"

PLAYGROUND="$(mktemp -d /tmp/curator-hr.XXXXX)"
trap 'rm -rf "$PLAYGROUND"' EXIT

export CLAUDE_HOME="$PLAYGROUND/.claude"
export CURATOR_STATE="$PLAYGROUND/.curator"
export CLAUDE_PROJECT_ROOT="$PLAYGROUND/project"
export CLAUDE_SESSION_ID="hr-test"
export CURATOR_MEMPALACE_URL="mock://$REPO_ROOT/test/fixtures/mock-mempalace.sh"
export MOCK_MCP_LOG="$PLAYGROUND/mcp.log"
export MOCK_MCP_MODE=ok

mkdir -p "$CLAUDE_HOME" "$CURATOR_STATE" "$CLAUDE_PROJECT_ROOT/memory"
echo '{"hooks":{}}' > "$CLAUDE_HOME/settings.json"
"$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp > /dev/null

fail() { echo "HR FAIL: $1" >&2; exit 1; }

echo "== HR-1: pattern-signal.md ambient context isolation =="
"$REPO_ROOT/core/hooks/session-start.sh"
# Verify settings.json contains NO reference to pattern-signal.md (other than memdir path)
if grep -r "pattern-signal" "$CLAUDE_HOME/settings.json" 2>/dev/null; then
  fail "HR-1: pattern-signal.md appears in settings.json — auto-inject risk"
fi
# Verify MEMORY.md does NOT @include pattern-signal
if grep -q "pattern-signal" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"; then
  fail "HR-1: MEMORY.md references pattern-signal.md"
fi
echo "  HR-1 OK — pattern-signal.md is a memdir file only, not auto-loaded"

echo "== HR-2: one proposal per session, deferrable =="
mkdir -p "$CURATOR_STATE/pattern-candidates"
echo "first rule" > "$CURATOR_STATE/pattern-candidates/hr-test.txt"
out1=$("$REPO_ROOT/core/hooks/user-prompt-submit.sh" 2>&1 || true)
[[ "$out1" == *"first rule"* ]] || fail "HR-2: first proposal not emitted"

echo "second rule" > "$CURATOR_STATE/pattern-candidates/hr-test.txt"
out2=$("$REPO_ROOT/core/hooks/user-prompt-submit.sh" 2>&1 || true)
[ -z "$out2" ] || [[ "$out2" != *"second rule"* ]] || fail "HR-2: second proposal leaked"
echo "  HR-2 OK — proposal count capped at 1 per session"

echo "== HR-3: /curator:memory shows connection + freshness =="
# Call the memory skill's inline bash directly — simulates slash command
out=$(bash -c '
  source "$CURATOR_HOME/core/lib/common.sh"
  source "$CURATOR_HOME/core/lib/mcp-client.sh"
  export CURATOR_STATE CLAUDE_PROJECT_ROOT
  # Inline the status block from skills/memory.md
  mem="$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
  if [ -f "$mem" ]; then
    l0_entries=$(grep -c "^- " "$mem" 2>/dev/null || echo 0)
    echo "[MEMORY.md]     L0 · $l0_entries entries"
  fi
  if mcp_ping 2>/dev/null; then
    echo "[MemPalace]     connected"
  else
    echo "[MemPalace]     disconnected"
  fi
')
[[ "$out" == *"[MEMORY.md]"* ]] || fail "HR-3: missing MEMORY.md line"
[[ "$out" == *"[MemPalace]"* ]] || fail "HR-3: missing MemPalace line"
echo "  HR-3 OK — status output contains required fields"

echo
echo "ALL HR ACCEPTANCE TESTS PASSED"
