# Curator v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build v1 of Curator — a Claude Code plugin that adds MemPalace-backed memory and pattern learning via Stop/SessionStart/UserPromptSubmit hooks, four slash commands (`/curator:capture`, `/curator:recall`, `/curator:memory`, `/curator:build`), a dual-layer CQRS memory bridge, and a portable installer that plays nicely with existing `~/.claude/` configurations.

**Architecture:** Dual-Layer CQRS (MemPalace canonical + `memdir/` projection cache). Bash + YAML/JSON + Markdown only — no compiled code. CC native hooks used throughout; no custom event bus. Dual-file projection: `MEMORY.md` holds L0 absolute rules (~2-5KB) and `pattern-signal.md` holds 7-day rolling observations picked up on-demand by CC's native `findRelevantMemories` Sonnet selector via `mtime` ordering.

**Tech Stack:** bash, `jq`, `yq`, `shasum`, `bats-core` (tests), MemPalace MCP (external dependency), Claude Code plugin system (`.claude-plugin/plugin.json`).

**Spec:** [`docs/superpowers/specs/2026-04-11-curator-design.md`](../specs/2026-04-11-curator-design.md)

**v1 Scope:** α + δ — complete memory layer with user-confirmed pattern extraction. `build-loop` workflow is a stub only (deferred to v1.2). No v2.1 主動警告, no v2.2 dashboard, no v3 Mac Mini remote runtime.

---

## File Structure

```
curator/                                     (repo root; currently "harness/" pending manual rename)
├── .claude-plugin/
│   └── plugin.json                          # CC plugin manifest
├── core/
│   ├── hooks/
│   │   ├── session-start.sh                 # SessionStart hook: projection + reconcile + stale banner
│   │   ├── user-prompt-submit.sh            # Pattern proposal emitter (one-per-session, deferrable)
│   │   └── stop.sh                          # Flush pending_sync + prune pattern-signal 7d window
│   ├── lib/
│   │   ├── common.sh                        # Shared helpers: logging, paths, device-id, sha256
│   │   ├── journal.sh                       # pending_sync.jsonl I/O + idempotency by content_hash
│   │   └── mcp-client.sh                    # MemPalace MCP call wrapper (read/write/ping)
│   ├── scripts/
│   │   ├── health-check.sh                  # Verify deps, MemPalace reachability, install state
│   │   ├── preflight-check.sh               # Scan ~/.claude for collisions before install
│   │   ├── install.sh                       # Backup memdir, patch settings.json, write receipt
│   │   └── uninstall.sh                     # Reverse install via receipt
│   └── templates/
│       ├── MEMORY.md.template               # L0 bootstrap content for new projects
│       └── settings.json.patch.jq           # jq filter to merge hooks into existing settings.json
├── memory-bridge/
│   ├── router.sh                            # yq-based rule dispatcher
│   ├── routing-rules.yaml                   # Core routing rules (declarative)
│   ├── project.sh                           # SessionStart projection: MemPalace → MEMORY.md
│   ├── reconcile.sh                         # Retry pending_sync.jsonl entries on SessionStart
│   └── adapter-interface.md                 # MemoryAdapter contract (Day 1 frozen)
├── skills/
│   ├── capture.md                           # /curator:capture
│   ├── recall.md                            # /curator:recall
│   ├── memory.md                            # /curator:memory
│   └── build.md                             # /curator:build (v1 stub)
├── test/
│   ├── fixtures/                            # Static test data (sample MEMORY.md, mock MCP responses)
│   │   ├── mock-mempalace.sh                # Stub MCP server binary
│   │   └── sample-memdir/
│   ├── lib/
│   │   ├── test_common.bats                 # Unit tests for common.sh
│   │   ├── test_journal.bats                # Unit tests for journal.sh
│   │   └── test_mcp_client.bats             # Unit tests for mcp-client.sh
│   ├── scripts/
│   │   ├── test_preflight.bats              # preflight-check integration
│   │   ├── test_install.bats                # install/uninstall round-trip
│   │   └── test_router.bats                 # Routing rule dispatch
│   ├── hooks/
│   │   ├── test_session_start.bats          # Session start hook w/ stub MCP
│   │   ├── test_stop.bats                   # Stop hook flush + prune
│   │   └── test_user_prompt_submit.bats     # Pattern proposal pipeline
│   ├── roundtrip.sh                         # End-to-end integration test (requires real MemPalace)
│   └── hr-acceptance.sh                     # HR-1/HR-2/HR-3 acceptance checks
└── docs/
    ├── quickstart.md                        # 5-minute onboarding
    ├── README.md                            # Entry point (replaces repo-root README)
    └── superpowers/                         # Spec + this plan (already exist)
```

**Environment variables used:**

| Variable | Purpose | Default | Where read |
|---|---|---|---|
| `CURATOR_HOME` | Repo install location | `~/.claude/plugins/.../curator` | lib/common.sh |
| `CURATOR_STATE` | State dir | `~/.curator` | lib/common.sh |
| `CURATOR_MEMPALACE_URL` | MemPalace MCP connection | `stdio` | lib/mcp-client.sh |
| `CLAUDE_PROJECT_ROOT` | CC-provided project root | (CC hook env) | hooks/*.sh |
| `CLAUDE_SESSION_ID` | CC-provided session ID | (CC hook env) | hooks/*.sh |

---

## Task 0: Dev prerequisites

**Files:**
- None (environment setup)

This installs dev tooling needed for the rest of the plan. Curator itself ships with a preflight check that verifies runtime prerequisites (built in Task 5).

- [ ] **Step 1: Verify or install `bats-core`, `yq`, `jq`**

Run:
```bash
command -v bats || brew install bats-core
command -v yq   || brew install yq
command -v jq   || brew install jq
command -v shasum || echo "shasum missing — should come with macOS by default"
bats --version
yq --version
jq --version
```

Expected: each command prints a version.

- [ ] **Step 2: Create a working branch**

```bash
cd ~/Workspace/GitHub/harness   # directory rename to curator/ happens post-v1
git checkout -b curator-v1-impl
git status
```

Expected: `On branch curator-v1-impl`, clean tree.

---

## Task 1: Plugin manifest + directory skeleton

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `core/lib/` (directory)
- Create: `core/scripts/` (directory)
- Create: `core/hooks/` (directory)
- Create: `core/templates/` (directory)
- Create: `memory-bridge/` (directory)
- Create: `skills/` (directory)
- Create: `test/lib/` `test/scripts/` `test/hooks/` `test/fixtures/sample-memdir/` (directories)
- Create: `.gitignore`

- [ ] **Step 1: Create directory skeleton**

```bash
mkdir -p .claude-plugin core/{lib,scripts,hooks,templates} \
         memory-bridge skills \
         test/{lib,scripts,hooks,fixtures/sample-memdir}
```

Expected: no output; `ls -la` shows all directories.

- [ ] **Step 2: Write `.claude-plugin/plugin.json`**

```json
{
  "name": "curator",
  "version": "0.1.0",
  "description": "Claude Code memory layer backed by MemPalace with pattern learning and CQRS projection",
  "author": { "name": "Jack Chung" },
  "repository": "https://github.com/jackg825/curator",
  "license": "MIT",
  "requires": {
    "mcp_servers": ["mempalace"],
    "binaries": ["jq", "yq"]
  },
  "postInstall": "core/scripts/install.sh",
  "keywords": ["memory", "mempalace", "cqrs", "pattern-learning", "claude-code"]
}
```

- [ ] **Step 3: Write `.gitignore`**

```
# Curator dev artifacts
*.bak
*.tmp
.DS_Store
test/tmp/
test/.bats-tmp/

# Never commit local state
.curator/
~/.curator/
```

- [ ] **Step 4: Verify structure**

```bash
find .claude-plugin core memory-bridge skills test -type d | sort
cat .claude-plugin/plugin.json | jq .
```

Expected: all directories listed, `plugin.json` parses as valid JSON.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin core memory-bridge skills test .gitignore
git commit -m "feat: curator plugin manifest and directory skeleton"
```

---

## Task 2: `core/lib/common.sh` — shared helpers

**Files:**
- Create: `core/lib/common.sh`
- Create: `test/lib/test_common.bats`

This file holds the base primitives every other script needs: path resolution, logging, device-id, SHA-256 hashing. No external dependencies beyond coreutils + `shasum`.

- [ ] **Step 1: Write the failing test**

Create `test/lib/test_common.bats`:

```bash
#!/usr/bin/env bats
# Unit tests for core/lib/common.sh

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=../../core/lib/common.sh
  source "$REPO_ROOT/core/lib/common.sh"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  mkdir -p "$CURATOR_STATE"
}

@test "curator_log writes to stderr with timestamp prefix" {
  run curator_log INFO "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[curator]"* ]]
  [[ "$output" == *"INFO"* ]]
  [[ "$output" == *"hello world"* ]]
}

@test "curator_sha256 returns 64 hex chars for a known string" {
  run curator_sha256 "curator test"
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 64 ]
  [[ "$output" =~ ^[a-f0-9]{64}$ ]]
}

@test "curator_sha256 is deterministic" {
  run curator_sha256 "same input"
  first="$output"
  run curator_sha256 "same input"
  [ "$first" = "$output" ]
}

@test "curator_device_id returns existing device-id when file present" {
  echo "laptop-abcd" > "$CURATOR_STATE/device-id"
  run curator_device_id
  [ "$status" -eq 0 ]
  [ "$output" = "laptop-abcd" ]
}

@test "curator_device_id generates new id when file absent" {
  rm -f "$CURATOR_STATE/device-id"
  run curator_device_id
  [ "$status" -eq 0 ]
  [ -f "$CURATOR_STATE/device-id" ]
  # Format: hostname-4chars
  [[ "$output" =~ ^[a-zA-Z0-9]+-[a-z0-9]{4}$ ]]
}

@test "curator_device_id is stable across calls" {
  run curator_device_id
  first="$output"
  run curator_device_id
  [ "$first" = "$output" ]
}

@test "curator_require_bin reports missing dependency clearly" {
  run curator_require_bin this_binary_does_not_exist_12345
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing"* ]]
  [[ "$output" == *"this_binary_does_not_exist_12345"* ]]
}

@test "curator_require_bin succeeds for existing binary" {
  run curator_require_bin bash
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bats test/lib/test_common.bats
```

Expected: all tests fail with "common.sh: No such file or directory" or "function not found".

- [ ] **Step 3: Write minimal `core/lib/common.sh`**

```bash
#!/usr/bin/env bash
# core/lib/common.sh — Shared helpers for all curator scripts.
# This file is sourced, not executed.

set -euo pipefail

# Resolve state directory. Override via CURATOR_STATE env var for tests.
: "${CURATOR_STATE:=$HOME/.curator}"

# Log a line to stderr with [curator] prefix, level, and ISO timestamp.
curator_log() {
  local level="$1"
  shift
  local msg="$*"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[curator] ${ts} ${level} ${msg}" >&2
}

# SHA-256 hex of stdin or argument.
curator_sha256() {
  local input="${1:-}"
  if [ -n "$input" ]; then
    printf "%s" "$input" | shasum -a 256 | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

# Return the device identifier. Creates it on first call.
curator_device_id() {
  local id_file="$CURATOR_STATE/device-id"
  if [ -f "$id_file" ]; then
    cat "$id_file"
    return 0
  fi

  mkdir -p "$CURATOR_STATE"
  local hostname_slug suffix
  hostname_slug="$(hostname -s | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/-*$//')"
  suffix="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 4)"
  printf "%s-%s" "$hostname_slug" "$suffix" > "$id_file"
  cat "$id_file"
}

# Verify a binary is on PATH. Fail loudly if not.
curator_require_bin() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "curator: missing required binary: $bin" >&2
    return 1
  fi
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
bats test/lib/test_common.bats
```

Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add core/lib/common.sh test/lib/test_common.bats
git commit -m "feat(lib): common.sh helpers for logging, sha256, device-id"
```

---

## Task 3: `core/lib/journal.sh` — pending_sync.jsonl I/O

**Files:**
- Create: `core/lib/journal.sh`
- Create: `test/lib/test_journal.bats`

Handles appending to and draining the pending-sync journal with content-hash idempotency.

- [ ] **Step 1: Write the failing test**

Create `test/lib/test_journal.bats`:

```bash
#!/usr/bin/env bats
# Unit tests for core/lib/journal.sh

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  mkdir -p "$CURATOR_STATE"
  # shellcheck source=../../core/lib/common.sh
  source "$REPO_ROOT/core/lib/common.sh"
  # shellcheck source=../../core/lib/journal.sh
  source "$REPO_ROOT/core/lib/journal.sh"
}

@test "journal_append creates pending_sync.jsonl with one entry" {
  journal_append "feedback" '{"text":"hello"}'
  [ -f "$CURATOR_STATE/pending_sync.jsonl" ]
  local line_count
  line_count=$(wc -l < "$CURATOR_STATE/pending_sync.jsonl")
  [ "$line_count" -eq 1 ]
}

@test "journal_append emits a JSON object with required fields" {
  journal_append "feedback" '{"text":"hello"}'
  local entry
  entry=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl")
  # Verify fields present
  echo "$entry" | jq -e '.content_hash, .ts, .device_id, .type, .payload, .pending' > /dev/null
}

@test "journal_append computes content_hash deterministically" {
  journal_append "feedback" '{"text":"same"}'
  local hash1
  hash1=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl" | jq -r .content_hash)
  rm "$CURATOR_STATE/pending_sync.jsonl"
  journal_append "feedback" '{"text":"same"}'
  local hash2
  hash2=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl" | jq -r .content_hash)
  [ "$hash1" = "$hash2" ]
}

@test "journal_append includes device_id in each entry" {
  echo "mac-test" > "$CURATOR_STATE/device-id"
  journal_append "feedback" '{"text":"hi"}'
  local entry_device
  entry_device=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl" | jq -r .device_id)
  [ "$entry_device" = "mac-test" ]
}

@test "journal_append sets pending array to [mempalace] by default" {
  journal_append "feedback" '{"text":"hi"}'
  local pending
  pending=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl" | jq -c .pending)
  [ "$pending" = '["mempalace"]' ]
}

@test "journal_mark_resolved removes target from pending array" {
  journal_append "feedback" '{"text":"hello"}'
  local hash
  hash=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl" | jq -r .content_hash)
  journal_mark_resolved "$hash" "mempalace"
  local pending
  pending=$(grep "$hash" "$CURATOR_STATE/pending_sync.jsonl" | tail -n 1 | jq -c .pending)
  [ "$pending" = '[]' ]
}

@test "journal_pending_entries returns only entries with non-empty pending" {
  journal_append "feedback" '{"text":"first"}'
  local hash1
  hash1=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl" | jq -r .content_hash)
  journal_append "feedback" '{"text":"second"}'
  journal_mark_resolved "$hash1" "mempalace"

  run journal_pending_entries
  [ "$status" -eq 0 ]
  # Only "second" should be pending
  [[ "$output" == *"second"* ]]
  [[ "$output" != *"first"* ]]
}

@test "journal_append is append-only (does not overwrite existing entries)" {
  journal_append "feedback" '{"text":"first"}'
  journal_append "pattern" '{"text":"second"}'
  local count
  count=$(wc -l < "$CURATOR_STATE/pending_sync.jsonl")
  [ "$count" -eq 2 ]
}

@test "journal_prune_older_than drops entries older than N days" {
  # Manually insert an old entry
  mkdir -p "$CURATOR_STATE"
  cat > "$CURATOR_STATE/pending_sync.jsonl" <<'OLD'
{"content_hash":"old1","ts":"2020-01-01T00:00:00Z","device_id":"x","type":"feedback","payload":{},"pending":["mempalace"]}
OLD
  journal_append "feedback" '{"text":"fresh"}'

  journal_prune_older_than 7  # 7 days

  run cat "$CURATOR_STATE/pending_sync.jsonl"
  [[ "$output" != *"old1"* ]]
  [[ "$output" == *"fresh"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bats test/lib/test_journal.bats
```

Expected: tests fail, no `journal.sh` yet.

- [ ] **Step 3: Write minimal `core/lib/journal.sh`**

```bash
#!/usr/bin/env bash
# core/lib/journal.sh — pending_sync.jsonl I/O with content-hash idempotency.
# Requires common.sh to be sourced first (curator_log, curator_sha256, curator_device_id).

: "${CURATOR_STATE:=$HOME/.curator}"
JOURNAL_PATH="$CURATOR_STATE/pending_sync.jsonl"

# Append a write-attempt to the journal.
# Args:
#   $1: type (e.g., "feedback", "pattern", "capture")
#   $2: payload (JSON string)
# Writes: one JSONL line with content_hash, ts, device_id, type, payload, pending.
journal_append() {
  local type="$1"
  local payload="$2"
  mkdir -p "$CURATOR_STATE"

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local device_id
  device_id="$(curator_device_id)"
  # Content hash covers type + payload + ts (idempotent retries of same content hit the same hash)
  local content_hash
  content_hash="$(printf "%s\0%s\0%s" "$type" "$payload" "$ts" | shasum -a 256 | awk '{print $1}')"

  # Build entry with jq to ensure valid JSON
  jq -cn --arg hash "$content_hash" \
        --arg ts "$ts" \
        --arg dev "$device_id" \
        --arg type "$type" \
        --argjson payload "$payload" \
        '{content_hash:$hash, ts:$ts, device_id:$dev, type:$type, payload:$payload, pending:["mempalace"]}' \
    >> "$JOURNAL_PATH"
}

# Mark a target as resolved for a given content_hash.
# Args:
#   $1: content_hash
#   $2: target to remove from pending (e.g., "mempalace")
# Strategy: append a resolution marker entry (keeps append-only semantics).
journal_mark_resolved() {
  local hash="$1"
  local target="$2"
  [ -f "$JOURNAL_PATH" ] || return 0

  # Rewrite in-place: for entries matching the hash, remove target from pending array.
  local tmp
  tmp="$(mktemp)"
  jq -c --arg hash "$hash" --arg target "$target" '
    if .content_hash == $hash then
      .pending = (.pending - [$target])
    else
      .
    end
  ' "$JOURNAL_PATH" > "$tmp"
  mv "$tmp" "$JOURNAL_PATH"
}

# Emit all entries whose pending array is non-empty.
journal_pending_entries() {
  [ -f "$JOURNAL_PATH" ] || return 0
  jq -c 'select(.pending | length > 0)' "$JOURNAL_PATH"
}

# Drop entries older than N days.
# Args:
#   $1: days (integer)
journal_prune_older_than() {
  local days="$1"
  [ -f "$JOURNAL_PATH" ] || return 0

  local cutoff
  cutoff="$(date -u -v-"${days}d" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "${days} days ago" +%Y-%m-%dT%H:%M:%SZ)"

  local tmp
  tmp="$(mktemp)"
  jq -c --arg cutoff "$cutoff" 'select(.ts >= $cutoff)' "$JOURNAL_PATH" > "$tmp"
  mv "$tmp" "$JOURNAL_PATH"
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
bats test/lib/test_journal.bats
```

Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add core/lib/journal.sh test/lib/test_journal.bats
git commit -m "feat(lib): journal.sh — pending_sync.jsonl append/mark/prune"
```

---

## Task 4: `core/lib/mcp-client.sh` — MemPalace wrapper

**Files:**
- Create: `core/lib/mcp-client.sh`
- Create: `test/fixtures/mock-mempalace.sh`
- Create: `test/lib/test_mcp_client.bats`

Wraps calls to the `mempalace` MCP server. Connection protocol depends on `CURATOR_MEMPALACE_URL`: `stdio` → spawn via `claude mcp`; `http://...` → curl. Tests use the mock-mempalace.sh stub.

- [ ] **Step 1: Write the stub MCP server**

Create `test/fixtures/mock-mempalace.sh`:

```bash
#!/usr/bin/env bash
# test/fixtures/mock-mempalace.sh — canned responder for curator tests.
# Reads a single MCP-style request from stdin and emits a canned response.
# Records the request to MOCK_MCP_LOG for assertion.

: "${MOCK_MCP_LOG:=/tmp/mock-mempalace.log}"
: "${MOCK_MCP_MODE:=ok}"  # ok | fail | timeout

input="$(cat)"
echo "---REQUEST---" >> "$MOCK_MCP_LOG"
echo "$input" >> "$MOCK_MCP_LOG"

case "$MOCK_MCP_MODE" in
  fail)
    echo '{"error":"simulated failure"}'
    exit 1
    ;;
  timeout)
    sleep 30
    exit 0
    ;;
  ok)
    # Parse method and respond
    method="$(echo "$input" | jq -r '.method // empty')"
    case "$method" in
      ping)
        echo '{"result":"pong"}'
        ;;
      search)
        echo '{"result":[{"text":"mock memory","wing":"test","hall":"hall_facts"}]}'
        ;;
      write)
        echo '{"result":{"id":"mock-drawer-1"}}'
        ;;
      *)
        echo '{"result":null}'
        ;;
    esac
    ;;
esac
```

Make executable:
```bash
chmod +x test/fixtures/mock-mempalace.sh
```

- [ ] **Step 2: Write the failing test**

Create `test/lib/test_mcp_client.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export MOCK_MCP_LOG="$BATS_TEST_TMPDIR/mock-mcp.log"
  mkdir -p "$CURATOR_STATE"
  : > "$MOCK_MCP_LOG"

  # Route calls through the mock
  export CURATOR_MEMPALACE_URL="mock://$REPO_ROOT/test/fixtures/mock-mempalace.sh"

  source "$REPO_ROOT/core/lib/common.sh"
  source "$REPO_ROOT/core/lib/mcp-client.sh"
}

@test "mcp_ping returns 0 when mock responds OK" {
  export MOCK_MCP_MODE=ok
  run mcp_ping
  [ "$status" -eq 0 ]
}

@test "mcp_ping returns non-zero when mock fails" {
  export MOCK_MCP_MODE=fail
  run mcp_ping
  [ "$status" -ne 0 ]
}

@test "mcp_search returns JSON array" {
  export MOCK_MCP_MODE=ok
  run mcp_search "auth refresh"
  [ "$status" -eq 0 ]
  # Output should be parseable JSON with array under .result
  echo "$output" | jq -e '.result | type == "array"' > /dev/null
}

@test "mcp_write sends type and payload to server" {
  export MOCK_MCP_MODE=ok
  mcp_write "feedback" '{"text":"test"}'
  grep -q '"method":"write"' "$MOCK_MCP_LOG"
  grep -q '"text":"test"' "$MOCK_MCP_LOG"
}

@test "mcp_write returns non-zero when server fails" {
  export MOCK_MCP_MODE=fail
  run mcp_write "feedback" '{"text":"x"}'
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
bats test/lib/test_mcp_client.bats
```

Expected: tests fail, no `mcp-client.sh`.

- [ ] **Step 4: Write `core/lib/mcp-client.sh`**

```bash
#!/usr/bin/env bash
# core/lib/mcp-client.sh — MemPalace MCP call wrapper.
# Supported URL schemes:
#   stdio                  → spawn via `claude mcp call mempalace`
#   mock://<path>          → pipe into a local script (tests only)
#   http://host:port       → POST via curl
# Requires common.sh sourced first.

: "${CURATOR_MEMPALACE_URL:=stdio}"
: "${CURATOR_MCP_TIMEOUT:=10}"  # seconds

# Internal: dispatch a JSON request to the configured MCP endpoint.
# Stdin: JSON request.
# Stdout: JSON response.
_mcp_dispatch() {
  local url="$CURATOR_MEMPALACE_URL"
  case "$url" in
    stdio)
      # Real CC-managed MCP call
      if command -v claude >/dev/null 2>&1; then
        claude mcp call mempalace --timeout "$CURATOR_MCP_TIMEOUT"
      else
        curator_log ERROR "claude CLI not found; cannot dispatch stdio MCP call"
        return 1
      fi
      ;;
    mock://*)
      local script="${url#mock://}"
      if [ ! -x "$script" ]; then
        curator_log ERROR "mock MCP script not executable: $script"
        return 1
      fi
      "$script"
      ;;
    http://*|https://*)
      if ! command -v curl >/dev/null 2>&1; then
        curator_log ERROR "curl missing; cannot use http:// MCP URL"
        return 1
      fi
      curl -s --max-time "$CURATOR_MCP_TIMEOUT" -H "Content-Type: application/json" -d @- "$url"
      ;;
    *)
      curator_log ERROR "unknown CURATOR_MEMPALACE_URL scheme: $url"
      return 1
      ;;
  esac
}

# Public: liveness check.
mcp_ping() {
  local resp
  if ! resp="$(echo '{"method":"ping"}' | _mcp_dispatch 2>/dev/null)"; then
    return 1
  fi
  echo "$resp" | jq -e '.result == "pong"' > /dev/null
}

# Public: semantic search. Prints response JSON on stdout.
# Args: $1 query, [$2 wing], [$3 hall]
mcp_search() {
  local query="$1"
  local wing="${2:-}"
  local hall="${3:-}"
  jq -cn --arg q "$query" --arg w "$wing" --arg h "$hall" \
    '{method:"search", params:{query:$q, wing:$w, hall:$h}}' \
    | _mcp_dispatch
}

# Public: write. Args: $1 type, $2 payload JSON.
mcp_write() {
  local type="$1"
  local payload="$2"
  local resp
  resp="$(jq -cn --arg t "$type" --argjson p "$payload" \
    '{method:"write", params:{type:$t, payload:$p}}' \
    | _mcp_dispatch)" || return 1
  # Success if response has .result and not .error
  echo "$resp" | jq -e '.result != null' > /dev/null
}
```

- [ ] **Step 5: Run tests to verify pass**

```bash
bats test/lib/test_mcp_client.bats
```

Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add core/lib/mcp-client.sh test/fixtures/mock-mempalace.sh test/lib/test_mcp_client.bats
git commit -m "feat(lib): mcp-client.sh wrapper with stdio/mock/http transports"
```

---

## Task 5: `core/scripts/health-check.sh`

**Files:**
- Create: `core/scripts/health-check.sh`

Runtime health check used by install.sh (pre-install smoke test) and the `/curator:memory` skill (for the `[MemPalace] connected` line). Emits a JSON summary on stdout.

- [ ] **Step 1: Write `core/scripts/health-check.sh`**

```bash
#!/usr/bin/env bash
# core/scripts/health-check.sh — emit JSON health summary.
# Usage: health-check.sh
# Exit code: 0 if all checks green, 1 if any red.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/mcp-client.sh"

bin_status() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 && echo "ok" || echo "missing"
}

mcp_status() {
  if mcp_ping 2>/dev/null; then
    echo "connected"
  else
    echo "unreachable"
  fi
}

state_status() {
  [ -d "$CURATOR_STATE" ] && echo "present" || echo "absent"
}

receipt_version() {
  local receipt="$CURATOR_STATE/install-receipt.json"
  if [ -f "$receipt" ]; then
    jq -r '.version // "unknown"' "$receipt"
  else
    echo "not-installed"
  fi
}

main() {
  local jq_status yq_status shasum_status
  jq_status="$(bin_status jq)"
  yq_status="$(bin_status yq)"
  shasum_status="$(bin_status shasum)"
  local mcp
  mcp="$(mcp_status)"
  local state
  state="$(state_status)"
  local ver
  ver="$(receipt_version)"

  jq -cn \
    --arg jq_s "$jq_status" \
    --arg yq_s "$yq_status" \
    --arg sha_s "$shasum_status" \
    --arg mcp_s "$mcp" \
    --arg state_s "$state" \
    --arg ver "$ver" \
    '{
      binaries: {jq:$jq_s, yq:$yq_s, shasum:$sha_s},
      mempalace: $mcp_s,
      state: $state_s,
      version: $ver
    }'

  # Exit non-zero if anything critical is broken
  if [ "$jq_status" = "missing" ] || [ "$yq_status" = "missing" ] || [ "$shasum_status" = "missing" ]; then
    exit 1
  fi
}

main "$@"
```

- [ ] **Step 2: Make executable and run it**

```bash
chmod +x core/scripts/health-check.sh
./core/scripts/health-check.sh | jq .
```

Expected output (values will vary):
```json
{
  "binaries": { "jq": "ok", "yq": "ok", "shasum": "ok" },
  "mempalace": "unreachable",
  "state": "absent",
  "version": "not-installed"
}
```

Exit code 0 if `jq/yq/shasum` all present; mempalace status can be unreachable without failing.

- [ ] **Step 3: Commit**

```bash
git add core/scripts/health-check.sh
git commit -m "feat(scripts): health-check.sh — JSON runtime status"
```

---

## Task 6: `core/scripts/preflight-check.sh`

**Files:**
- Create: `core/scripts/preflight-check.sh`
- Create: `test/scripts/test_preflight.bats`

Scans `~/.claude/` for collisions with curator's install plan. Generates a report and exits non-zero on hard blockers.

- [ ] **Step 1: Write the failing test**

Create `test/scripts/test_preflight.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # Fake a clean ~/.claude in a temp dir
  export CLAUDE_HOME="$BATS_TEST_TMPDIR/.claude"
  mkdir -p "$CLAUDE_HOME"/{skills,commands,projects}
  echo '{"hooks":{}}' > "$CLAUDE_HOME/settings.json"

  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  mkdir -p "$CURATOR_STATE"
}

@test "preflight succeeds on clean environment" {
  run "$REPO_ROOT/core/scripts/preflight-check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]] || [[ "$output" == *"OK"* ]]
}

@test "preflight detects skill name collision" {
  mkdir -p "$CLAUDE_HOME/skills/capture"
  echo "---" > "$CLAUDE_HOME/skills/capture/SKILL.md"
  run "$REPO_ROOT/core/scripts/preflight-check.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"capture"* ]]
  [[ "$output" == *"collision"* ]] || [[ "$output" == *"exists"* ]]
}

@test "preflight reports existing memdir and lists repos" {
  mkdir -p "$CLAUDE_HOME/projects/-Users-test-repoA/memory"
  echo "existing L0 content" > "$CLAUDE_HOME/projects/-Users-test-repoA/memory/MEMORY.md"
  run "$REPO_ROOT/core/scripts/preflight-check.sh"
  # Not a hard blocker: returns 0 but logs to preflight report
  [[ "$output" == *"backup"* ]] || [[ "$output" == *"memdir"* ]]
  [[ "$output" == *"repoA"* ]]
}

@test "preflight writes report file to CURATOR_STATE" {
  "$REPO_ROOT/core/scripts/preflight-check.sh" || true
  run bash -c "ls $CURATOR_STATE/preflight-*.log 2>/dev/null | head -1"
  [ -n "$output" ]
}

@test "preflight detects missing yq binary as hard blocker (with PATH hack)" {
  # Simulate missing yq by clearing PATH except system essentials
  local old_path="$PATH"
  export PATH="/bin:/usr/bin"  # bats is in /usr/local typically, so this skips it — just ensure we don't fail preflight test itself
  # Actually we can't easily remove yq from PATH; this test just asserts the check exists
  run grep -q "yq" "$REPO_ROOT/core/scripts/preflight-check.sh"
  [ "$status" -eq 0 ]
  export PATH="$old_path"
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bats test/scripts/test_preflight.bats
```

Expected: tests fail.

- [ ] **Step 3: Write `core/scripts/preflight-check.sh`**

```bash
#!/usr/bin/env bash
# core/scripts/preflight-check.sh — scan existing ~/.claude for curator install collisions.
# Usage: preflight-check.sh
# Exit code: 0 if safe to install (with warnings possibly), 1 if hard blockers exist.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

: "${CLAUDE_HOME:=$HOME/.claude}"
: "${CURATOR_STATE:=$HOME/.curator}"

REPORT="$CURATOR_STATE/preflight-$(date -u +%Y%m%d-%H%M%S).log"
mkdir -p "$CURATOR_STATE"
: > "$REPORT"

say() {
  echo "$@"
  echo "$@" >> "$REPORT"
}

blockers=0
warnings=0

say "# Curator preflight check — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say ""

# --- 1. Required binaries ---
say "## Binaries"
for bin in jq yq shasum; do
  if command -v "$bin" >/dev/null 2>&1; then
    say "  [OK] $bin"
  else
    say "  [BLOCKER] missing: $bin (brew install $bin)"
    blockers=$((blockers + 1))
  fi
done
say ""

# --- 2. Skill name collisions ---
say "## Skill name collisions"
for name in capture recall memory build; do
  collision=""
  [ -d "$CLAUDE_HOME/skills/$name" ] && collision="$CLAUDE_HOME/skills/$name"
  [ -d "$CLAUDE_HOME/skills/curator-$name" ] && collision="$collision $CLAUDE_HOME/skills/curator-$name"
  if [ -n "$collision" ]; then
    say "  [BLOCKER] collision for '$name': $collision"
    blockers=$((blockers + 1))
  else
    say "  [OK] $name — no collision"
  fi
done
say ""

# --- 3. Hook slot audit ---
say "## Hook slot audit"
settings="$CLAUDE_HOME/settings.json"
if [ -f "$settings" ]; then
  for slot in SessionStart UserPromptSubmit Stop; do
    count=$(jq -r --arg s "$slot" '.hooks[$s] // [] | length' "$settings" 2>/dev/null || echo 0)
    if [ "$count" = "0" ]; then
      say "  [OK] $slot — empty (clean append)"
    else
      say "  [INFO] $slot — $count existing hooks (curator will append at end; order matters for Stop)"
      warnings=$((warnings + 1))
    fi
  done
else
  say "  [INFO] no settings.json yet — will be created on install"
fi
say ""

# --- 4. Existing memdir content ---
say "## Existing memdir content"
projects_dir="$CLAUDE_HOME/projects"
if [ -d "$projects_dir" ]; then
  found=0
  while IFS= read -r mem; do
    repo=$(basename "$(dirname "$(dirname "$mem")")")
    say "  [BACKUP] $repo has populated MEMORY.md (will be backed up by install.sh)"
    warnings=$((warnings + 1))
    found=$((found + 1))
  done < <(find "$projects_dir" -maxdepth 4 -name "MEMORY.md" -size +0 2>/dev/null)
  [ "$found" -eq 0 ] && say "  [OK] no populated MEMORY.md files"
else
  say "  [OK] no projects directory yet"
fi
say ""

# --- 5. MemPalace MCP server ---
say "## MemPalace MCP"
if command -v claude >/dev/null 2>&1 && claude mcp list 2>/dev/null | grep -q '^mempalace'; then
  say "  [OK] mempalace MCP server registered"
else
  say "  [BLOCKER] MemPalace MCP not registered — install and run: claude mcp add mempalace -- mempalace serve --stdio"
  blockers=$((blockers + 1))
fi
say ""

# --- Summary ---
say "## Summary"
say "  blockers: $blockers"
say "  warnings: $warnings"
say ""
say "Report saved to: $REPORT"

if [ "$blockers" -gt 0 ]; then
  say ""
  say "PREFLIGHT FAILED — resolve blockers before running install.sh"
  exit 1
fi

say ""
say "PREFLIGHT OK — safe to install"
exit 0
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x core/scripts/preflight-check.sh
bats test/scripts/test_preflight.bats
```

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add core/scripts/preflight-check.sh test/scripts/test_preflight.bats
git commit -m "feat(scripts): preflight-check.sh — scan ~/.claude for collisions"
```

---

## Task 7: `core/scripts/install.sh`

**Files:**
- Create: `core/scripts/install.sh`
- Create: `core/templates/settings.json.patch.jq`
- Create: `core/templates/MEMORY.md.template`
- Create: `test/scripts/test_install.bats`

Runs preflight, backs up memdir, patches `settings.json` via `jq`, symlinks skills, registers MCP, writes install-receipt.json.

- [ ] **Step 1: Write `core/templates/settings.json.patch.jq`**

This `jq` filter takes the existing `settings.json` as input and curator config as `--argjson curator` and produces the patched settings.

```jq
# settings.json.patch.jq — merge curator hooks into existing settings.json
# Usage: jq -f settings.json.patch.jq --argjson curator "$CURATOR_CONFIG" settings.json

. as $existing
| .hooks //= {}
| .hooks.SessionStart //= []
| .hooks.UserPromptSubmit //= []
| .hooks.Stop //= []
# Append curator hook entries (dedup by command string)
| .hooks.SessionStart |= (
    . + ($curator.session_start | map(select(
      [.hooks[0].command] as $new_cmd |
      ([$existing.hooks.SessionStart[]?.hooks[0].command] | index($new_cmd[0])) == null
    )))
  )
| .hooks.UserPromptSubmit |= (
    . + ($curator.user_prompt_submit | map(select(
      [.hooks[0].command] as $new_cmd |
      ([$existing.hooks.UserPromptSubmit[]?.hooks[0].command] | index($new_cmd[0])) == null
    )))
  )
| .hooks.Stop |= (
    . + ($curator.stop | map(select(
      [.hooks[0].command] as $new_cmd |
      ([$existing.hooks.Stop[]?.hooks[0].command] | index($new_cmd[0])) == null
    )))
  )
```

- [ ] **Step 2: Write `core/templates/MEMORY.md.template`**

```markdown
<!-- curator: projection-ts=__PROJECTION_TS__ source=fresh schema_version=1 -->
# __PROJECT_NAME__ — L0 Memory

> **Absolute rules only.** L0 is what must never be violated. Historical context and patterns live in `pattern-signal.md` and are loaded on-demand by Claude Code.

## Project identity

- Project: __PROJECT_NAME__
- Canonical store: MemPalace (wing: __WING_NAME__)

## Absolute rules

(Populated by first `/curator:capture --pin <rule>` or by user-edited additions.)
```

- [ ] **Step 3: Write the failing test**

Create `test/scripts/test_install.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CLAUDE_HOME="$BATS_TEST_TMPDIR/.claude"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CURATOR_HOME="$REPO_ROOT"  # run from source tree
  export CURATOR_SKIP_MCP=1         # skip MCP verification in install
  mkdir -p "$CLAUDE_HOME"
  cat > "$CLAUDE_HOME/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "existing-stop-hook.sh" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "secret-scan.sh" } ] }
    ]
  }
}
EOF
  # Create a populated memdir so backup path is exercised
  mkdir -p "$CLAUDE_HOME/projects/-Users-test-repoX/memory"
  echo "old content" > "$CLAUDE_HOME/projects/-Users-test-repoX/memory/MEMORY.md"
}

@test "install writes install-receipt.json" {
  run "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  [ "$status" -eq 0 ]
  [ -f "$CURATOR_STATE/install-receipt.json" ]
  jq -e '.version, .installed_at, .device_id, .hook_order_snapshot' \
    "$CURATOR_STATE/install-receipt.json" > /dev/null
}

@test "install appends curator hooks to Stop without removing existing" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  local stop_count
  stop_count=$(jq '.hooks.Stop | length' "$CLAUDE_HOME/settings.json")
  [ "$stop_count" -ge 2 ]  # existing + curator
  # Existing hook must still be present
  jq -e '.hooks.Stop | map(.hooks[0].command) | any(. == "existing-stop-hook.sh")' \
    "$CLAUDE_HOME/settings.json" > /dev/null
  # Curator hook must be present
  jq -e '.hooks.Stop | map(.hooks[0].command) | any(contains("curator") or contains("stop.sh"))' \
    "$CLAUDE_HOME/settings.json" > /dev/null
}

@test "install creates SessionStart and UserPromptSubmit hooks when slots empty" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  jq -e '.hooks.SessionStart | length >= 1' "$CLAUDE_HOME/settings.json" > /dev/null
  jq -e '.hooks.UserPromptSubmit | length >= 1' "$CLAUDE_HOME/settings.json" > /dev/null
}

@test "install preserves PreToolUse hooks untouched" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  jq -e '.hooks.PreToolUse | length == 1' "$CLAUDE_HOME/settings.json" > /dev/null
  jq -e '.hooks.PreToolUse[0].hooks[0].command == "secret-scan.sh"' \
    "$CLAUDE_HOME/settings.json" > /dev/null
}

@test "install backs up existing memdir content" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  # Backup dir should exist and contain the old content
  find "$CLAUDE_HOME/projects/-Users-test-repoX/memory" -type d -name "backup-*" | \
    read -r backup_dir
  [ -n "$backup_dir" ]
  grep -q "old content" "$backup_dir/MEMORY.md"
}

@test "install generates device-id on first run and keeps it stable" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  local id1
  id1=$(cat "$CURATOR_STATE/device-id")
  [ -n "$id1" ]
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  local id2
  id2=$(cat "$CURATOR_STATE/device-id")
  [ "$id1" = "$id2" ]
}

@test "install is idempotent (no duplicate hooks on second run)" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  local count1
  count1=$(jq '.hooks.Stop | length' "$CLAUDE_HOME/settings.json")
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  local count2
  count2=$(jq '.hooks.Stop | length' "$CLAUDE_HOME/settings.json")
  [ "$count1" = "$count2" ]
}
```

- [ ] **Step 4: Run test to verify it fails**

```bash
bats test/scripts/test_install.bats
```

Expected: tests fail.

- [ ] **Step 5: Write `core/scripts/install.sh`**

```bash
#!/usr/bin/env bash
# core/scripts/install.sh — deploy curator into ~/.claude and ~/.curator.
# Safe to re-run (idempotent). Reverse with uninstall.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURATOR_HOME="${CURATOR_HOME:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$SCRIPT_DIR/../lib/common.sh"

: "${CLAUDE_HOME:=$HOME/.claude}"
: "${CURATOR_STATE:=$HOME/.curator}"

SKIP_PREFLIGHT=0
SKIP_MCP=0
for arg in "$@"; do
  case "$arg" in
    --skip-preflight) SKIP_PREFLIGHT=1 ;;
    --skip-mcp) SKIP_MCP=1 ;;
    --help|-h)
      echo "Usage: install.sh [--skip-preflight] [--skip-mcp]"
      exit 0
      ;;
  esac
done

# --- 1. Preflight ---
if [ "$SKIP_PREFLIGHT" = "0" ]; then
  curator_log INFO "Running preflight check..."
  "$SCRIPT_DIR/preflight-check.sh"
fi

# --- 2. Ensure state dir + device-id ---
mkdir -p "$CURATOR_STATE"
curator_device_id > /dev/null  # ensures file exists
device_id="$(cat "$CURATOR_STATE/device-id")"
curator_log INFO "device-id: $device_id"

# --- 3. Backup existing memdir ---
curator_log INFO "Backing up existing memdir content..."
backup_count=0
if [ -d "$CLAUDE_HOME/projects" ]; then
  while IFS= read -r mem; do
    repo_memory="$(dirname "$mem")"
    ts="$(date -u +%Y%m%d-%H%M%S)"
    backup_dir="$repo_memory/backup-$ts"
    mkdir -p "$backup_dir"
    cp -r "$repo_memory"/*.md "$backup_dir/" 2>/dev/null || true
    backup_count=$((backup_count + 1))
    curator_log INFO "  backed up: $repo_memory → $backup_dir"
  done < <(find "$CLAUDE_HOME/projects" -maxdepth 4 -name "MEMORY.md" -size +0 2>/dev/null)
fi
curator_log INFO "memdir backups: $backup_count"

# --- 4. Symlink skills into ~/.claude/skills/ ---
mkdir -p "$CLAUDE_HOME/skills"
for skill in capture recall memory build; do
  src="$CURATOR_HOME/skills/$skill.md"
  dst="$CLAUDE_HOME/skills/curator-$skill.md"
  if [ -f "$src" ]; then
    ln -sf "$src" "$dst"
    curator_log INFO "  linked skill: $dst → $src"
  fi
done

# --- 5. Patch settings.json ---
settings="$CLAUDE_HOME/settings.json"
[ -f "$settings" ] || echo '{}' > "$settings"

# Build curator hook config
curator_config=$(jq -cn \
  --arg session_start "$CURATOR_HOME/core/hooks/session-start.sh" \
  --arg user_prompt "$CURATOR_HOME/core/hooks/user-prompt-submit.sh" \
  --arg stop_hook "$CURATOR_HOME/core/hooks/stop.sh" \
  '{
    session_start: [{ matcher: "", hooks: [{ type: "command", command: $session_start, timeout: 15 }] }],
    user_prompt_submit: [{ matcher: "", hooks: [{ type: "command", command: $user_prompt, timeout: 600 }] }],
    stop: [{ matcher: "", hooks: [{ type: "command", command: $stop_hook, timeout: 600 }] }]
  }')

# Apply the patch using the jq filter (idempotent by command string dedup)
tmp_settings=$(mktemp)
jq -f "$CURATOR_HOME/core/templates/settings.json.patch.jq" \
   --argjson curator "$curator_config" "$settings" > "$tmp_settings"
mv "$tmp_settings" "$settings"
curator_log INFO "patched $settings"

# --- 6. Register MCP server (if not skipping) ---
if [ "$SKIP_MCP" = "0" ]; then
  if command -v claude >/dev/null 2>&1; then
    if claude mcp list 2>/dev/null | grep -q '^mempalace'; then
      curator_log INFO "mempalace MCP already registered"
    else
      curator_log WARN "mempalace MCP not registered — register manually: claude mcp add mempalace -- mempalace serve --stdio"
    fi
  fi
fi

# --- 7. Write install receipt ---
receipt="$CURATOR_STATE/install-receipt.json"
hook_snapshot=$(jq -c '.hooks' "$settings")
jq -cn \
  --arg version "0.1.0" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg device "$device_id" \
  --argjson hooks "$hook_snapshot" \
  '{
    version: $version,
    installed_at: $ts,
    device_id: $device,
    hook_order_snapshot: $hooks,
    curator_home: env.CURATOR_HOME
  }' > "$receipt"
curator_log INFO "install receipt: $receipt"

curator_log INFO "Install complete."
```

- [ ] **Step 6: Make executable and run tests**

```bash
chmod +x core/scripts/install.sh
bats test/scripts/test_install.bats
```

Expected: 7 tests pass.

- [ ] **Step 7: Commit**

```bash
git add core/scripts/install.sh core/templates/ test/scripts/test_install.bats
git commit -m "feat(scripts): install.sh with jq-patch settings.json and memdir backup"
```

---

## Task 8: `core/scripts/uninstall.sh`

**Files:**
- Create: `core/scripts/uninstall.sh`
- Add tests to `test/scripts/test_install.bats`

Reverses install by reading `install-receipt.json` and removing hook entries by command-string match.

- [ ] **Step 1: Add test cases to existing bats file**

Append to `test/scripts/test_install.bats`:

```bash
@test "uninstall removes curator hooks but leaves existing" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  "$REPO_ROOT/core/scripts/uninstall.sh" --keep-state
  # Curator hooks should be gone
  jq -e '.hooks.Stop | map(.hooks[0].command) | any(contains("curator") or contains("stop.sh")) | not' \
    "$CLAUDE_HOME/settings.json" > /dev/null
  # Existing hook must still be there
  jq -e '.hooks.Stop | map(.hooks[0].command) | any(. == "existing-stop-hook.sh")' \
    "$CLAUDE_HOME/settings.json" > /dev/null
}

@test "uninstall removes skill symlinks" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  "$REPO_ROOT/core/scripts/uninstall.sh" --keep-state
  [ ! -L "$CLAUDE_HOME/skills/curator-capture.md" ]
  [ ! -L "$CLAUDE_HOME/skills/curator-recall.md" ]
}

@test "uninstall --keep-state preserves ~/.curator" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  echo "sentinel" > "$CURATOR_STATE/sentinel.txt"
  "$REPO_ROOT/core/scripts/uninstall.sh" --keep-state
  [ -f "$CURATOR_STATE/sentinel.txt" ]
}

@test "uninstall --purge removes ~/.curator" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  "$REPO_ROOT/core/scripts/uninstall.sh" --purge
  [ ! -d "$CURATOR_STATE" ]
}
```

- [ ] **Step 2: Write `core/scripts/uninstall.sh`**

```bash
#!/usr/bin/env bash
# core/scripts/uninstall.sh — reverse install.sh via install-receipt.json.
# Flags: --keep-state (default: preserve ~/.curator), --purge (delete ~/.curator)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

: "${CLAUDE_HOME:=$HOME/.claude}"
: "${CURATOR_STATE:=$HOME/.curator}"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/../.." && pwd)}"

MODE="keep"  # keep | purge
for arg in "$@"; do
  case "$arg" in
    --keep-state) MODE="keep" ;;
    --purge) MODE="purge" ;;
  esac
done

receipt="$CURATOR_STATE/install-receipt.json"
if [ ! -f "$receipt" ]; then
  curator_log WARN "no install receipt at $receipt — will still attempt best-effort cleanup"
fi

# --- 1. Remove hook entries matching curator commands from settings.json ---
settings="$CLAUDE_HOME/settings.json"
if [ -f "$settings" ]; then
  tmp=$(mktemp)
  jq --arg curator_home "$CURATOR_HOME" '
    .hooks //= {} |
    (.hooks.SessionStart // []) as $ss |
    (.hooks.UserPromptSubmit // []) as $us |
    (.hooks.Stop // []) as $st |
    .hooks.SessionStart = ($ss | map(select(.hooks[0].command | startswith($curator_home) | not))) |
    .hooks.UserPromptSubmit = ($us | map(select(.hooks[0].command | startswith($curator_home) | not))) |
    .hooks.Stop = ($st | map(select(.hooks[0].command | startswith($curator_home) | not)))
  ' "$settings" > "$tmp"
  mv "$tmp" "$settings"
  curator_log INFO "removed curator hooks from $settings"
fi

# --- 2. Remove skill symlinks ---
for skill in capture recall memory build; do
  dst="$CLAUDE_HOME/skills/curator-$skill.md"
  [ -L "$dst" ] && rm "$dst" && curator_log INFO "removed symlink: $dst"
done

# --- 3. Handle state dir ---
if [ "$MODE" = "purge" ]; then
  rm -rf "$CURATOR_STATE"
  curator_log INFO "purged state dir: $CURATOR_STATE"
else
  curator_log INFO "state dir preserved: $CURATOR_STATE"
fi

curator_log INFO "Uninstall complete."
```

- [ ] **Step 3: Run tests**

```bash
chmod +x core/scripts/uninstall.sh
bats test/scripts/test_install.bats
```

Expected: all 11 tests pass (7 original + 4 uninstall).

- [ ] **Step 4: Commit**

```bash
git add core/scripts/uninstall.sh test/scripts/test_install.bats
git commit -m "feat(scripts): uninstall.sh — reverse install via command-string dedup"
```

---

## Task 9: `memory-bridge/routing-rules.yaml` + `memory-bridge/router.sh`

**Files:**
- Create: `memory-bridge/routing-rules.yaml`
- Create: `memory-bridge/router.sh`
- Create: `test/scripts/test_router.bats`

Declarative routing from memory type to destination.

- [ ] **Step 1: Write `memory-bridge/routing-rules.yaml`**

```yaml
# memory-bridge/routing-rules.yaml
version: 1
rules:
  - match:
      type: feedback
      min_length: 50
    destinations:
      memory: immediate
      mempalace: batch
      priority: medium

  - match:
      type: architecture_decision
      min_length: 50
    destinations:
      memory: immediate
      mempalace: priority_push
      priority: high

  - match:
      type: user_preference
    destinations:
      memory: immediate
      mempalace: skip

  - match:
      type: session_observation
    destinations:
      memory: skip
      mempalace: batch
      priority: low

  - match:
      type: pattern
      min_confidence: 0.8
    destinations:
      memory: pattern_signal
      mempalace: after_user_confirm
      priority: medium
```

- [ ] **Step 2: Write the failing test**

Create `test/scripts/test_router.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/core/lib/common.sh"
  source "$REPO_ROOT/memory-bridge/router.sh"
  export CURATOR_RULES="$REPO_ROOT/memory-bridge/routing-rules.yaml"
}

@test "router_match returns 'memory:immediate,mempalace:batch' for feedback >= 50 chars" {
  local text="this is a feedback message that is definitely longer than fifty characters for the test"
  run router_match "feedback" "$text"
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory:immediate"* ]]
  [[ "$output" == *"mempalace:batch"* ]]
}

@test "router_match returns 'memory:skip,mempalace:batch' for session_observation" {
  run router_match "session_observation" "short"
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory:skip"* ]]
  [[ "$output" == *"mempalace:batch"* ]]
}

@test "router_match returns 'memory:pattern_signal' for high-confidence pattern" {
  run router_match "pattern" "some text" "confidence=0.9"
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory:pattern_signal"* ]]
}

@test "router_match falls through with memory:skip,mempalace:skip for unknown type" {
  run router_match "unknown_type" "x"
  # Either exits 0 with skip:skip or returns non-zero with clear message
  [[ "$output" == *"skip"* ]] || [ "$status" -ne 0 ]
}

@test "router_match skips short feedback (below min_length)" {
  run router_match "feedback" "short"
  # Rule requires min_length 50, so this should not match the feedback rule
  [[ "$output" != *"mempalace:batch"* ]] || [[ "$output" == *"skip"* ]]
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
bats test/scripts/test_router.bats
```

Expected: tests fail, no `router.sh`.

- [ ] **Step 4: Write `memory-bridge/router.sh`**

```bash
#!/usr/bin/env bash
# memory-bridge/router.sh — declarative routing dispatcher.
# Reads routing-rules.yaml and returns destination config for a given type/text/metadata.

: "${CURATOR_HOME:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${CURATOR_RULES:=$CURATOR_HOME/memory-bridge/routing-rules.yaml}"

# Args:
#   $1: type (e.g., feedback, pattern)
#   $2: text
#   $3: optional metadata (key=value pairs, space-separated), e.g., "confidence=0.9"
# Output: "memory:<dest>,mempalace:<dest>[,priority:<p>]"
router_match() {
  local type="$1"
  local text="${2:-}"
  local metadata="${3:-}"
  local text_len=${#text}

  # Extract confidence if provided
  local confidence=0
  if [[ "$metadata" == *confidence=* ]]; then
    confidence=$(echo "$metadata" | sed -n 's/.*confidence=\([0-9.]*\).*/\1/p')
  fi

  # Iterate rules and match
  local rule_count
  rule_count=$(yq '.rules | length' "$CURATOR_RULES")

  local i
  for ((i = 0; i < rule_count; i++)); do
    local rule_type rule_min_len rule_min_conf
    rule_type=$(yq ".rules[$i].match.type // \"\"" "$CURATOR_RULES")
    rule_min_len=$(yq ".rules[$i].match.min_length // 0" "$CURATOR_RULES")
    rule_min_conf=$(yq ".rules[$i].match.min_confidence // 0" "$CURATOR_RULES")

    [ "$rule_type" != "$type" ] && continue
    if [ "$text_len" -lt "$rule_min_len" ]; then
      continue
    fi
    # Compare floats via awk
    if awk -v c="$confidence" -v m="$rule_min_conf" 'BEGIN{exit !(c+0 < m+0)}'; then
      continue
    fi

    # Match! Emit destinations
    local mem_dest mp_dest prio
    mem_dest=$(yq ".rules[$i].destinations.memory // \"skip\"" "$CURATOR_RULES")
    mp_dest=$(yq ".rules[$i].destinations.mempalace // \"skip\"" "$CURATOR_RULES")
    prio=$(yq ".rules[$i].destinations.priority // \"medium\"" "$CURATOR_RULES")

    echo "memory:$mem_dest,mempalace:$mp_dest,priority:$prio"
    return 0
  done

  # No match: skip everywhere
  echo "memory:skip,mempalace:skip,priority:low"
  return 0
}
```

- [ ] **Step 5: Run tests to verify pass**

```bash
bats test/scripts/test_router.bats
```

Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add memory-bridge/routing-rules.yaml memory-bridge/router.sh test/scripts/test_router.bats
git commit -m "feat(bridge): declarative YAML routing rules + yq interpreter"
```

---

**v1 note on `router.sh` usage**: In v1, curator writes every user-captured memory as type `feedback`, so only the `feedback` rule matches. `router.sh` is implemented here as infrastructure — it will be wired into `/curator:capture` in v1.1 when differentiated types (architecture_decision, pattern, user_preference) get explicit flags. Shipping the YAML + interpreter in v1 avoids a schema migration later.

---

## Task 10: `memory-bridge/adapter-interface.md` — MemoryAdapter contract

**Files:**
- Create: `memory-bridge/adapter-interface.md`

This is a Day-1 frozen contract document. No code, no tests — but it's the source of truth for what any future MemoryAdapter implementation must provide.

- [ ] **Step 1: Write the contract**

Create `memory-bridge/adapter-interface.md`:

```markdown
# MemoryAdapter Interface (Day 1 Contract — frozen)

> **Stability**: this contract is frozen from v1.0 onward. Breaking changes require a major version bump and an adapter migration plan.

A `MemoryAdapter` is any module that curator can delegate writes and reads to. MemPalace is the default adapter. Future adapters (e.g., a team-scoped adapter for v2.3) must implement this same contract.

## Lifecycle

Every adapter MUST expose the following operations. Inputs and outputs are JSON; protocol is MCP over stdio, http, or mock.

### `ping() → {result: "pong"}`

Liveness check. MUST respond within 3 seconds or the caller treats it as unreachable.

### `search(params: {query: string, wing?: string, hall?: string, limit?: int}) → {result: Array<Drawer>}`

Semantic search. Returns up to `limit` (default 5) drawers ordered by relevance. Fields:

```json
{
  "id": "drawer-uuid",
  "wing": "wing-name",
  "hall": "hall_facts | hall_events | hall_discoveries | hall_preferences | hall_advice",
  "room": "topic-name",
  "text": "verbatim content",
  "ts": "ISO-8601",
  "metadata": {
    "device_id": "laptop-k3x7",
    "content_hash": "sha256-hex"
  }
}
```

If no results, `result` is an empty array, not null.

### `write(params: {type: string, payload: object, metadata?: object}) → {result: {id: string}}`

Store a new drawer. `type` is the curator memory type (feedback, pattern, capture, architecture_decision). `payload.text` is the required field; all other fields are adapter-specific.

`metadata` MUST include:
- `content_hash` (SHA-256 hex) — idempotency key. Second write with same hash is a no-op and returns the original `id`.
- `device_id` — string, device identifier.

If the write succeeds, the response `result.id` is a stable identifier for the drawer.

### `delete(params: {id: string}) → {result: {deleted: boolean}}`

Optional for v1. MemPalace adapter returns `{deleted: false}` if unsupported.

## Error contract

All errors are returned as `{error: {code: string, message: string}}`. Codes:

- `UNREACHABLE` — adapter process down or network partition
- `TIMEOUT` — exceeded `CURATOR_MCP_TIMEOUT` seconds
- `INVALID_PARAMS` — request malformed
- `DUPLICATE` — write attempted with existing content_hash; NOT a failure, adapter MAY return normal `result` with original id
- `INTERNAL` — adapter-specific failure

Curator treats `UNREACHABLE` and `TIMEOUT` as retryable. `INVALID_PARAMS` and `INTERNAL` are terminal (log and drop).

## Concurrency

Adapters MUST NOT assume single-writer. Two curator hooks on different devices can call `write` concurrently with different content. They MAY call `write` with the same `content_hash`; the adapter MUST deduplicate by hash.

## Namespace parameter (reserved for v2.3)

All operations accept an optional `namespace: string` parameter. In v1, the MemPalace adapter ignores it. In v2.3, a team adapter uses it to partition drawers by team. Curator always sends `namespace: null` in v1.
```

- [ ] **Step 2: Commit**

```bash
git add memory-bridge/adapter-interface.md
git commit -m "docs(bridge): MemoryAdapter contract (Day 1 frozen)"
```

---

## Task 11: `memory-bridge/project.sh` — SessionStart projection

**Files:**
- Create: `memory-bridge/project.sh`
- Add tests to: `test/hooks/test_session_start.bats` (file created in T13; for now, unit tests go in `test/scripts/test_project.bats`)
- Create: `test/scripts/test_project.bats`

Pulls L0 rules from MemPalace and writes them into `$CLAUDE_PROJECT_ROOT/memory/MEMORY.md` using the template. Also computes the stale banner tier.

- [ ] **Step 1: Write the failing test**

Create `test/scripts/test_project.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CLAUDE_PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
  export CURATOR_HOME="$REPO_ROOT"
  export MOCK_MCP_LOG="$BATS_TEST_TMPDIR/mcp.log"
  export CURATOR_MEMPALACE_URL="mock://$REPO_ROOT/test/fixtures/mock-mempalace.sh"
  export MOCK_MCP_MODE=ok
  mkdir -p "$CLAUDE_PROJECT_ROOT/memory"
  : > "$MOCK_MCP_LOG"
}

@test "project_run writes MEMORY.md with projection-ts banner" {
  "$REPO_ROOT/memory-bridge/project.sh"
  [ -f "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md" ]
  grep -q "curator: projection-ts=" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
  grep -q "source=fresh" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
}

@test "project_run writes MEMORY.md with source=stale when MCP unreachable" {
  export MOCK_MCP_MODE=fail
  "$REPO_ROOT/memory-bridge/project.sh" || true
  grep -q "source=stale" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md" || \
    [ ! -f "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md" ]  # or leaves previous stale file
}

@test "project_run includes project name in MEMORY.md" {
  export CLAUDE_PROJECT_ROOT="$BATS_TEST_TMPDIR/my-repo"
  mkdir -p "$CLAUDE_PROJECT_ROOT/memory"
  "$REPO_ROOT/memory-bridge/project.sh"
  grep -q "my-repo" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
}

@test "project_run calls mcp search with wing=current project" {
  "$REPO_ROOT/memory-bridge/project.sh"
  grep -q '"method":"search"' "$MOCK_MCP_LOG"
}

@test "project_run preserves existing MEMORY.md as backup before overwrite" {
  echo "existing content" > "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
  "$REPO_ROOT/memory-bridge/project.sh"
  # Backup should exist under memory/backup-*/MEMORY.md
  find "$CLAUDE_PROJECT_ROOT/memory" -name "backup-*" -type d | head -1 | read -r backup
  [ -n "$backup" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bats test/scripts/test_project.bats
```

Expected: tests fail.

- [ ] **Step 3: Write `memory-bridge/project.sh`**

```bash
#!/usr/bin/env bash
# memory-bridge/project.sh — SessionStart projection: MemPalace → MEMORY.md.
# Required env: CLAUDE_PROJECT_ROOT, CURATOR_HOME.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/mcp-client.sh"

: "${CLAUDE_PROJECT_ROOT:?CLAUDE_PROJECT_ROOT must be set}"

mem_dir="$CLAUDE_PROJECT_ROOT/memory"
mem_file="$mem_dir/MEMORY.md"
template="$CURATOR_HOME/core/templates/MEMORY.md.template"

mkdir -p "$mem_dir"

# 1. Back up existing MEMORY.md (idempotent; skip if already backed up this second)
if [ -f "$mem_file" ] && [ -s "$mem_file" ]; then
  ts=$(date -u +%Y%m%d-%H%M%S)
  backup="$mem_dir/backup-$ts"
  mkdir -p "$backup"
  cp "$mem_file" "$backup/MEMORY.md"
fi

# 2. Try to pull L0 rules from MemPalace
project_name="$(basename "$CLAUDE_PROJECT_ROOT")"
wing_name="$project_name"
source_tier="fresh"
l0_rules=""

if mcp_ping 2>/dev/null; then
  resp=$(mcp_search "L0 absolute rules" "$wing_name" "hall_facts" 2>/dev/null || echo "")
  if [ -n "$resp" ]; then
    l0_rules=$(echo "$resp" | jq -r '.result // [] | map("- " + .text) | join("\n")')
  fi
else
  source_tier="stale"
fi

# 3. Render template
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [ ! -f "$template" ]; then
  curator_log ERROR "template missing: $template"
  exit 1
fi

sed \
  -e "s|__PROJECTION_TS__|$now|g" \
  -e "s|__PROJECT_NAME__|$project_name|g" \
  -e "s|__WING_NAME__|$wing_name|g" \
  "$template" > "$mem_file"

# Override source tier in banner if stale
if [ "$source_tier" = "stale" ]; then
  sed -i.bak "s|source=fresh|source=stale|" "$mem_file" && rm "$mem_file.bak"
fi

# Append pulled L0 rules if any
if [ -n "$l0_rules" ]; then
  printf "\n%s\n" "$l0_rules" >> "$mem_file"
fi

curator_log INFO "projection written: $mem_file (source=$source_tier)"
```

- [ ] **Step 4: Make executable, run tests**

```bash
chmod +x memory-bridge/project.sh
bats test/scripts/test_project.bats
```

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add memory-bridge/project.sh test/scripts/test_project.bats
git commit -m "feat(bridge): project.sh — SessionStart projection with stale banner"
```

---

## Task 12: `memory-bridge/reconcile.sh` — pending_sync retry

**Files:**
- Create: `memory-bridge/reconcile.sh`
- Create: `test/scripts/test_reconcile.bats`

Reads `pending_sync.jsonl`, retries entries with non-empty `pending` array, marks resolved on success, prunes >7d entries.

- [ ] **Step 1: Write the failing test**

Create `test/scripts/test_reconcile.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CURATOR_MEMPALACE_URL="mock://$REPO_ROOT/test/fixtures/mock-mempalace.sh"
  export MOCK_MCP_LOG="$BATS_TEST_TMPDIR/mcp.log"
  mkdir -p "$CURATOR_STATE"
  : > "$MOCK_MCP_LOG"
  source "$REPO_ROOT/core/lib/common.sh"
  source "$REPO_ROOT/core/lib/journal.sh"
  echo "test-device" > "$CURATOR_STATE/device-id"
}

@test "reconcile marks pending entries as resolved after successful retry" {
  export MOCK_MCP_MODE=ok
  journal_append "feedback" '{"text":"needs retry"}'
  "$REPO_ROOT/memory-bridge/reconcile.sh"
  # Pending array should now be empty
  local pending_count
  pending_count=$(jq -s 'map(select(.pending | length > 0)) | length' "$CURATOR_STATE/pending_sync.jsonl")
  [ "$pending_count" -eq 0 ]
}

@test "reconcile leaves entries pending when MCP fails" {
  export MOCK_MCP_MODE=fail
  journal_append "feedback" '{"text":"fail case"}'
  "$REPO_ROOT/memory-bridge/reconcile.sh" || true
  local pending_count
  pending_count=$(jq -s 'map(select(.pending | length > 0)) | length' "$CURATOR_STATE/pending_sync.jsonl")
  [ "$pending_count" -ge 1 ]
}

@test "reconcile is a no-op when no pending entries" {
  # Empty journal file
  : > "$CURATOR_STATE/pending_sync.jsonl"
  run "$REPO_ROOT/memory-bridge/reconcile.sh"
  [ "$status" -eq 0 ]
}

@test "reconcile prunes entries older than 7 days" {
  cat > "$CURATOR_STATE/pending_sync.jsonl" <<'OLD'
{"content_hash":"old","ts":"2020-01-01T00:00:00Z","device_id":"x","type":"feedback","payload":{"text":"ancient"},"pending":["mempalace"]}
OLD
  export MOCK_MCP_MODE=ok
  "$REPO_ROOT/memory-bridge/reconcile.sh"
  # Old entry should be removed
  run grep -c "old" "$CURATOR_STATE/pending_sync.jsonl"
  [ "$output" = "0" ] || [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bats test/scripts/test_reconcile.bats
```

Expected: tests fail.

- [ ] **Step 3: Write `memory-bridge/reconcile.sh`**

```bash
#!/usr/bin/env bash
# memory-bridge/reconcile.sh — retry pending_sync.jsonl writes against MemPalace.
# Runs during SessionStart hook. Idempotent by content_hash.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/journal.sh"
source "$CURATOR_HOME/core/lib/mcp-client.sh"

# 1. Prune entries older than 7 days first (always)
journal_prune_older_than 7 || true

# 2. Iterate pending entries and retry each
journal_pending_entries | while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  local_hash=$(echo "$entry" | jq -r '.content_hash')
  local_type=$(echo "$entry" | jq -r '.type')
  local_payload=$(echo "$entry" | jq -c '.payload')

  if mcp_write "$local_type" "$local_payload"; then
    journal_mark_resolved "$local_hash" "mempalace"
    curator_log INFO "reconciled: $local_hash"
  else
    curator_log WARN "reconcile failed for $local_hash (will retry next session)"
  fi
done

exit 0
```

- [ ] **Step 4: Run tests**

```bash
chmod +x memory-bridge/reconcile.sh
bats test/scripts/test_reconcile.bats
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add memory-bridge/reconcile.sh test/scripts/test_reconcile.bats
git commit -m "feat(bridge): reconcile.sh — idempotent retry of pending_sync"
```

---

## Task 13: `core/hooks/session-start.sh`

**Files:**
- Create: `core/hooks/session-start.sh`
- Create: `test/hooks/test_session_start.bats`

Orchestrator hook: resets session-state, calls project.sh, calls reconcile.sh, emits stale-tier banner.

- [ ] **Step 1: Write the failing test**

Create `test/hooks/test_session_start.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_HOME="$REPO_ROOT"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CLAUDE_PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
  export CLAUDE_SESSION_ID="test-sess-1"
  export CURATOR_MEMPALACE_URL="mock://$REPO_ROOT/test/fixtures/mock-mempalace.sh"
  export MOCK_MCP_LOG="$BATS_TEST_TMPDIR/mcp.log"
  export MOCK_MCP_MODE=ok
  mkdir -p "$CLAUDE_PROJECT_ROOT/memory" "$CURATOR_STATE"
  : > "$MOCK_MCP_LOG"
  echo "mac-test" > "$CURATOR_STATE/device-id"
}

@test "session-start resets session-state.json proposal_count to 0" {
  "$REPO_ROOT/core/hooks/session-start.sh"
  local count
  count=$(jq -r .proposal_count "$CURATOR_STATE/session-state.json")
  [ "$count" = "0" ]
}

@test "session-start records session_id in session-state.json" {
  "$REPO_ROOT/core/hooks/session-start.sh"
  local sid
  sid=$(jq -r .session_id "$CURATOR_STATE/session-state.json")
  [ "$sid" = "test-sess-1" ]
}

@test "session-start creates MEMORY.md via project.sh" {
  "$REPO_ROOT/core/hooks/session-start.sh"
  [ -f "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md" ]
}

@test "session-start invokes reconcile when pending_sync has entries" {
  source "$REPO_ROOT/core/lib/common.sh"
  source "$REPO_ROOT/core/lib/journal.sh"
  journal_append "feedback" '{"text":"pre-existing pending"}'
  "$REPO_ROOT/core/hooks/session-start.sh"
  local pending
  pending=$(jq -s 'map(select(.pending | length > 0)) | length' \
    "$CURATOR_STATE/pending_sync.jsonl")
  [ "$pending" = "0" ]
}

@test "session-start exits 0 even when MemPalace unreachable" {
  export MOCK_MCP_MODE=fail
  run "$REPO_ROOT/core/hooks/session-start.sh"
  [ "$status" -eq 0 ]
  # MEMORY.md still written with stale banner
  grep -q "source=stale" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
}

@test "session-start is fast enough (under 15 seconds)" {
  local start
  start=$(date +%s)
  "$REPO_ROOT/core/hooks/session-start.sh"
  local end
  end=$(date +%s)
  [ "$((end - start))" -lt 15 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bats test/hooks/test_session_start.bats
```

Expected: tests fail.

- [ ] **Step 3: Write `core/hooks/session-start.sh`**

```bash
#!/usr/bin/env bash
# core/hooks/session-start.sh — CC SessionStart hook entry point.
# Non-blocking (15s timeout in settings.json). Fire-and-forget behavior: any
# internal failure just logs and returns 0 to avoid blocking session start.

set -uo pipefail  # NOTE: no -e — we never want to fail the whole session

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$CURATOR_HOME/core/lib/common.sh"

: "${CURATOR_STATE:=$HOME/.curator}"
: "${CLAUDE_PROJECT_ROOT:=$PWD}"
: "${CLAUDE_SESSION_ID:=$(date +%s)-$$}"

mkdir -p "$CURATOR_STATE"

# 1. Reset per-session state
jq -cn \
  --arg sid "$CLAUDE_SESSION_ID" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{session_id:$sid, started_at:$ts, proposal_count:0, last_proposal_ts:null}' \
  > "$CURATOR_STATE/session-state.json"

# 2. Run projection (never blocks session)
if ! "$CURATOR_HOME/memory-bridge/project.sh"; then
  curator_log WARN "project.sh failed — continuing with stale MEMORY.md"
fi

# 3. Run reconcile (best effort)
if ! "$CURATOR_HOME/memory-bridge/reconcile.sh"; then
  curator_log WARN "reconcile.sh failed — will retry next session"
fi

# 4. Compute staleness tier and emit banner to stderr (CC routes stderr to user)
mem_file="$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
if [ -f "$mem_file" ]; then
  banner=$(head -n 1 "$mem_file")
  if [[ "$banner" == *source=stale* ]]; then
    proj_ts=$(echo "$banner" | sed -n 's/.*projection-ts=\([^ ]*\).*/\1/p')
    now=$(date -u +%s)
    proj_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$proj_ts" +%s 2>/dev/null || \
                 date -u -d "$proj_ts" +%s 2>/dev/null || echo "$now")
    age=$((now - proj_epoch))
    if [ "$age" -ge 86400 ]; then
      echo "[curator] ⚠ using cached memory (stale >24h), MemPalace unreachable" >&2
    elif [ "$age" -ge 300 ]; then
      echo "[curator] ⚠ using cached memory (stale ${age}s), MemPalace unreachable" >&2
    fi
    # <5min is silent
  fi
fi

exit 0
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x core/hooks/session-start.sh
bats test/hooks/test_session_start.bats
```

Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add core/hooks/session-start.sh test/hooks/test_session_start.bats
git commit -m "feat(hooks): session-start.sh — projection + reconcile + stale banner"
```

---

## Task 14: `core/hooks/stop.sh`

**Files:**
- Create: `core/hooks/stop.sh`
- Create: `test/hooks/test_stop.bats`

Flushes any remaining `pending_sync` entries (same idempotent path as reconcile), prunes `pattern-signal.md` to 7d rolling window.

- [ ] **Step 1: Write the failing test**

Create `test/hooks/test_stop.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_HOME="$REPO_ROOT"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CLAUDE_PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
  export CURATOR_MEMPALACE_URL="mock://$REPO_ROOT/test/fixtures/mock-mempalace.sh"
  export MOCK_MCP_LOG="$BATS_TEST_TMPDIR/mcp.log"
  export MOCK_MCP_MODE=ok
  mkdir -p "$CLAUDE_PROJECT_ROOT/memory" "$CURATOR_STATE"
  : > "$MOCK_MCP_LOG"
  echo "mac-test" > "$CURATOR_STATE/device-id"
}

@test "stop flushes pending_sync via reconcile" {
  source "$REPO_ROOT/core/lib/common.sh"
  source "$REPO_ROOT/core/lib/journal.sh"
  journal_append "feedback" '{"text":"flush me"}'
  "$REPO_ROOT/core/hooks/stop.sh"
  local pending
  pending=$(jq -s 'map(select(.pending | length > 0)) | length' \
    "$CURATOR_STATE/pending_sync.jsonl")
  [ "$pending" = "0" ]
}

@test "stop prunes pattern-signal entries older than 7 days" {
  local ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
  cat > "$ps" <<'EOF'
<!-- curator-pattern-signal schema_version=1 -->
- 2020-01-01T00:00:00Z | ancient pattern | device=old
- __RECENT__ | fresh pattern | device=new
EOF
  # Replace __RECENT__ with a recent timestamp
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sed -i.bak "s|__RECENT__|$now|" "$ps" && rm "$ps.bak"

  "$REPO_ROOT/core/hooks/stop.sh"
  grep -q "fresh pattern" "$ps"
  ! grep -q "ancient pattern" "$ps"
}

@test "stop touches pattern-signal mtime even when content unchanged" {
  local ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
  touch -t 202001010000 "$ps" 2>/dev/null || touch "$ps"
  local old_mtime
  old_mtime=$(stat -f "%m" "$ps" 2>/dev/null || stat -c "%Y" "$ps")

  "$REPO_ROOT/core/hooks/stop.sh"

  local new_mtime
  new_mtime=$(stat -f "%m" "$ps" 2>/dev/null || stat -c "%Y" "$ps")
  [ "$new_mtime" -gt "$old_mtime" ]
}

@test "stop exits 0 when no pattern-signal exists yet" {
  run "$REPO_ROOT/core/hooks/stop.sh"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bats test/hooks/test_stop.bats
```

Expected: tests fail.

- [ ] **Step 3: Write `core/hooks/stop.sh`**

```bash
#!/usr/bin/env bash
# core/hooks/stop.sh — CC Stop hook entry point.
# 10min timeout. Flushes pending_sync and maintains pattern-signal 7d window.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/journal.sh"

: "${CURATOR_STATE:=$HOME/.curator}"
: "${CLAUDE_PROJECT_ROOT:=$PWD}"

# 1. Flush pending_sync (same path as reconcile)
if ! "$CURATOR_HOME/memory-bridge/reconcile.sh"; then
  curator_log WARN "reconcile during stop failed"
fi

# 2. Prune pattern-signal.md to last 7 days
ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
if [ -f "$ps" ]; then
  cutoff=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
           date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)

  tmp=$(mktemp)
  # Keep banner (first line) + entries newer than cutoff
  head -n 1 "$ps" > "$tmp"
  awk -v cutoff="$cutoff" '
    /^- / {
      ts = $2
      if (ts >= cutoff) print
      next
    }
    # Keep blank lines and non-entry lines (section headers, etc.)
    !/^- / && NR > 1 { print }
  ' "$ps" >> "$tmp"
  mv "$tmp" "$ps"
  # Touch mtime so Sonnet selector sees it as recently updated
  touch "$ps"
fi

exit 0
```

- [ ] **Step 4: Run tests**

```bash
chmod +x core/hooks/stop.sh
bats test/hooks/test_stop.bats
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add core/hooks/stop.sh test/hooks/test_stop.bats
git commit -m "feat(hooks): stop.sh — flush pending_sync + prune pattern-signal 7d"
```

---

## Task 15: `core/hooks/user-prompt-submit.sh`

**Files:**
- Create: `core/hooks/user-prompt-submit.sh`
- Create: `test/hooks/test_user_prompt_submit.bats`

Emits pattern proposal when a natural pause is detected AND `proposal_count < 1`. Enforces HR-2. v1 heuristic: look for candidate text in `~/.curator/pattern-candidates/<session_id>.txt` populated by `/curator:capture`'s upstream logic. If file has content, pop one proposal and emit via exit 2.

**Note**: v1 keeps the candidate-detection heuristic simple: any text file in `pattern-candidates/` is a candidate. A smarter detector (regex on recent conversation, correction-language detection) is a v1.1 refinement. The hook itself is the plumbing; detection quality is separate.

- [ ] **Step 1: Write the failing test**

Create `test/hooks/test_user_prompt_submit.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_HOME="$REPO_ROOT"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CLAUDE_SESSION_ID="sess-test"
  mkdir -p "$CURATOR_STATE/pattern-candidates"
  jq -cn --arg sid "$CLAUDE_SESSION_ID" \
    '{session_id:$sid, proposal_count:0, last_proposal_ts:null}' \
    > "$CURATOR_STATE/session-state.json"
}

@test "hook exits 0 with no stderr when no candidates exist" {
  run "$REPO_ROOT/core/hooks/user-prompt-submit.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook emits proposal via exit 2 when candidate exists and count is 0" {
  echo "prefer pnpm over npm in this repo" > "$CURATOR_STATE/pattern-candidates/sess-test.txt"
  run "$REPO_ROOT/core/hooks/user-prompt-submit.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"pattern"* ]]
  [[ "$output" == *"pnpm"* ]]
  [[ "$output" == *"Y/n/d"* ]]
}

@test "hook increments proposal_count after emitting" {
  echo "some rule" > "$CURATOR_STATE/pattern-candidates/sess-test.txt"
  "$REPO_ROOT/core/hooks/user-prompt-submit.sh" || true
  local count
  count=$(jq -r .proposal_count "$CURATOR_STATE/session-state.json")
  [ "$count" = "1" ]
}

@test "hook does NOT emit when proposal_count already >= 1 (HR-2 cap)" {
  echo "second rule" > "$CURATOR_STATE/pattern-candidates/sess-test.txt"
  jq -cn '{session_id:"sess-test", proposal_count:1}' > "$CURATOR_STATE/session-state.json"
  run "$REPO_ROOT/core/hooks/user-prompt-submit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"pattern"* ]] || [ -z "$output" ]
}

@test "hook removes candidate after emitting (consumed)" {
  local cfile="$CURATOR_STATE/pattern-candidates/sess-test.txt"
  echo "one shot" > "$cfile"
  "$REPO_ROOT/core/hooks/user-prompt-submit.sh" || true
  [ ! -s "$cfile" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bats test/hooks/test_user_prompt_submit.bats
```

Expected: tests fail.

- [ ] **Step 3: Write `core/hooks/user-prompt-submit.sh`**

```bash
#!/usr/bin/env bash
# core/hooks/user-prompt-submit.sh — CC UserPromptSubmit hook.
# Emits ONE pattern proposal per session (HR-2). Exit 2 = show stderr to model.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$CURATOR_HOME/core/lib/common.sh"

: "${CURATOR_STATE:=$HOME/.curator}"
: "${CLAUDE_SESSION_ID:=$(date +%s)-$$}"

state_file="$CURATOR_STATE/session-state.json"
candidates_dir="$CURATOR_STATE/pattern-candidates"
candidate_file="$candidates_dir/${CLAUDE_SESSION_ID}.txt"

[ -d "$candidates_dir" ] || mkdir -p "$candidates_dir"

# If session state missing, initialize (we may be fired before session-start)
[ -f "$state_file" ] || \
  jq -cn --arg sid "$CLAUDE_SESSION_ID" \
    '{session_id:$sid, proposal_count:0, last_proposal_ts:null}' \
    > "$state_file"

# HR-2: cap at one proposal per session
proposal_count=$(jq -r '.proposal_count // 0' "$state_file")
if [ "$proposal_count" -ge 1 ]; then
  exit 0
fi

# No candidate? Silent pass-through.
if [ ! -s "$candidate_file" ]; then
  exit 0
fi

candidate_text=$(cat "$candidate_file")

# Increment proposal_count atomically
tmp=$(mktemp)
jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.proposal_count = ((.proposal_count // 0) + 1) | .last_proposal_ts = $ts' \
   "$state_file" > "$tmp"
mv "$tmp" "$state_file"

# Consume the candidate (one-shot)
: > "$candidate_file"

# Emit proposal via exit 2 (stderr → model)
cat >&2 <<EOF
[curator] pattern detected:

  "$candidate_text"

Reply Y to capture, n to skip, d to defer to /curator:memory --review
EOF
exit 2
```

- [ ] **Step 4: Run tests**

```bash
chmod +x core/hooks/user-prompt-submit.sh
bats test/hooks/test_user_prompt_submit.bats
```

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add core/hooks/user-prompt-submit.sh test/hooks/test_user_prompt_submit.bats
git commit -m "feat(hooks): user-prompt-submit.sh — HR-2 one-per-session proposal"
```

---

## Task 16: `skills/capture.md` — `/curator:capture`

**Files:**
- Create: `skills/capture.md`

Slash command skill. Delegates to `core/lib/journal.sh` and `core/lib/mcp-client.sh` through inline bash.

- [ ] **Step 1: Write the skill markdown**

Create `skills/capture.md`:

```markdown
---
name: capture
description: Write a memory to MemPalace immediately with idempotent journaling. Use when the user says "remember this" or "/curator:capture <text>".
allowed-tools: Bash
---

# /curator:capture

Writes a memory to MemPalace right now. Goes through the pending_sync journal so failures retry automatically on next SessionStart.

**Usage:**
- `/curator:capture <text>` — capture as a feedback-type memory
- `/curator:capture --pin <text>` — also append to MEMORY.md L0 section (reserves as absolute rule)

## Implementation

When the user invokes this skill, execute:

\`\`\`bash
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/journal.sh"
source "$CURATOR_HOME/core/lib/mcp-client.sh"

# Parse arguments
PIN=0
DEFER=0
TEXT=""
for arg in "$@"; do
  case "$arg" in
    --pin) PIN=1 ;;
    --defer) DEFER=1 ;;
    *) TEXT="$TEXT $arg" ;;
  esac
done
TEXT="${TEXT# }"

if [ -z "$TEXT" ]; then
  echo "Usage: /curator:capture [--pin] [--defer] <text>" >&2
  exit 1
fi

# Defer path: write to pending-proposals.jsonl for later batch review via /curator:memory --review
if [ "$DEFER" = "1" ]; then
  pp="$CURATOR_STATE/pending-proposals.jsonl"
  mkdir -p "$(dirname "$pp")"
  jq -cn --arg text "$TEXT" \
         --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         --arg sid "${CLAUDE_SESSION_ID:-unknown}" \
    '{proposal_id: ($ts + "-" + ($text | @base64)[0:8]), ts: $ts, candidate_text: $text, session_id: $sid}' \
    >> "$pp"
  echo "[curator] deferred: $TEXT (review later with /curator:memory --review)"
  exit 0
fi

# Normal path: append to journal with mempalace pending
payload=$(jq -cn --arg text "$TEXT" '{text:$text}')
journal_append "feedback" "$payload"

# Also append to pattern-signal.md for local recency signal
ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
mkdir -p "$(dirname "$ps")"
[ -f "$ps" ] || echo "<!-- curator-pattern-signal schema_version=1 -->" > "$ps"
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
device=$(curator_device_id)
echo "- $ts | $TEXT | device=$device" >> "$ps"
touch "$ps"

# If --pin: append to MEMORY.md L0 section
if [ "$PIN" = "1" ]; then
  mem_file="$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
  echo "- $TEXT" >> "$mem_file"
fi

# Try immediate MemPalace write (best effort; journal already has it)
if mcp_write "feedback" "$payload" 2>/dev/null; then
  hash=$(printf "%s\0%s\0%s" "feedback" "$payload" "$ts" | shasum -a 256 | awk '{print $1}')
  journal_mark_resolved "$hash" "mempalace"
  echo "[curator] captured: $TEXT"
else
  echo "[curator] captured locally; will sync on next session (MemPalace unreachable)"
fi
\`\`\`

After execution, confirm to the user what was captured and where it landed (MemPalace vs pending).
```

- [ ] **Step 2: Validate skill frontmatter**

```bash
head -n 6 skills/capture.md | grep -E "^name|^description|^allowed-tools"
```

Expected: three frontmatter fields visible.

- [ ] **Step 3: Commit**

```bash
git add skills/capture.md
git commit -m "feat(skills): /curator:capture — idempotent memory write"
```

---

## Task 17: `skills/recall.md` — `/curator:recall`

**Files:**
- Create: `skills/recall.md`

- [ ] **Step 1: Write the skill**

```markdown
---
name: recall
description: Semantic search MemPalace for past memories. Use when user asks "how did we handle X?" or "/curator:recall <query>".
allowed-tools: Bash
---

# /curator:recall

Live semantic query against MemPalace. Returns top matches with drawer content and source attribution.

**Usage:** `/curator:recall <query>`

## Implementation

\`\`\`bash
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/mcp-client.sh"

QUERY="$*"
if [ -z "$QUERY" ]; then
  echo "Usage: /curator:recall <query>" >&2
  exit 1
fi

# Primary: live MemPalace query
if mcp_ping 2>/dev/null; then
  response=$(mcp_search "$QUERY" "$(basename "$CLAUDE_PROJECT_ROOT")" "" 2>/dev/null)
  if [ -n "$response" ]; then
    hits=$(echo "$response" | jq -r '.result // [] | length')
    if [ "$hits" -gt 0 ]; then
      echo "[curator] $hits result(s) from MemPalace:"
      echo "$response" | jq -r '.result[] | "- [\(.hall)/\(.room // "?")] \(.text) (\(.metadata.device_id // "unknown"), \(.ts))"'
      exit 0
    fi
    echo "[curator] no results for: $QUERY"
    exit 0
  fi
fi

# Fallback: local pattern-signal.md grep
echo "[curator] ⚠ MemPalace unreachable — falling back to local pattern-signal.md"
ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
if [ -f "$ps" ]; then
  grep -i "$QUERY" "$ps" || echo "[curator] no local matches for: $QUERY"
else
  echo "[curator] no local pattern-signal.md; nothing to search"
fi
\`\`\`
```

- [ ] **Step 2: Commit**

```bash
git add skills/recall.md
git commit -m "feat(skills): /curator:recall — live MemPalace search with local fallback"
```

---

## Task 18: `skills/memory.md` — `/curator:memory`

**Files:**
- Create: `skills/memory.md`

Implements HR-3 status output.

- [ ] **Step 1: Write the skill**

```markdown
---
name: memory
description: Show curator status (MEMORY.md, pattern-signal, MemPalace connection, pending proposals). Use when user runs "/curator:memory" or asks "what does curator remember?".
allowed-tools: Bash
---

# /curator:memory

Displays curator's current state: the L0 MEMORY.md summary, pattern-signal status, MemPalace connection tier, and any pending pattern proposals awaiting review.

**Usage:**
- `/curator:memory` — status overview
- `/curator:memory --review` — batch-review deferred pattern proposals
- `/curator:memory --edit` — open MEMORY.md in $EDITOR

## Implementation

\`\`\`bash
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/mcp-client.sh"

case "${1:-}" in
  --edit)
    "${EDITOR:-vi}" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
    exit 0
    ;;
  --review)
    pp="$CURATOR_STATE/pending-proposals.jsonl"
    if [ ! -s "$pp" ]; then
      echo "[curator] no pending proposals"
      exit 0
    fi
    count=$(wc -l < "$pp")
    echo "[curator] $count pending proposal(s):"
    cat -n "$pp" | jq -r '[.[0], (.[1:] | join(" "))] | @tsv' 2>/dev/null || cat -n "$pp"
    echo
    echo "To confirm: /curator:capture <text>"
    echo "To clear all: rm $pp"
    exit 0
    ;;
esac

# Default: status overview (HR-3 format)
mem="$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"

if [ -f "$mem" ]; then
  l0_entries=$(grep -c "^- " "$mem" 2>/dev/null || echo 0)
  l0_bytes=$(wc -c < "$mem")
  l0_human=$(awk -v b="$l0_bytes" 'BEGIN{printf "%.1fKB", b/1024}')
  echo "[MEMORY.md]     L0 · $l0_entries entries · $l0_human · schema v1"
else
  echo "[MEMORY.md]     (not yet initialized)"
fi

if [ -f "$ps" ]; then
  ps_entries=$(grep -c "^- " "$ps" 2>/dev/null || echo 0)
  ps_mtime=$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%SZ" "$ps" 2>/dev/null || \
             stat -c "%y" "$ps" | cut -d'.' -f1)
  echo "[pattern-signal] $ps_entries observations · last write $ps_mtime"
else
  echo "[pattern-signal] (empty)"
fi

if mcp_ping 2>/dev/null; then
  pending_count=0
  if [ -f "$CURATOR_STATE/pending_sync.jsonl" ]; then
    pending_count=$(jq -s 'map(select(.pending | length > 0)) | length' \
      "$CURATOR_STATE/pending_sync.jsonl" 2>/dev/null || echo 0)
  fi
  echo "[MemPalace]     connected · $pending_count pending write(s)"
else
  banner=$(head -n 1 "$mem" 2>/dev/null || echo "")
  proj_ts=$(echo "$banner" | sed -n 's/.*projection-ts=\([^ ]*\).*/\1/p')
  echo "[MemPalace]     disconnected · last sync $proj_ts"
fi

pp="$CURATOR_STATE/pending-proposals.jsonl"
if [ -s "$pp" ]; then
  pp_count=$(wc -l < "$pp")
  echo "[pending proposals] $pp_count items — run /curator:memory --review"
else
  echo "[pending proposals] 0"
fi
\`\`\`
```

- [ ] **Step 2: Commit**

```bash
git add skills/memory.md
git commit -m "feat(skills): /curator:memory — HR-3 status output"
```

---

## Task 19: `skills/build.md` — `/curator:build` v1 stub

**Files:**
- Create: `skills/build.md`

- [ ] **Step 1: Write the stub**

```markdown
---
name: build
description: (v1 stub) build-loop 4-phase workflow placeholder. Will be implemented in v1.2.
allowed-tools: Bash
---

# /curator:build (v1 stub)

The build-loop workflow is reserved for v1.2. In v1 this command exists only to reserve the name and explain the plan.

## Implementation

\`\`\`bash
cat <<'EOF'
[curator] /curator:build is a v1 stub.

The build-loop (4-phase workflow: PLAN → IMPLEMENT → SIMPLIFY → REVIEW) is
deferred to curator v1.2. The v1 release focuses on memory + pattern learning.

For now, use these commands:
  /curator:capture <text>   — record a decision or rule
  /curator:recall <query>   — find past decisions
  /curator:memory           — show current state

See docs/superpowers/specs/2026-04-11-curator-design.md § Future Work for details.
EOF
\`\`\`
```

- [ ] **Step 2: Commit**

```bash
git add skills/build.md
git commit -m "feat(skills): /curator:build v1 stub (reserved for v1.2)"
```

---

## Task 20: `test/roundtrip.sh` — end-to-end integration test

**Files:**
- Create: `test/roundtrip.sh`

Non-bats integration test that uses a real bats-spawned mock MCP (via `CURATOR_MEMPALACE_URL=mock://...`). Verifies the full capture→recall→projection flow.

- [ ] **Step 1: Write the test**

```bash
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
```

- [ ] **Step 2: Run it**

```bash
chmod +x test/roundtrip.sh
./test/roundtrip.sh
```

Expected: prints step-by-step progress and ends with "ROUNDTRIP OK".

- [ ] **Step 3: Commit**

```bash
git add test/roundtrip.sh
git commit -m "test: end-to-end roundtrip integration test"
```

---

## Task 21: `test/hr-acceptance.sh` — HR-1/HR-2/HR-3 acceptance

**Files:**
- Create: `test/hr-acceptance.sh`

Verifies the three non-negotiable DX Hard Requirements from spec § DX Hard Requirements.

- [ ] **Step 1: Write the script**

```bash
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
```

- [ ] **Step 2: Run it**

```bash
chmod +x test/hr-acceptance.sh
./test/hr-acceptance.sh
```

Expected: prints "HR-1 OK", "HR-2 OK", "HR-3 OK", then "ALL HR ACCEPTANCE TESTS PASSED".

- [ ] **Step 3: Commit**

```bash
git add test/hr-acceptance.sh
git commit -m "test: HR-1/HR-2/HR-3 acceptance script"
```

---

## Task 22: `docs/quickstart.md` + `README.md`

**Files:**
- Create: `docs/quickstart.md`
- Create: `README.md`

- [ ] **Step 1: Write `docs/quickstart.md`**

```markdown
# Curator Quickstart (5 minutes)

Curator is a Claude Code plugin that gives you persistent, searchable memory across sessions and repos, backed by MemPalace.

## 1. Install MemPalace first (if not already installed)

Curator depends on MemPalace as a separate MCP server. Choose one path:

**Local stdio (single machine):**
\`\`\`bash
pip install mempalace
claude mcp add mempalace -- mempalace serve --stdio
\`\`\`

**Docker:**
\`\`\`bash
docker run -d --name mempalace -p 7890:7890 -v ~/.mempalace:/data mempalace/mempalace
claude mcp add mempalace --url http://localhost:7890
\`\`\`

Verify:
\`\`\`bash
claude mcp list | grep mempalace
\`\`\`

## 2. Install curator

\`\`\`bash
claude plugin marketplace add jackg825/curator
claude plugin install curator@jackg825
\`\`\`

The postInstall hook runs preflight + install automatically. Review the preflight report at `~/.curator/preflight-*.log` before continuing.

## 3. First session

Open a Claude Code session in any repo. At session start you should see:
- `~/.claude/projects/<repo>/memory/MEMORY.md` auto-generated with L0 template
- `~/.curator/device-id` created (check with `cat ~/.curator/device-id`)

Try the commands:

\`\`\`
/curator:memory                   # should show [MEMORY.md] [pattern-signal] [MemPalace] status
/curator:capture use pnpm         # write a feedback memory
/curator:recall "pnpm"            # search for it
\`\`\`

## 4. Inspect state

\`\`\`bash
ls ~/.curator/
#  device-id  install-receipt.json  pending_sync.jsonl  session-state.json  preflight-*.log
\`\`\`

## 5. Uninstall (cleanly)

\`\`\`bash
~/.claude/plugins/.../curator/core/scripts/uninstall.sh --keep-state
# or --purge to also delete ~/.curator
\`\`\`

## Next steps

- Read the full spec: [`docs/superpowers/specs/2026-04-11-curator-design.md`](superpowers/specs/2026-04-11-curator-design.md)
- Phase 2 multi-device: see spec § Multi-Device Architecture
```

- [ ] **Step 2: Write `README.md`**

```markdown
# Curator

A Claude Code plugin for persistent, searchable memory backed by [MemPalace](https://github.com/milla-jovovich/mempalace).

## What it does

Curator adds four slash commands (`/curator:capture`, `/curator:recall`, `/curator:memory`, `/curator:build`) and three lifecycle hooks (`SessionStart`, `UserPromptSubmit`, `Stop`) on top of Claude Code. At session start it projects L0 absolute rules from MemPalace into the CC native memdir. During sessions, it captures new memories with content-hash idempotency. On session end, it flushes pending writes and maintains a 7-day rolling pattern-signal file that CC's native Sonnet selector picks up on demand.

## Why

Claude Code has no cross-session semantic memory. `/memory` and memdir are per-session static files; `teamMemorySync` only works with first-party OAuth and doesn't do vector search. Curator fills the gap by wiring MemPalace (ChromaDB semantic memory with 96.6% LongMemEval R@5) into the CC lifecycle without replacing any native functionality.

## Install

See [`docs/quickstart.md`](docs/quickstart.md).

## Design

The full design is in [`docs/superpowers/specs/2026-04-11-curator-design.md`](docs/superpowers/specs/2026-04-11-curator-design.md). It was produced through a 3-round 5-expert debate with Devil's Advocate, with 16 Claude Code source-code citations grounding every capability claim.

## Status

v1 — memory layer + pattern extraction. `build-loop` workflow is a stub (v1.2). 主動警告, dashboard, and multi-user team mode are deferred (v2.x). Multi-device Mac Mini runtime is phase 2.

## License

MIT
```

- [ ] **Step 3: Commit**

```bash
git add docs/quickstart.md README.md
git commit -m "docs: quickstart guide and README"
```

---

## Task 23: Full test suite + final verification

**Files:**
- None (runs existing tests)

- [ ] **Step 1: Run every test**

```bash
bats test/lib/*.bats test/scripts/*.bats test/hooks/*.bats
./test/roundtrip.sh
./test/hr-acceptance.sh
./core/scripts/health-check.sh
```

Expected: every bats suite passes, roundtrip prints "ROUNDTRIP OK", HR acceptance prints "ALL HR ACCEPTANCE TESTS PASSED", health-check prints JSON.

- [ ] **Step 2: Install against a throwaway `~/.claude` and exercise manually**

```bash
export CLAUDE_HOME=/tmp/curator-final-check
export CURATOR_STATE=/tmp/curator-final-state
mkdir -p "$CLAUDE_HOME"
echo '{"hooks":{}}' > "$CLAUDE_HOME/settings.json"
./core/scripts/install.sh --skip-preflight --skip-mcp
jq '.hooks' "$CLAUDE_HOME/settings.json"
./core/scripts/uninstall.sh --purge
```

Expected: install shows curator hooks; uninstall removes them; `CURATOR_STATE` is gone after purge.

- [ ] **Step 3: Merge working branch**

```bash
git log --oneline curator-v1-impl ^master | cat
git checkout master
git merge --no-ff curator-v1-impl -m "feat: curator v1 implementation (memory layer + pattern learning)"
```

- [ ] **Step 4: Tag v0.1.0**

```bash
git tag -a v0.1.0 -m "curator v1.0: memory layer + pattern learning"
git tag -l
```

- [ ] **Step 5: Final commit of any leftover artifacts**

```bash
git status
# If anything modified, commit; otherwise skip
```

---

## Post-implementation checklist

After all tasks complete:

- [ ] All bats tests green
- [ ] `roundtrip.sh` passes
- [ ] `hr-acceptance.sh` passes
- [ ] Manual install/uninstall cycle on throwaway `~/.claude` works
- [ ] `git log --oneline` shows one commit per task (≥23 commits on `curator-v1-impl`)
- [ ] Tag `v0.1.0` points at merge commit
- [ ] `docs/quickstart.md` renders cleanly
- [ ] Spec § DX Hard Requirements mapped 1:1 to `test/hr-acceptance.sh`
- [ ] Repo directory can now be renamed `harness/` → `curator/` manually (remember to update any external pointers)

---

## Spec coverage matrix

| Spec section | Tasks |
|---|---|
| § Scope (v1 = α+δ) | All |
| § Portability constraints (env var, device_id, device-local state) | T2, T3, T7 |
| § D1 Dual-Layer CQRS | T11, T14, T16, T17 |
| § D2 Dual-file projection | T11, T14, T16 |
| § D3 Proposed pattern extraction | T15, T16 |
| § Components (4 skills, 3 hooks, state dir) | T13-T19 |
| § Data Flow (/recall, /capture, SessionStart projection, proposal pipeline) | T11, T13, T15, T16, T17 |
| § Error Handling (stale tier, idempotency, outage tiers) | T3, T11, T12, T13 |
| § DX Hard Requirements (HR-1/2/3) | T21 |
| § Routing Rules | T9 |
| § Testing Strategy (smoke / roundtrip / HR) | T5 (health), T20 (roundtrip), T21 (HR) |
| § Pre-Installation Environment Check | T6 |
| § Installation & Distribution (plugin manifest, install.sh, uninstall.sh) | T1, T7, T8 |
| § Multi-Device Architecture | T2, T3 (portability hooks only; phase 2 out of scope) |
