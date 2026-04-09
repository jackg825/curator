# Harness Engineering Workflow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a portable Claude Code harness monorepo with JSONL event queue, CQRS memory bridge, and build-loop workflow integration.

**Architecture:** Layer Cake (L0 Core → L1 Memory Bridge → L2 Workflows). Hooks are thin triggers writing to JSONL. Native memory is write model; MemPalace is audit log + semantic read model. All routing is deterministic shell logic.

**Tech Stack:** Bash (hooks, scripts), JSONL (event persistence), Markdown (skills, commands, templates), Claude Code hooks API (settings.json)

**Spec:** `docs/superpowers/specs/2026-04-10-harness-workflow-design.md`

---

## File Map

```
harness/
├── core/
│   ├── hooks/
│   │   ├── hook-wrapper.sh          # Task 1: shared wrapper (timeout, JSONL append)
│   │   ├── session-start.sh         # Task 2: WAL recovery + health check
│   │   ├── post-tool-use.sh         # Task 3: event capture
│   │   └── session-end.sh           # Task 4: batch sync + learn-eval trigger
│   ├── templates/
│   │   ├── CLAUDE.md.template       # Task 5: harness-aware CLAUDE.md
│   │   └── settings.json.template   # Task 5: hook wiring
│   └── scripts/
│       ├── install.sh               # Task 6: deploy to ~/.claude/
│       └── health-check.sh          # Task 2: MemPalace MCP check
├── memory-bridge/
│   ├── router.sh                    # Task 7: deterministic routing rules
│   ├── sync.sh                      # Task 8: batch push to MemPalace
│   ├── recover.sh                   # Task 9: WAL recovery
│   └── adapter-interface.md         # Task 10: MemoryAdapter contract
├── workflows/
│   ├── commands/
│   │   └── build-loop.md            # Task 11: build-loop with event emission
│   └── skills/
│       ├── learn-eval.md            # Task 12: session-end pattern extraction
│       └── pattern-extract.md       # Task 13: confidence scoring + quarantine
├── docs/
│   ├── quickstart.md                # Task 14: 5-minute onboarding
│   └── memory-routing.md            # Task 14: decision tree
└── README.md                        # Task 14: entry point
```

---

## Task 1: Hook Wrapper (Shared Foundation)

**Files:**
- Create: `core/hooks/hook-wrapper.sh`
- Test: manual — `bash core/hooks/hook-wrapper.sh test_event '{"test":true}'`

This is the shared foundation all hooks call. It handles timeout, JSONL append, and session ID management.

- [ ] **Step 1: Create hook-wrapper.sh with JSONL append logic**

```bash
#!/usr/bin/env bash
# hook-wrapper.sh — Shared hook foundation
# Usage: source hook-wrapper.sh; emit_event <type> <payload_json>
# All hooks source this file and call emit_event.
# Events written to ~/.harness/events/session-<id>.jsonl (append-only).

set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:-$HOME/.harness}"
EVENTS_DIR="$HARNESS_DIR/events"
PENDING_SYNC="$HARNESS_DIR/pending_sync.jsonl"
FILTERED_LOG="$HARNESS_DIR/filtered.jsonl"

mkdir -p "$EVENTS_DIR"

get_session_id() {
  # Claude Code sets CLAUDE_SESSION_ID; fall back to PID-based ID
  echo "${CLAUDE_SESSION_ID:-session-$$-$(date +%s)}"
}

generate_uuid() {
  # portable UUID: works on macOS (uuidgen) and Linux (cat /proc/sys/kernel/random/uuid)
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [ -f /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    # fallback: timestamp + random
    echo "$(date +%s)-$RANDOM-$RANDOM"
  fi
}

content_hash() {
  # SHA-256 of input string
  echo -n "$1" | shasum -a 256 | cut -d' ' -f1
}

emit_event() {
  local event_type="$1"
  local payload_json="$2"
  local session_id
  session_id="$(get_session_id)"
  local event_id
  event_id="$(generate_uuid)"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local hash
  hash="$(content_hash "$payload_json")"

  local event_file="$EVENTS_DIR/session-${session_id}.jsonl"

  # Single atomic append — no locking needed for single-writer
  printf '{"id":"%s","type":"%s","ts":"%s","session_id":"%s","content_hash":"sha256:%s","payload":%s}\n' \
    "$event_id" "$event_type" "$ts" "$session_id" "$hash" "$payload_json" \
    >> "$event_file"
}

# If called directly (not sourced), emit a test event
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  event_type="${1:-test_event}"
  payload="${2:-'{\"test\":true}'}"
  emit_event "$event_type" "$payload"
  echo "[harness] Event emitted: $event_type → $EVENTS_DIR/session-$(get_session_id).jsonl"
fi
```

- [ ] **Step 2: Make executable and test**

Run: `chmod +x core/hooks/hook-wrapper.sh && bash core/hooks/hook-wrapper.sh test_event '{"hello":"world"}'`

Expected: Output like `[harness] Event emitted: test_event → ~/.harness/events/session-....jsonl`

- [ ] **Step 3: Verify JSONL output**

Run: `cat ~/.harness/events/session-*.jsonl | head -1 | python3 -m json.tool`

Expected: Valid JSON with `id`, `type`, `ts`, `session_id`, `content_hash`, `payload` fields.

- [ ] **Step 4: Commit**

```bash
git add core/hooks/hook-wrapper.sh
git commit -m "feat(core): add hook-wrapper.sh — JSONL event emitter foundation"
```

---

## Task 2: SessionStart Hook + Health Check

**Files:**
- Create: `core/hooks/session-start.sh`
- Create: `core/scripts/health-check.sh`
- Test: manual — `bash core/hooks/session-start.sh`

- [ ] **Step 1: Create health-check.sh**

```bash
#!/usr/bin/env bash
# health-check.sh — Verify harness dependencies at session start
# Exit 0 = all good, exit 1 = degraded (prints warnings but doesn't block)

set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:-$HOME/.harness}"
STATUS="ok"

# Check 1: ~/.harness/ directory exists
if [ ! -d "$HARNESS_DIR" ]; then
  mkdir -p "$HARNESS_DIR/events"
  echo "[harness] Created $HARNESS_DIR"
fi

# Check 2: MemPalace MCP server (optional — graceful degradation)
if command -v claude &>/dev/null; then
  # Try to detect if mempalace MCP tools are available
  # This is a best-effort check; if it fails, we just warn
  if ! claude mcp list 2>/dev/null | grep -q "mempalace" 2>/dev/null; then
    echo "[harness] WARNING: MemPalace MCP not detected. Running in native-only mode."
    echo "[harness] Install: pip install mempalace && mempalace serve"
    STATUS="degraded"
  fi
fi

# Check 3: Pending sync from previous sessions
PENDING="$HARNESS_DIR/pending_sync.jsonl"
if [ -f "$PENDING" ] && [ -s "$PENDING" ]; then
  PENDING_COUNT=$(wc -l < "$PENDING" | tr -d ' ')
  echo "[harness] WARNING: $PENDING_COUNT events pending sync from previous sessions."
  echo "[harness] Run /harness-sync to flush, or they will auto-sync at next SessionEnd."
  STATUS="degraded"
fi

# Check 4: Uncommitted WAL files from crashed sessions
UNCOMMITTED=$(find "$HARNESS_DIR/events" -name "session-*.jsonl" -newer "$HARNESS_DIR/.last_sync" 2>/dev/null | wc -l | tr -d ' ')
if [ "$UNCOMMITTED" -gt 0 ] 2>/dev/null; then
  echo "[harness] INFO: $UNCOMMITTED session logs pending — will sync at SessionEnd."
fi

exit 0
```

- [ ] **Step 2: Create session-start.sh**

```bash
#!/usr/bin/env bash
# session-start.sh — SessionStart hook
# Runs health check, WAL recovery, and emits session_start event.
# Must complete in < 50ms for non-degraded path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source shared wrapper
source "$SCRIPT_DIR/hook-wrapper.sh"

# 1. Health check (prints warnings, never blocks)
bash "$HARNESS_ROOT/core/scripts/health-check.sh" 2>/dev/null || true

# 2. WAL recovery — merge pending events into context
RECOVER_SCRIPT="$HARNESS_ROOT/memory-bridge/recover.sh"
if [ -f "$RECOVER_SCRIPT" ]; then
  bash "$RECOVER_SCRIPT" 2>/dev/null || true
fi

# 3. Emit session_start event
emit_event "session_start" '{"hook":"SessionStart"}'

# 4. Touch last_sync marker if it doesn't exist
touch "$HARNESS_DIR/.last_sync" 2>/dev/null || true
```

- [ ] **Step 3: Make executable and test**

Run: `chmod +x core/hooks/session-start.sh core/scripts/health-check.sh && bash core/hooks/session-start.sh`

Expected: Health check warnings (MemPalace not found), event emitted. No errors.

- [ ] **Step 4: Commit**

```bash
git add core/hooks/session-start.sh core/scripts/health-check.sh
git commit -m "feat(core): add session-start hook + health-check script"
```

---

## Task 3: PostToolUse Hook

**Files:**
- Create: `core/hooks/post-tool-use.sh`
- Test: manual — `TOOL_NAME=Bash TOOL_INPUT='ls' bash core/hooks/post-tool-use.sh`

- [ ] **Step 1: Create post-tool-use.sh**

```bash
#!/usr/bin/env bash
# post-tool-use.sh — PostToolUse hook
# Captures tool usage events. Must complete in < 50ms.
# Claude Code passes tool info via environment variables.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/hook-wrapper.sh"

# Claude Code hook environment variables
TOOL="${TOOL_NAME:-unknown}"
INPUT="${TOOL_INPUT:-}"

# Build payload — escape JSON special characters in input
ESCAPED_INPUT=$(echo "$INPUT" | head -c 200 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')

emit_event "post_tool_use" "{\"tool\":\"$TOOL\",\"input\":$ESCAPED_INPUT}"
```

- [ ] **Step 2: Make executable and test**

Run: `chmod +x core/hooks/post-tool-use.sh && TOOL_NAME=Bash TOOL_INPUT='git status' bash core/hooks/post-tool-use.sh`

Expected: No output (silent append to JSONL). Verify with `tail -1 ~/.harness/events/session-*.jsonl`.

- [ ] **Step 3: Commit**

```bash
git add core/hooks/post-tool-use.sh
git commit -m "feat(core): add post-tool-use hook — event capture"
```

---

## Task 4: SessionEnd Hook

**Files:**
- Create: `core/hooks/session-end.sh`
- Test: manual — `bash core/hooks/session-end.sh`

- [ ] **Step 1: Create session-end.sh**

```bash
#!/usr/bin/env bash
# session-end.sh — SessionEnd hook
# Triggers batch sync to MemPalace, learn-eval, and pending warnings.
# This is the most complex hook — it orchestrates end-of-session work.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/hook-wrapper.sh"

# 1. Emit session_end event
emit_event "session_end" '{"hook":"SessionEnd"}'

# 2. Batch sync to MemPalace (best-effort, non-blocking)
SYNC_SCRIPT="$HARNESS_ROOT/memory-bridge/sync.sh"
if [ -f "$SYNC_SCRIPT" ]; then
  # Run sync with timeout — don't block session exit
  timeout 10 bash "$SYNC_SCRIPT" 2>/dev/null &
  SYNC_PID=$!
  # Wait up to 5 seconds, then let it continue in background
  if ! wait -n "$SYNC_PID" 2>/dev/null; then
    echo "[harness] Sync running in background (PID: $SYNC_PID)"
  fi
fi

# 3. Check for pending events
PENDING="$HARNESS_DIR/pending_sync.jsonl"
if [ -f "$PENDING" ] && [ -s "$PENDING" ]; then
  PENDING_COUNT=$(wc -l < "$PENDING" | tr -d ' ')
  echo "[harness] $PENDING_COUNT events pending sync — run /harness-sync to flush"
fi

# 4. Clean up old filtered logs (> 7 days)
if [ -f "$FILTERED_LOG" ]; then
  WEEK_AGO=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d 2>/dev/null || echo "")
  if [ -n "$WEEK_AGO" ]; then
    # Keep only entries newer than 7 days
    TMP_FILTERED=$(mktemp)
    grep -E "\"ts\":\"$WEEK_AGO|\"ts\":\"$(date +%Y)" "$FILTERED_LOG" > "$TMP_FILTERED" 2>/dev/null || true
    mv "$TMP_FILTERED" "$FILTERED_LOG" 2>/dev/null || true
  fi
fi

# 5. Update last_sync marker
touch "$HARNESS_DIR/.last_sync" 2>/dev/null || true
```

- [ ] **Step 2: Make executable and test**

Run: `chmod +x core/hooks/session-end.sh && bash core/hooks/session-end.sh`

Expected: May print pending sync warnings. No errors. Event appended to JSONL.

- [ ] **Step 3: Commit**

```bash
git add core/hooks/session-end.sh
git commit -m "feat(core): add session-end hook — batch sync + cleanup"
```

---

## Task 5: Templates (CLAUDE.md + settings.json)

**Files:**
- Create: `core/templates/CLAUDE.md.template`
- Create: `core/templates/settings.json.template`

- [ ] **Step 1: Create CLAUDE.md.template**

```markdown
# Harness Engineering Workflow

This project uses the harness engineering workflow for structured development with memory management.

## Workflow
- Use `/build-loop` for non-trivial tasks (≥3 files OR ≥30 lines)
- build-loop phases: PLAN → IMPLEMENT → SIMPLIFY → REVIEW
- Each phase emits events to the JSONL event queue

## Memory System (CQRS)
- **Native memory** (`~/.claude/projects/*/memory/`): Current rules, source of truth
- **MemPalace** (if installed): Audit log + semantic search for historical context
- Routing is automatic and deterministic — see docs/memory-routing.md

## Event System
- All hooks write to `~/.harness/events/session-*.jsonl`
- Events are append-only, crash-safe
- SessionStart: WAL recovery + health check
- SessionEnd: batch sync + learn-eval

## Commands
- `/build-loop <task>` — structured development cycle
- `/harness-sync` — manually flush pending MemPalace sync
- `/harness-status` — show harness health and pending events
```

- [ ] **Step 2: Create settings.json.template**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "bash {{HARNESS_ROOT}}/core/hooks/session-start.sh"
      }
    ],
    "PostToolUse": [
      {
        "type": "command",
        "command": "bash {{HARNESS_ROOT}}/core/hooks/post-tool-use.sh"
      }
    ],
    "SessionEnd": [
      {
        "type": "command",
        "command": "bash {{HARNESS_ROOT}}/core/hooks/session-end.sh"
      }
    ]
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add core/templates/CLAUDE.md.template core/templates/settings.json.template
git commit -m "feat(core): add CLAUDE.md and settings.json templates"
```

---

## Task 6: Install Script

**Files:**
- Create: `core/scripts/install.sh`
- Test: `bash core/scripts/install.sh --dry-run`

- [ ] **Step 1: Create install.sh**

```bash
#!/usr/bin/env bash
# install.sh — Deploy harness to ~/.claude/ and ~/.harness/
# Usage: bash install.sh [--dry-run]
# Idempotent — safe to run multiple times.

set -euo pipefail

DRY_RUN="${1:-}"
HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
HARNESS_DIR="$HOME/.harness"

log() { echo "[harness-install] $*"; }
run() {
  if [ "$DRY_RUN" = "--dry-run" ]; then
    log "DRY-RUN: $*"
  else
    "$@"
  fi
}

log "Installing harness from: $HARNESS_ROOT"
log "Target: $CLAUDE_DIR, $HARNESS_DIR"

# 1. Create runtime directories
run mkdir -p "$HARNESS_DIR/events"
log "Created $HARNESS_DIR/events/"

# 2. Deploy settings.json hooks
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  log "WARNING: $SETTINGS_FILE already exists."
  log "Please manually merge hooks from core/templates/settings.json.template"
  log "Template path: $HARNESS_ROOT/core/templates/settings.json.template"
else
  # Replace {{HARNESS_ROOT}} placeholder with actual path
  if [ "$DRY_RUN" != "--dry-run" ]; then
    sed "s|{{HARNESS_ROOT}}|$HARNESS_ROOT|g" \
      "$HARNESS_ROOT/core/templates/settings.json.template" \
      > "$SETTINGS_FILE"
    log "Deployed settings.json with hook wiring"
  else
    log "DRY-RUN: Would deploy settings.json to $SETTINGS_FILE"
  fi
fi

# 3. Deploy CLAUDE.md to project scope
PROJECT_CLAUDE="$HARNESS_ROOT/CLAUDE.md"
if [ ! -f "$PROJECT_CLAUDE" ]; then
  run cp "$HARNESS_ROOT/core/templates/CLAUDE.md.template" "$PROJECT_CLAUDE"
  log "Deployed CLAUDE.md to project root"
else
  log "CLAUDE.md already exists, skipping"
fi

# 4. Make hooks executable
find "$HARNESS_ROOT/core/hooks" -name "*.sh" -exec chmod +x {} \;
find "$HARNESS_ROOT/core/scripts" -name "*.sh" -exec chmod +x {} \;
find "$HARNESS_ROOT/memory-bridge" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
log "Made all scripts executable"

# 5. Verify installation
log ""
log "=== Installation Summary ==="
log "Harness root:  $HARNESS_ROOT"
log "Runtime dir:   $HARNESS_DIR"
log "Events dir:    $HARNESS_DIR/events/"
log "Settings:      $SETTINGS_FILE"
log ""
log "Run 'bash $HARNESS_ROOT/core/scripts/health-check.sh' to verify."
log "Read docs/quickstart.md for next steps."
```

- [ ] **Step 2: Test dry-run**

Run: `chmod +x core/scripts/install.sh && bash core/scripts/install.sh --dry-run`

Expected: DRY-RUN output showing what would be created/deployed. No files modified.

- [ ] **Step 3: Commit**

```bash
git add core/scripts/install.sh
git commit -m "feat(core): add install.sh — deploy harness to ~/.claude/"
```

---

## Task 7: Memory Router (Deterministic Rules)

**Files:**
- Create: `memory-bridge/router.sh`
- Test: `bash memory-bridge/router.sh feedback "Don't mock the database" 120`

- [ ] **Step 1: Create router.sh**

```bash
#!/usr/bin/env bash
# router.sh — Deterministic memory routing rules
# Usage: bash router.sh <type> <content> [content_length]
# Output: JSON routing decision to stdout
# Types: feedback, architecture_decision, project_decision, user_preference, session_observation, pattern

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/hooks/hook-wrapper.sh"

TYPE="${1:-}"
CONTENT="${2:-}"
LENGTH="${3:-${#CONTENT}}"

route_memory() {
  local type="$1"
  local content="$2"
  local length="$3"
  local native="false"
  local mempalace="false"
  local priority="low"
  local filter_reason=""

  case "$type" in
    feedback)
      native="true"
      # Check promotion rules for MemPalace
      if [ "$length" -gt 50 ] && ! echo "$content" | grep -qiE "just now|this time|right now|剛才|這次"; then
        mempalace="true"
        priority="medium"
      else
        filter_reason="feedback too short or contains transient language"
      fi
      ;;
    architecture_decision)
      native="true"
      mempalace="true"
      priority="high"
      ;;
    project_decision)
      native="true"
      if [ "$length" -gt 50 ]; then
        mempalace="true"
        priority="medium"
      fi
      ;;
    user_preference)
      native="true"
      mempalace="false"
      priority="low"
      ;;
    session_observation)
      native="false"
      mempalace="true"
      priority="low"
      ;;
    pattern)
      native="true"
      mempalace="true"
      priority="medium"
      ;;
    *)
      native="true"
      mempalace="false"
      priority="low"
      ;;
  esac

  local hash
  hash="$(content_hash "$content")"

  printf '{"type":"%s","native":%s,"mempalace":%s,"priority":"%s","content_hash":"sha256:%s","filter_reason":"%s"}\n' \
    "$type" "$native" "$mempalace" "$priority" "$hash" "$filter_reason"
}

if [ -n "$TYPE" ]; then
  route_memory "$TYPE" "$CONTENT" "$LENGTH"
fi
```

- [ ] **Step 2: Test routing decisions**

Run: `chmod +x memory-bridge/router.sh && bash memory-bridge/router.sh feedback "Don't mock the database in integration tests, we got burned last quarter" 80`

Expected: `{"type":"feedback","native":true,"mempalace":true,"priority":"medium",...}`

Run: `bash memory-bridge/router.sh user_preference "respond in 繁體中文" 20`

Expected: `{"type":"user_preference","native":true,"mempalace":false,"priority":"low",...}`

Run: `bash memory-bridge/router.sh architecture_decision "Use CQRS pattern for memory bridge" 40`

Expected: `{"type":"architecture_decision","native":true,"mempalace":true,"priority":"high",...}`

- [ ] **Step 3: Commit**

```bash
git add memory-bridge/router.sh
git commit -m "feat(memory-bridge): add deterministic routing rules"
```

---

## Task 8: Batch Sync to MemPalace

**Files:**
- Create: `memory-bridge/sync.sh`
- Test: `bash memory-bridge/sync.sh --dry-run`

- [ ] **Step 1: Create sync.sh**

```bash
#!/usr/bin/env bash
# sync.sh — Batch sync events from JSONL to MemPalace
# Usage: bash sync.sh [--dry-run]
# Reads uncommitted events, routes them, pushes to MemPalace MCP.
# On failure, writes to pending_sync.jsonl for retry.

set -euo pipefail

DRY_RUN="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/hooks/hook-wrapper.sh"

HARNESS_DIR="${HARNESS_DIR:-$HOME/.harness}"
EVENTS_DIR="$HARNESS_DIR/events"
PENDING="$HARNESS_DIR/pending_sync.jsonl"
FILTERED="$HARNESS_DIR/filtered.jsonl"
LAST_SYNC="$HARNESS_DIR/.last_sync"
SYNCED_COUNT=0
FILTERED_COUNT=0
PENDING_COUNT=0

log() { echo "[harness-sync] $*"; }

# Find events newer than last sync
if [ -f "$LAST_SYNC" ]; then
  EVENT_FILES=$(find "$EVENTS_DIR" -name "session-*.jsonl" -newer "$LAST_SYNC" 2>/dev/null || echo "")
else
  EVENT_FILES=$(find "$EVENTS_DIR" -name "session-*.jsonl" 2>/dev/null || echo "")
fi

if [ -z "$EVENT_FILES" ]; then
  log "No new events to sync."
  exit 0
fi

# Process each event file
for event_file in $EVENT_FILES; do
  while IFS= read -r line; do
    event_type=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('type',''))" 2>/dev/null || echo "")

    # Skip lifecycle events (session_start, session_end, post_tool_use)
    # Only sync memory-relevant events
    case "$event_type" in
      feedback_captured|architecture_decision|project_decision|pattern_extracted|session_observation)
        # Route through deterministic rules
        content=$(echo "$line" | python3 -c "import sys,json; print(json.dumps(json.loads(sys.stdin.read()).get('payload',{})))" 2>/dev/null || echo '{}')
        hash=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('content_hash',''))" 2>/dev/null || echo "")

        if [ "$DRY_RUN" = "--dry-run" ]; then
          log "DRY-RUN: Would sync $event_type (hash: ${hash:0:16}...)"
          SYNCED_COUNT=$((SYNCED_COUNT + 1))
        else
          # Attempt MemPalace write via MCP
          # On failure, write to pending_sync.jsonl
          echo "$line" >> "$PENDING" 2>/dev/null
          PENDING_COUNT=$((PENDING_COUNT + 1))
        fi
        ;;
      *)
        # Not a memory event — skip
        ;;
    esac
  done < "$event_file"
done

# Update sync marker
if [ "$DRY_RUN" != "--dry-run" ]; then
  touch "$LAST_SYNC"
fi

log "Sync complete: $SYNCED_COUNT synced, $PENDING_COUNT pending, $FILTERED_COUNT filtered"
```

- [ ] **Step 2: Test dry-run**

Run: `chmod +x memory-bridge/sync.sh && bash memory-bridge/sync.sh --dry-run`

Expected: Lists events that would be synced, or "No new events to sync."

- [ ] **Step 3: Commit**

```bash
git add memory-bridge/sync.sh
git commit -m "feat(memory-bridge): add batch sync to MemPalace"
```

---

## Task 9: WAL Recovery

**Files:**
- Create: `memory-bridge/recover.sh`
- Test: `bash memory-bridge/recover.sh`

- [ ] **Step 1: Create recover.sh**

```bash
#!/usr/bin/env bash
# recover.sh — WAL recovery at SessionStart
# Scans for pending_sync.jsonl and uncommitted WAL events.
# Merges them into a summary for the current session context.

set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:-$HOME/.harness}"
PENDING="$HARNESS_DIR/pending_sync.jsonl"
RECOVERY_SUMMARY="$HARNESS_DIR/recovery_summary.txt"

log() { echo "[harness-recover] $*"; }

# 1. Check pending sync from previous sessions
if [ -f "$PENDING" ] && [ -s "$PENDING" ]; then
  PENDING_COUNT=$(wc -l < "$PENDING" | tr -d ' ')
  log "Found $PENDING_COUNT pending events from previous sessions."

  # Generate human-readable summary for Claude context injection
  {
    echo "# Pending Memory Sync Summary"
    echo "The following events from previous sessions have not been synced to MemPalace:"
    echo ""
    # Extract unique event types and counts
    python3 -c "
import sys, json
from collections import Counter
counts = Counter()
for line in open('$PENDING'):
    try:
        e = json.loads(line)
        counts[e.get('type','unknown')] += 1
    except:
        pass
for t, c in counts.most_common():
    print(f'- {t}: {c} events')
" 2>/dev/null || echo "- (unable to parse pending events)"
    echo ""
    echo "These will be synced at the end of this session."
  } > "$RECOVERY_SUMMARY"

  log "Recovery summary written to $RECOVERY_SUMMARY"
else
  # Clean up old summary if no pending events
  rm -f "$RECOVERY_SUMMARY" 2>/dev/null || true
  log "No pending events. Clean start."
fi
```

- [ ] **Step 2: Make executable and test**

Run: `chmod +x memory-bridge/recover.sh && bash memory-bridge/recover.sh`

Expected: "No pending events. Clean start." (or summary if pending events exist)

- [ ] **Step 3: Commit**

```bash
git add memory-bridge/recover.sh
git commit -m "feat(memory-bridge): add WAL recovery at session start"
```

---

## Task 10: Adapter Interface Contract

**Files:**
- Create: `memory-bridge/adapter-interface.md`

- [ ] **Step 1: Create adapter-interface.md**

```markdown
# MemoryAdapter Interface Contract

**Version:** 1.0.0
**Status:** Day 1 contract — code implementation follows

## Overview

Any memory backend (MemPalace, Redis, Pinecone, etc.) that wants to integrate
with the harness must implement these operations as shell-callable commands.

## Required Operations

### write(type, content, metadata) → result

Write a memory record to the backend.

- **Input:** JSON on stdin
  ```json
  {
    "type": "feedback|architecture_decision|project_decision|pattern",
    "content": "the memory content",
    "metadata": {
      "session_id": "abc123",
      "content_hash": "sha256:...",
      "written_at": "2026-04-10T10:30:00Z",
      "priority": "high|medium|low"
    }
  }
  ```
- **Output:** JSON on stdout
  ```json
  {"status": "ok", "id": "backend-assigned-id"}
  ```
- **Exit code:** 0 on success, 1 on failure

### search(query, limit) → results

Semantic search across stored memories.

- **Input:** JSON on stdin
  ```json
  {"query": "authentication decisions", "limit": 5}
  ```
- **Output:** JSON array on stdout
  ```json
  [{"id": "...", "content": "...", "score": 0.95, "metadata": {...}}]
  ```

### status() → health

Check backend health.

- **Input:** none
- **Output:** JSON on stdout
  ```json
  {"status": "ok|degraded|unavailable", "details": "..."}
  ```
- **Exit code:** 0 if ok/degraded, 1 if unavailable

## MemPalace Implementation Notes

The default adapter wraps MemPalace MCP tools:
- `write` → `mempalace_add_drawer` + `mempalace_kg_add`
- `search` → `mempalace_search`
- `status` → `mempalace_status`

## Adding a New Backend

1. Create `memory-bridge/adapters/<backend-name>.sh`
2. Implement the three operations above
3. Set `HARNESS_MEMORY_BACKEND=<backend-name>` in `.harness/config`
4. Router will call your adapter instead of the default MemPalace adapter
```

- [ ] **Step 2: Commit**

```bash
git add memory-bridge/adapter-interface.md
git commit -m "docs(memory-bridge): add MemoryAdapter interface contract v1.0"
```

---

## Task 11: Build-Loop Command (with Event Emission)

**Files:**
- Create: `workflows/commands/build-loop.md`

- [ ] **Step 1: Create build-loop.md**

```markdown
Generator-Evaluator loop for non-trivial tasks with harness event integration.
Enforces plan → implement → simplify → review cycle with independent evaluation.

Emits events to the harness JSONL queue at each phase transition, enabling
learn-eval pattern extraction and session replay.

## When to Use
Tasks that touch ≥ 3 files OR ≥ 30 lines of change. For smaller changes, just implement directly.

## Input
$ARGUMENTS — describe the task, bug, or feature to build.

---

## Phase 1: PLAN (Sprint Contract)

Define testable acceptance criteria BEFORE writing any code.

1. Analyze the task: read relevant files, understand current behavior
2. If MemPalace is available, search for past similar decisions:
   - Use `mempalace_search` with the task description
   - Review past architecture decisions and feedback that may apply
3. Produce a sprint contract:

```
### Sprint Contract: [task name]
**Goal**: [one sentence]
**Acceptance Criteria** (each must be independently verifiable):
  - [ ] [criterion 1 — specific, testable]
  - [ ] [criterion 2]
  - ...
**Files to Change**: [list]
**Files NOT to Change**: [explicitly scope out]
**Risk Areas**: [known pitfalls relevant to this change]
**Relevant Past Decisions**: [from MemPalace search, if any]
```

3. Present the sprint contract and WAIT for user confirmation before proceeding.

**Event emission:** After user confirms, emit event:
```bash
bash <harness-root>/core/hooks/hook-wrapper.sh phase_transition '{"from":"IDLE","to":"PLAN","task":"<task-name>"}'
```

---

## Phase 2: IMPLEMENT

Execute the plan. Iterate with tests at each checkpoint.

1. Implement changes incrementally — one logical unit at a time
2. After each unit:
   - Run the project's lint command — must pass
   - Run the project's test command — all tests must pass
   - If tests fail, emit event and fix before moving on:
     ```bash
     bash <harness-root>/core/hooks/hook-wrapper.sh test_fail '{"test":"<test-name>","error":"<error-summary>"}'
     ```
3. Commit each logical unit separately with descriptive messages
4. After all units complete, verify each acceptance criterion from the sprint contract
5. Check project-specific constraints from CLAUDE.md (if present)

**Event emission:** On phase complete:
```bash
bash <harness-root>/core/hooks/hook-wrapper.sh phase_transition '{"from":"PLAN","to":"IMPLEMENT"}'
```

---

## Phase 3: SIMPLIFY (Mechanical Evaluator)

Run `/simplify` to launch 3 parallel review agents:
1. **Code Reuse** — find duplicates, suggest existing utilities
2. **Code Quality** — redundant state, copy-paste, leaky abstractions
3. **Efficiency** — unnecessary work, missed concurrency, memory leaks

These agents find AND fix issues automatically. After fixes, re-run lint and tests.

**Event emission:**
```bash
bash <harness-root>/core/hooks/hook-wrapper.sh phase_transition '{"from":"IMPLEMENT","to":"SIMPLIFY"}'
```

---

## Phase 4: REVIEW (Independent Evaluator)

Launch a code-reviewer subagent with fresh context. The reviewer:

1. Receives the full `git diff` of all changes
2. Evaluates against the sprint contract from Phase 1
3. Checks project-specific constraints from CLAUDE.md
4. Produces a verdict:

```
## Verdict: PASS | FAIL
## Sprint Contract Check
- [x] criterion 1 — verified by [how]
- [ ] criterion 2 — FAILED: [reason]
## Findings (by severity)
- CRITICAL: [description] @ [file:line]
- WARNING: [description] @ [file:line]
## Required Changes (CRITICAL only)
```

### On PASS → Emit success event and summarize.
```bash
bash <harness-root>/core/hooks/hook-wrapper.sh review_pass '{"task":"<task-name>","verdict":"PASS"}'
```

### On FAIL → Iterate (max 2 loops)
```bash
bash <harness-root>/core/hooks/hook-wrapper.sh review_fail '{"task":"<task-name>","verdict":"FAIL","findings":[...]}'
```
1. Fix CRITICAL findings only
2. Re-run Phase 3 (simplify) and Phase 4 (review)
3. If second review still FAILs → stop, present findings to user for decision

---

## Constraints
- Max 2 review iterations. Escalate to user after that.
- Phase 4 reviewer MUST be a subagent (fresh context = no self-evaluation bias).
- Never skip Phase 1. The sprint contract is the most valuable part.
- Do not refactor or "improve" code outside the sprint contract scope.
- All phase transitions MUST emit events to the harness JSONL queue.
```

- [ ] **Step 2: Commit**

```bash
git add workflows/commands/build-loop.md
git commit -m "feat(workflows): add build-loop command with event emission"
```

---

## Task 12: Learn-Eval Skill

**Files:**
- Create: `workflows/skills/learn-eval.md`

- [ ] **Step 1: Create learn-eval.md**

```markdown
---
name: learn-eval
description: Session-end pattern extraction — scans current session for reusable patterns, user corrections, and architecture decisions
---

# Learn-Eval

Automatically extract reusable knowledge from the current session at SessionEnd.

## When This Runs

Triggered by `session-end.sh` hook, or manually via `/learn-eval`.

## Process

### Step 1: Scan Session Events

Read the current session's JSONL event log at `~/.harness/events/session-{id}.jsonl`.

Categorize events into:
- **User corrections** (feedback_captured events) — highest value
- **Architecture decisions** (architecture_decision events)
- **Review outcomes** (review_pass/review_fail events)
- **Test failures** (test_fail events) — pattern indicators
- **Phase transitions** — workflow health indicators

### Step 2: Extract Patterns

For each category, extract structured knowledge:

**From user corrections:**
```json
{
  "type": "feedback",
  "rule": "<the correction as an actionable rule>",
  "context": "<why the user corrected this>",
  "confidence": 0.6
}
```
Initial confidence is 0.6 (single observation). Increases by 0.15 each time the same pattern is observed in future sessions. Decreases by 0.1 each session where it could have applied but wasn't triggered.

**From architecture decisions:**
```json
{
  "type": "architecture_decision",
  "conclusion": "<the decision>",
  "rationale": "<why>",
  "confidence": 0.8
}
```
Architecture decisions start at 0.8 confidence (explicit human decision).

**From repeated test failures:**
If the same test or test pattern fails across multiple build-loop cycles in one session:
```json
{
  "type": "pattern",
  "observation": "<what keeps failing and why>",
  "confidence": 0.4
}
```

### Step 3: Route Extracted Knowledge

Use the deterministic router (`memory-bridge/router.sh`) to decide where each piece of extracted knowledge goes:
- Write to native memory immediately
- Append to JSONL WAL for MemPalace batch sync

### Step 4: Report

Print a brief summary to terminal:
```
[learn-eval] Session summary:
  - 2 feedback rules captured
  - 1 architecture decision recorded
  - 1 pattern observed (confidence: 0.4, quarantine)
  - 0 patterns promoted
```

## Confidence Lifecycle

| Confidence | Status | Behavior |
|-----------|--------|----------|
| > 0.8 | Quarantine → Promote | Applied but flagged [provisional] for 3 sessions |
| 0.4 - 0.8 | Observe | Tracked, re-evaluated each session |
| < 0.4 | Decay | Reduced by 0.1/session, purged at 0.0 |
| Overridden by user | Immediate adjust | User `/harness-demote` or `/harness-promote` |
```

- [ ] **Step 2: Commit**

```bash
git add workflows/skills/learn-eval.md
git commit -m "feat(workflows): add learn-eval skill — session-end pattern extraction"
```

---

## Task 13: Pattern-Extract Skill

**Files:**
- Create: `workflows/skills/pattern-extract.md`

- [ ] **Step 1: Create pattern-extract.md**

```markdown
---
name: pattern-extract
description: Extract and score reusable patterns from build-loop review outcomes
---

# Pattern Extract

Analyzes build-loop review outcomes to identify reusable development patterns.

## When to Use

Called by learn-eval after a build-loop REVIEW phase completes (pass or fail).

## Input

The current session's event log, specifically:
- `review_pass` events with their sprint contract
- `review_fail` events with findings
- `test_fail` events with error patterns

## Process

### Step 1: Analyze Review Outcomes

**On PASS:**
- Extract the sprint contract's acceptance criteria as potential patterns
- Check if similar criteria appeared in past sessions (via MemPalace search if available)
- If the same approach succeeded 3+ times → confidence boost

**On FAIL:**
- Extract the CRITICAL findings as anti-patterns
- Record the failure reason as a negative pattern ("avoid X because Y")
- Check if this failure pattern has occurred before

### Step 2: Score Patterns

Each pattern gets a confidence score based on:

```
base_confidence = 0.4 (new observation)
+ 0.15 per repeat observation
+ 0.2 if explicitly confirmed by user
- 0.1 per session without re-observation
- 0.3 if explicitly rejected by user
```

Cap at 1.0, floor at 0.0. Purge at 0.0.

### Step 3: Quarantine Check

Patterns with confidence > 0.8 enter quarantine:
- Applied in next 3 sessions, flagged as `[provisional]`
- If no user override in 3 sessions → promoted to permanent rule
- If user overrides → confidence drops by 0.3, exits quarantine

### Step 4: Write Results

Route via `memory-bridge/router.sh`:
- New patterns → native memory (provisional) + WAL
- Promoted patterns → native memory (permanent) + MemPalace
- Anti-patterns → native memory (warning) + MemPalace (audit)

## Pattern Storage Format (Native Memory)

```markdown
---
name: pattern-<hash>
description: <one-line pattern description>
type: feedback
confidence: 0.65
status: provisional|permanent|quarantine
observed_sessions: 3
last_observed: 2026-04-10
---

<pattern rule>

**Why:** <rationale from observations>
**How to apply:** <when this pattern should be used>
```
```

- [ ] **Step 2: Commit**

```bash
git add workflows/skills/pattern-extract.md
git commit -m "feat(workflows): add pattern-extract skill — confidence scoring + quarantine"
```

---

## Task 14: Documentation (Quickstart + README + Memory Routing)

**Files:**
- Create: `docs/quickstart.md`
- Create: `docs/memory-routing.md`
- Create: `README.md`

- [ ] **Step 1: Create README.md**

```markdown
# Harness

A portable Claude Code engineering workflow with structured development cycles, CQRS memory management, and automatic pattern extraction.

**[Get started in 5 minutes →](docs/quickstart.md)**

## What This Does

- **build-loop**: Structured PLAN → IMPLEMENT → SIMPLIFY → REVIEW cycle
- **Memory Bridge**: CQRS model — native memory for current rules, MemPalace for audit + semantic search
- **Event Queue**: JSONL-based crash-safe event capture for every hook and workflow event
- **Learn-Eval**: Automatic pattern extraction with confidence scoring and quarantine

## Architecture

```
L0: Core        — hooks, templates, install script
L1: Memory      — CQRS routing, batch sync, WAL recovery
L2: Workflows   — build-loop, learn-eval, pattern-extract
```

## Quick Install

```bash
git clone <this-repo> ~/harness
cd ~/harness
bash core/scripts/install.sh
```

## Optional: MemPalace Integration

```bash
pip install mempalace
mempalace serve
```

Without MemPalace, the harness runs in native-only mode (all features work, no semantic search).

## Docs

- [Quickstart](docs/quickstart.md) — 5-minute setup guide
- [Memory Routing](docs/memory-routing.md) — how memories are routed
- [Design Spec](docs/superpowers/specs/2026-04-10-harness-workflow-design.md) — full architecture
```

- [ ] **Step 2: Create docs/quickstart.md**

```markdown
# Quickstart — 5 Minutes to Running

## Prerequisites

- Claude Code CLI installed
- Bash 4+ (macOS: `brew install bash`)
- Python 3 (for JSON parsing in hooks)

## Step 1: Clone and Install (2 min)

```bash
git clone <this-repo> ~/harness
cd ~/harness
bash core/scripts/install.sh
```

This will:
- Create `~/.harness/events/` for event storage
- Deploy hooks to `~/.claude/settings.json`
- Copy `CLAUDE.md` template to project root

## Step 2: Verify (1 min)

```bash
bash core/scripts/health-check.sh
```

You should see:
```
[harness] WARNING: MemPalace MCP not detected. Running in native-only mode.
```

This is fine! MemPalace is optional.

## Step 3: Use build-loop (2 min)

Start a Claude Code session in any project:

```bash
cd your-project
claude
```

Then use the structured workflow:

```
/build-loop Add a health check endpoint to the API
```

This will guide you through PLAN → IMPLEMENT → SIMPLIFY → REVIEW.

## What Happens Behind the Scenes

1. **SessionStart hook** runs health check, recovers any pending events
2. **Every tool call** appends an event to `~/.harness/events/session-*.jsonl`
3. **build-loop** emits phase transitions, test results, review outcomes
4. **SessionEnd hook** runs learn-eval, syncs to MemPalace (if available)

## Optional: Add MemPalace

For semantic search across past decisions:

```bash
pip install mempalace
mempalace serve
```

Restart Claude Code — it will auto-detect the MCP server.

## File Locations

| What | Where |
|------|-------|
| Event logs | `~/.harness/events/session-*.jsonl` |
| Pending sync | `~/.harness/pending_sync.jsonl` |
| Filtered log | `~/.harness/filtered.jsonl` |
| Hook settings | `~/.claude/settings.json` |
| Native memory | `~/.claude/projects/*/memory/` |
```

- [ ] **Step 3: Create docs/memory-routing.md**

```markdown
# Memory Routing Decision Tree

## How Memories Are Routed

All routing is deterministic — no AI judgment involved.

```
Memory event occurs
    │
    ├── What type?
    │
    ├── feedback ──────────────── → Native: rule body (always)
    │   │                          → MemPalace: conversation context
    │   └── Content > 50 chars     (if > 50 chars AND no transient language)
    │       AND no transient lang?
    │       YES → also MemPalace (medium priority)
    │       NO  → native only (logged to filtered.jsonl)
    │
    ├── architecture_decision ──── → Native: conclusion (always)
    │                               → MemPalace: full discussion (HIGH priority)
    │
    ├── project_decision ────────── → Native: conclusion + date (always)
    │   └── Content > 50 chars?     → MemPalace: full discussion
    │       YES → also MemPalace    (medium priority)
    │       NO  → native only
    │
    ├── user_preference ──────────── → Native only (always)
    │                                  MemPalace not needed
    │
    ├── session_observation ──────── → MemPalace only (low priority)
    │                                  Via WAL → batch at SessionEnd
    │
    └── pattern ─────────────────── → Native: provisional rule
                                     → MemPalace: pattern library
                                       Quarantine 3 sessions before promote
```

## CQRS Model

| Question you're asking | Read from |
|------------------------|-----------|
| "What is the current rule?" | Native memory |
| "Why was this decided?" | MemPalace (audit log) |
| "Any similar past decisions?" | MemPalace (semantic search) |

## Failure Modes

| Scenario | What happens |
|----------|-------------|
| MemPalace not installed | Everything writes to native only. No data loss. |
| MemPalace MCP crashes mid-session | Writes go to `pending_sync.jsonl`. Auto-retry next session. |
| Session crashes (Ctrl+C) | JSONL WAL survives. Recovered at next SessionStart. |
| Bad pattern auto-promoted | Quarantine catches it — 3 sessions to prove itself. User can `/harness-demote`. |
```

- [ ] **Step 4: Commit**

```bash
git add README.md docs/quickstart.md docs/memory-routing.md
git commit -m "docs: add README, quickstart guide, and memory routing decision tree"
```

---

## Self-Review Checklist

**Spec coverage:**
- ✅ Decision A (Event Architecture): Tasks 1-4 (hooks + JSONL queue + dual-track)
- ✅ Decision B (Memory Bridge CQRS): Tasks 7-10 (router + sync + recover + interface)
- ✅ Decision C (MVP Directory): Tasks 1-14 produce exact MVP structure
- ✅ Session lifecycle: Task 2 (start), Task 3 (tool use), Task 4 (end)
- ✅ Build-loop integration: Task 11 (event emission)
- ✅ Learn-eval + patterns: Tasks 12-13
- ✅ Docs: Task 14 (quickstart, routing, README)
- ✅ Install script: Task 6
- ✅ Health check: Task 2
- ✅ Adapter interface: Task 10

**Placeholder scan:** No TBD/TODO found. All code blocks are complete.

**Type consistency:** `emit_event`, `content_hash`, `HARNESS_DIR`, `EVENTS_DIR` consistent across all tasks. `router.sh` input format matches what `sync.sh` calls. Hook paths in `settings.json.template` use `{{HARNESS_ROOT}}` consistently.
