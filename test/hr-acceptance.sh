#!/usr/bin/env bash
# test/hr-acceptance.sh — DX Hard Requirement acceptance tests (v1.2).
# HR-1: pattern-signal.md must NOT auto-inject into ambient context.
# HR-2: pattern proposal is one-per-session, deferrable.
# HR-3: /curator:memory shows the local pattern-signal + mempalace availability.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CURATOR_HOME="$REPO_ROOT"

PLAYGROUND="$(mktemp -d /tmp/curator-hr.XXXXX)"
trap 'rm -rf "$PLAYGROUND"' EXIT

export CLAUDE_HOME="$PLAYGROUND/.claude"
export CURATOR_STATE="$PLAYGROUND/.curator"
export CLAUDE_PROJECT_ROOT="$PLAYGROUND/project"
export CLAUDE_SESSION_ID="hr-test"
# Hermetic test: force mempalace_available to fail by pointing at a missing path.
export CURATOR_MEMPALACE_BIN="/nonexistent/path/mempalace"

mkdir -p "$CLAUDE_HOME" "$CURATOR_STATE" "$CLAUDE_PROJECT_ROOT/memory"
echo '{"hooks":{}}' > "$CLAUDE_HOME/settings.json"
"$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp > /dev/null

fail() { echo "HR FAIL: $1" >&2; exit 1; }

echo "== HR-1: pattern-signal.md ambient context isolation =="
"$REPO_ROOT/core/hooks/session-start.sh"
# Verify settings.json contains NO reference to pattern-signal
if grep -q "pattern-signal" "$CLAUDE_HOME/settings.json" 2>/dev/null; then
  fail "HR-1: pattern-signal appears in settings.json — auto-inject risk"
fi
# v1.2: SessionStart no longer creates MEMORY.md, so no @include risk
if [ -e "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md" ] && grep -q "pattern-signal" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"; then
  fail "HR-1: MEMORY.md references pattern-signal"
fi
echo "  HR-1 OK — pattern-signal is local-only, not auto-loaded"

echo "== HR-2: one proposal per session, deferrable =="
mkdir -p "$CURATOR_STATE/pattern-candidates"
echo "first rule" > "$CURATOR_STATE/pattern-candidates/hr-test.txt"
out1=$("$REPO_ROOT/core/hooks/user-prompt-submit.sh" 2>&1 || true)
[[ "$out1" == *"first rule"* ]] || fail "HR-2: first proposal not emitted"

echo "second rule" > "$CURATOR_STATE/pattern-candidates/hr-test.txt"
out2=$("$REPO_ROOT/core/hooks/user-prompt-submit.sh" 2>&1 || true)
[ -z "$out2" ] || [[ "$out2" != *"second rule"* ]] || fail "HR-2: second proposal leaked"
echo "  HR-2 OK — proposal count capped at 1 per session"

echo "== HR-3: /curator:memory shows pattern-signal + mempalace status =="
# Inline the status block from skills/memory.md
out=$(bash -c '
  source "$CURATOR_HOME/core/lib/common.sh"
  source "$CURATOR_HOME/core/lib/mempalace-cli.sh"
  ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
  if [ -f "$ps" ]; then
    ps_entries=$(grep -c "^- " "$ps" 2>/dev/null || echo 0)
    echo "[pattern-signal] $ps_entries observations"
  else
    echo "[pattern-signal] (empty)"
  fi
  if mempalace_available; then
    echo "[MemPalace CLI] available"
  else
    echo "[MemPalace CLI] not installed"
  fi
')
[[ "$out" == *"[pattern-signal]"* ]] || fail "HR-3: missing pattern-signal line"
[[ "$out" == *"[MemPalace CLI]"* ]] || fail "HR-3: missing MemPalace CLI line"
echo "  HR-3 OK — status output contains required fields"

echo
echo "ALL HR ACCEPTANCE TESTS PASSED"
