# Curator — v1 Design

**Date:** 2026-04-11
**Status:** Draft (pending user review)
**Supersedes:** `docs/superpowers/specs/2026-04-10-harness-workflow-design.md` (v1 draft, retracted)
**Authors:** Jack Chung + 5-expert panel (memory-engineer, cc-internals-expert, dx-designer, reliability-engineer, platform-architect)

---

## Overview

Curator is a portable Claude Code workflow layer that adds **persistent, searchable, cross-repo memory** and **structured pattern learning** to Claude Code sessions. It is NOT a fork of Claude Code. It is a package of skills, commands, hooks, and a small state directory that rides on top of Claude Code's existing `memdir/`, hook system, and MCP support.

The memory substrate is **MemPalace** (ChromaDB-based local semantic memory with `wings/halls/rooms` structure, accessed via MCP). Curator projects MemPalace data into `memdir/` files at SessionStart and captures new memories through Claude Code's `Stop` hook.

Curator replaces a retracted earlier draft (`2026-04-10-harness-workflow-design.md`, then named "harness"), which was produced before reading Claude Code source code and contained several false premises about Claude Code capabilities. The rename from "harness" to "curator" happened alongside this redesign because the term "harness" is too generic.

---

## Why This Redesign

Source-code exploration of `/Users/jackchung/Workspace/GitHub/claude-source-code` invalidated five premises from the retracted draft:

| Retracted-draft claim | Source-code reality |
|---|---|
| "Only 4 hook event types, synchronous, blocking" | 26 user-space hook events via `settings.json`; `AsyncHookRegistry` with `asyncRewake:true` exists (`entrypoints/sdk/coreTypes.ts:25-53`, `utils/hooks/hooksConfigManager.ts`) |
| "CC has no internal event bus" | `utils/hooks/hookEvents.ts` with 100-event buffer |
| "CC has no semantic memory infrastructure" | Partial: `memdir/findRelevantMemories.ts:39-75` is a Sonnet-based keyword selector (not vector). True semantic gap exists; MemPalace fills it. |
| "Need custom cost tracking" | `cost-tracker.ts` (323 lines) with per-model session-restore |
| "Need custom rate-limit handling" | `services/api/withRetry.ts:170-299` with cascade + persistent retry mode |

Two additional discoveries shaped v2:

1. **`SessionEnd` hook has a 1.5s hard timeout** with silently-ignored exceptions (`utils/hooks.ts:175`, `utils/gracefulShutdown.ts:479`). It cannot be used for network writes. **Curator uses `Stop` hook** (10-minute timeout, blocking-capable).
2. **`memdir/memoryScan.ts:72` sorts memory files by `mtimeMs`** and `formatMemoryManifest()` includes ISO timestamps. Claude Code's native Sonnet selector already consumes recency signal. Curator does not need to build its own hot-tier loader — it only needs to write a separate memdir file.

---

## Scope (v1)

**v1 = α + δ**: complete memory layer with user-confirmed pattern extraction, **no build-loop workflow**.

### In-scope

- Dual-layer CQRS: MemPalace as canonical store, `memdir/` as projection cache
- Four slash commands: `/capture`, `/recall`, `/memory`, `/build` (placeholder)
- Four hooks: `SessionStart`, `UserPromptSubmit`, `Stop`, and reserved `PreToolUse` (v2.1)
- Pattern extraction via `UserPromptSubmit` proposal pipeline (one-at-a-time, deferrable)
- Stale projection visibility with 3-tier alerting
- Idempotent dual-write via `~/.curator/pending_sync.jsonl` with SHA-256 content hash
- Declarative routing rules via `routing-rules.yaml` + `yq` interpreter
- **Preflight check** (`preflight-check.sh`) that detects hook-slot, skill-name, and memdir collisions before any install
- **Installer** (`install.sh`) that does mandatory memdir backup, symlinks skills, appends hooks via `jq` patches (preserves existing entries), registers MemPalace MCP, generates device-id, writes install receipt
- **Uninstaller** (`uninstall.sh`) that reads the install receipt and reverses changes cleanly
- **Claude Code plugin manifest** (`.claude-plugin/plugin.json`) for one-command install via `claude plugin install curator@jackg825`
- **Phase 2 portability hooks**: `CURATOR_MEMPALACE_URL` env var, `device_id` field in all writes, device-local state directory

### Out of scope (deferred)

- **Build-loop workflow** (`/build` is reserved as a stub; implementation deferred to v1.2)
- **v2.1 PreToolUse reverse-pattern match** (主動警告) — extension point preserved
- **v2.2 Learning dashboard** — requires event log schema which v1 ships but no UI
- **v2.3 Multi-user team mode** — adapter interface preserves namespace parameter
- **v3 Mac Mini remote agent runtime** — separate phase

### Non-goals

- Curator does not replicate MemPalace functionality. Semantic search always goes through MemPalace MCP.
- Curator does not parse Claude Code internal state. It only writes to `memdir/` via normal filesystem operations.
- Curator does not try to recover from a corrupted MemPalace database. That is MemPalace's responsibility.

### Portability constraints (must hold in v1)

These three constraints preserve the phase 2 multi-device path. v1 must not violate them even if it doesn't yet use them.

1. **MemPalace connection URL is environment-variable driven.** `CURATOR_MEMPALACE_URL` (default `stdio` or `http://localhost:<port>`) — never hardcoded. Phase 2 switches this to a Tailscale IP pointing at the Mac Mini without any code change.
2. **Every write carries a `device_id` field.** Read from `~/.curator/device-id` (auto-generated from `hostname -s + 4-char random suffix` at install time). v1 records this field but does nothing with it. Phase 2 uses it for cross-device provenance.
3. **Curator state (`~/.curator/`) is device-local, not synced.** Only MemPalace is shared across devices. Never put `pending_sync.jsonl` or `session-state.json` in iCloud Drive / Dropbox / Syncthing. Phase 2 relies on each device having its own journal.

---

## Architecture Decisions

This section records the three architectural decisions from the Phase 5 Decision Matrix. Each was debated across 3 rounds by 5 experts.

### D1 — Dual-Layer CQRS (Approach B)

**MemPalace is the canonical source of truth. `memdir/` is a per-session projection cache. Curator owns the projection logic and the slash command surface.**

| Alternative | Rejected because |
|---|---|
| **A: MemPalace-as-Backbone** | Every SessionStart is a blocking MCP call. MemPalace outage = complete amnesia. Complexity leaks to user (they must debug MCP when it fails). |
| **C: curator-inside-MemPalace** | Ties curator to MemPalace release cadence. No home for build-loop (even if deferred). Loses independent evolution. |

**Why B wins**:

1. **Offline degradation**: MemPalace outage → curator falls back to stale `memdir/` cache. User still has partial context.
2. **Encapsulated complexity**: The projection logic, dual-write idempotency, and stale detection live inside curator. The user-facing interface (`/capture`, `/recall`, `/memory`) is identical regardless of MemPalace availability.
3. **Extension points**: A curator-owned JSONL event log + `MemoryAdapter` interface allow v2.1/v2.2/v2.3 to plug in without forking MemPalace.

**Key constraint**: `teamMemorySync` (`services/teamMemorySync/index.ts:151-161`) only works with first-party OAuth. API-key users get nothing. This is the source-code-verified reason why curator cannot delegate cross-repo shared memory to Claude Code itself.

---

### D2 — Dual-File Projection (Option vii)

**`memdir/MEMORY.md` stores L0 only (absolute rules, ~2-5KB, ≤30 lines). A separate `memdir/pattern-signal.md` stores 7-day rolling pattern observations and is read on-demand by Claude Code's native Sonnet selector.**

| Alternative | Rejected because |
|---|---|
| **(i) L0+L1 only** | L1 detail in MEMORY.md adds 5-10KB of mixed-priority content, diluting the signal Claude reads at session start |
| **(ii) L0+L1 + 7d hot in MEMORY.md** | Signal dilution: Claude cannot distinguish "absolute red line" from "historical case" when both are in the same file |
| **(iii) Aggressive (~20-25KB)** | Approaches the `MAX_ENTRYPOINT_BYTES = 25_000` hard cap (`memdir/memdir.ts:38`). Auto-truncation is a silent data-loss path. |
| **(iv) L0 only (no pattern-signal)** | Kills v2 pattern extraction recency signal. Forces full MemPalace semantic search on every session — slow and coupling-heavy. |

**Why (vii) wins — the critical source-code insight**:

`memdir/memoryScan.ts:72` sorts `memdir/` files by `mtimeMs` descending. `formatMemoryManifest()` at lines 84-94 emits each memory file with its ISO timestamp. `findRelevantMemories.ts:39-75` passes this manifest to a Sonnet sidecar that selects up to 5 relevant files per query.

**This means recency signal is already handled by Claude Code natively.** Curator does not need to build a hot-tier loader. `pattern-signal.md` is just a regular `memdir/` file that:

- Gets touched (`mtime` updated) by the `Stop` hook whenever pattern observations are written
- Is ranked higher by the native Sonnet selector because of its recent `mtime`
- Is picked up ONLY when a user query is semantically relevant — it never auto-injects into every session's ambient context
- Has a 7-day rolling window enforced by a `Stop` hook cleanup pass

**This satisfies DX HR-1** (hot-cache must not pollute `MEMORY.md` ambient context) **automatically**, because `memdir/` files are not `MEMORY.md` includes — they are the selector's candidate pool.

---

### D3 — Proposed Pattern Extraction with One-at-a-Time UX (Option ii)

**Pattern extraction is automatic but always user-confirmed. The proposal pipeline has hard UX constraints to prevent session-end review fatigue.**

| Alternative | Rejected because |
|---|---|
| **(i) Pure manual** | Misses implicit patterns the user would never think to `/capture` manually. Hit rate too low for Priority 3 「對話即學習」 |
| **(iii) Auto + quarantine** | Background extraction violates the "don't let AI decide what's worth remembering" philosophy. Quarantine cleanup becomes maintenance burden. Risks polluting MemPalace embedding space even when quarantined. |

**Why (ii) wins**:

1. AI proposes (addresses Priority 3 auto-capture), user confirms (preserves trust and control).
2. Compatible with MemPalace author philosophy when framed as "AI helper to user intent" rather than "AI auto-curator".
3. Rollback is trivial: `reject` just drops the proposal; no background state to clean up.

**Hard UX Requirements (DX HR-2)**:

- **Maximum one proposal per session**. Not per `UserPromptSubmit`, not per tool call — per entire session. This is enforced by a session-level counter in `~/.curator/session-state.json`.
- **Proposal appears at a natural pause point**: after a tool call completes and Claude is waiting for user instruction. NOT at `SessionEnd`. NOT mid-subtask.
- **Three responses**:
  - `Y` → `/capture` immediately writes to MemPalace and updates `pattern-signal.md`
  - `n` → drop, no record
  - `d` → defer to pending queue; shows up in next `/memory` invocation for batch review
- **Violating any of the above reverts D3 to option (i) by user expectation** — the constraints are not optional implementation details.

---

## Architecture Diagram

```
                    ┌────────────────────────────────────┐
                    │    MemPalace MCP (external)        │
                    │    ChromaDB + wings/halls/rooms    │
                    │    CANONICAL SOURCE OF TRUTH       │
                    └────────────┬───────────────────────┘
                                 │
                ┌────────────────┼────────────────┐
                │                │                │
          live query       projection        verbatim write
           (/recall)       (SessionStart)      (Stop hook)
                │                │                │
                ▼                ▼                ▲
┌─────────────────────────────────────────────────────────────┐
│  Claude Code native machinery (curator does not replace)    │
│                                                              │
│  memdir/MEMORY.md                                           │
│    L0 only — ~2-5KB, ≤30 lines                              │
│    project identity + absolute rules                        │
│    auto-loaded into every session                           │
│    maintained by /capture (pinned writes) + user edits      │
│                                                              │
│  memdir/pattern-signal.md                                   │
│    7-day rolling pattern observations                       │
│    NOT in MEMORY.md include chain                           │
│    picked up by findRelevantMemories Sonnet selector        │
│    ranked via mtime (memoryScan.ts:72)                      │
│                                                              │
│  Claude Code hooks (settings.json registered)               │
│    SessionStart / UserPromptSubmit / Stop / (PreToolUse)    │
└─────────────────────────────────────────────────────────────┘
                ▲                                ▲
                │                                │
    ┌───────────┴──────────┐          ┌─────────┴──────────┐
    │   curator skills     │          │  curator state     │
    │   + commands         │          │  ~/.curator/       │
    │                      │          │                    │
    │   /capture           │          │  pending_sync.jsonl│
    │   /recall            │          │  session-state.json│
    │   /memory            │          │  events/*.jsonl    │
    │   /build (stub)      │          │  routing-rules.yaml│
    └──────────────────────┘          └────────────────────┘
```

---

## Components

### Slash Commands (4)

| Command | Purpose | Implementation |
|---|---|---|
| `/capture [text]` | Write a memory now. Optionally `--pin` to also write to L0. | MCP write to MemPalace; if `--pin`, also append to `MEMORY.md` L0 section |
| `/recall [query]` | Semantic query against MemPalace. Returns top-5 results with citations. | Direct MCP call (`mempalace.search`) |
| `/memory` | Show current state: `MEMORY.md` contents, `pattern-signal.md` status, MemPalace connection, pending proposals queue | Pure local read |
| `/build` | **v1 stub**. Displays "build-loop deferred to v1.2" message. Reserves the command name. | Markdown-only skill |

**Hard constraint (DX)**: No additional commands may ship in v1. Any fifth command must pass "user still remembers it 3 months later" justification.

### Hooks (registered via `settings.json`)

| Hook | Timing | Purpose | Timeout |
|---|---|---|---|
| `SessionStart` | session begin | Run L0 projection from MemPalace → `MEMORY.md`; verify MemPalace reachable; compute stale-tier; scan `pending_sync.jsonl` for retry | 15s (non-blocking) |
| `UserPromptSubmit` | before each user message is processed | Detect natural pause; if pattern candidate exists AND session counter < 1, emit proposal inline | 10min (blocking; exit 2 injects proposal text) |
| `Stop` | right before Claude concludes response | Flush `pending_sync.jsonl` to MemPalace; prune `pattern-signal.md` entries older than 7 days (rolling window maintenance); update `mtime` for Sonnet selector | 10min (blocking; can return exit 2) |
| `PreToolUse` | **reserved for v2.1** | 主動警告 reverse-pattern match | 10min (blocking) |

**Why `Stop` not `SessionEnd`**: `SESSION_END_HOOK_TIMEOUT_MS_DEFAULT = 1500` (`utils/hooks.ts:175`) is a 1.5-second hard cap. `SessionEnd` exceptions are caught and silently ignored in `utils/gracefulShutdown.ts:479`. Network writes are infeasible there. `Stop` inherits `TOOL_HOOK_EXECUTION_TIMEOUT_MS = 10 * 60 * 1000` (`utils/hooks.ts:166`) and supports exit code 2.

### Curator State Directory (`~/.curator/`)

| File | Purpose | Format |
|---|---|---|
| `device-id` | Stable device identifier. Generated once at install time (`hostname -s + random suffix`), never rotated. | Single-line plain text, e.g., `macbook-k3x7` |
| `pending_sync.jsonl` | Append-only journal of writes that have not yet reached MemPalace. SessionStart scans this for retry. | One JSON object per line with `content_hash` (SHA-256) as idempotency key, `ts`, `device_id`, `payload`, `written_to`, `pending` array |
| `pending-proposals.jsonl` | Deferred pattern proposals awaiting batch review. `/memory --review` reads this. | JSONL with `proposal_id`, `ts`, `candidate_text`, `session_id` |
| `session-state.json` | Per-session ephemeral state: proposal counter, last proposal timestamp | Single JSON object, overwritten each SessionStart |
| `events/session-<id>.jsonl` | Per-session event log for v2.2 dashboard. v1 writes this but does not read it. | JSONL with `schema_version: 1` header line |
| `routing-rules.yaml` | Declarative rules that map memory type → destination (native / mempalace / both / priority). Interpreted by `router.sh` using `yq`. | See "Routing Rules" below |
| `routing-rules.d/` | Plugin-contributed rule files (merged by interpreter, lower priority than core) | Directory of `.yaml` files |

### Directory Layout (Repository)

```
curator/
├── .claude-plugin/
│   └── plugin.json                  # CC plugin manifest (name, version, postInstall)
├── core/
│   ├── hooks/
│   │   ├── session-start.sh         # L0 projection, stale check, pending_sync scan
│   │   ├── user-prompt-submit.sh    # Pattern proposal emitter
│   │   └── stop.sh                  # Flush pending_sync, prune pattern-signal 7d window
│   ├── scripts/
│   │   ├── preflight-check.sh       # Scan ~/.claude for collisions, abort on conflict
│   │   ├── install.sh               # jq-patch settings.json, symlink skills, register MCP
│   │   ├── uninstall.sh             # Reverse install via install-receipt.json
│   │   └── health-check.sh          # Used by install.sh and /memory
│   └── templates/
│       ├── MEMORY.md.template       # L0 bootstrap template
│       └── settings.json.patch.json # jq patch applied to existing settings.json
├── memory-bridge/
│   ├── router.sh                    # yq-based interpreter (~30 lines)
│   ├── project.sh                   # SessionStart L0 projection logic
│   ├── reconcile.sh                 # pending_sync.jsonl retry on SessionStart
│   ├── routing-rules.yaml           # Core routing rules
│   └── adapter-interface.md         # MemoryAdapter contract (Day 1 frozen)
├── skills/
│   ├── capture.md                   # /capture command definition
│   ├── recall.md                    # /recall command definition
│   ├── memory.md                    # /memory command definition
│   └── build.md                     # /build v1 stub
├── docs/
│   ├── quickstart.md                # 5-minute onboarding
│   └── superpowers/
│       ├── specs/
│       │   ├── 2026-04-10-harness-workflow-design.md  (v1, superseded)
│       │   └── 2026-04-11-curator-design.md (this document)
│       └── plans/
│           └── 2026-04-11-curator-plan.md              (created post-approval)
└── README.md                        # Entry point → docs/quickstart.md
```

**Day 1 directories only**. `eval/`, `plugins/`, `dashboard/`, `contracts/` are added when triggered by real demand (not preemptively).

---

## Data Flow

### Read Path — `/recall` (mid-session)

```
user: /recall "how did we handle rate limiting?"
  │
  ▼
recall skill executes
  │
  ├── live path: direct MCP call to mempalace.search(query)
  │     │
  │     ▼
  │   Top-5 results with citations
  │     │
  │     ▼
  │   Display to user with drawer content
  │
  └── fallback (MemPalace unreachable):
        │
        ▼
      Read memdir/pattern-signal.md (mtime-sorted)
        │
        ▼
      Grep for query keywords
        │
        ▼
      Display degraded result with "[STALE — MemPalace offline]" banner
```

**Invariant**: `/recall` always goes to MemPalace first. Only on MCP failure does it fall back to `pattern-signal.md`. This is the "live strong consistency" path. `memdir/` is never used for user-initiated recall when MemPalace is healthy.

### Write Path — `/capture` (mid-session)

```
user: /capture "the OAuth refresh requires re-fetching scopes"
  │
  ▼
capture skill:
  │
  1. Compute content_hash = sha256(payload + ts)
  2. Append to ~/.curator/pending_sync.jsonl with pending=["mempalace"]
  3. Append entry to memdir/pattern-signal.md (local, immediate)
     → touches mtime so Sonnet selector can surface it
  4. Attempt MCP write to MemPalace
     ├── success → mark pending=[] in journal
     └── failure → leave pending, show "[will retry on next session]"
  5. If `--pin` flag: append rule body to MEMORY.md L0 section
  6. Confirm to user with drawer location
```

**Idempotency guarantee**: `content_hash` is the dedup key. Replaying the same journal entry is safe because MemPalace accepts only the first write per hash. No sequence numbers needed.

### SessionStart Projection

```
SessionStart hook fires
  │
  ├── 1. Verify MemPalace MCP reachable (with 3s timeout)
  │       │
  │       ├── reachable → continue to step 2
  │       └── unreachable → skip projection, mark stale tier, continue
  │
  ├── 2. Query MemPalace for L0 rules (wing=current-repo, hall=hall_facts, pinned=true)
  │       │
  │       ▼
  │     Rewrite MEMORY.md from scratch with projected L0 + schema_version header
  │
  ├── 3. Scan ~/.curator/pending_sync.jsonl for entries with pending != []
  │       │
  │       ▼
  │     For each, retry write to MemPalace (idempotent by content_hash)
  │
  ├── 4. Compute stale tier:
  │       now - projection_ts
  │       < 5 min   → silent
  │       5m - 24h  → inject one-time inline warning
  │       > 24h     → inject persistent warning
  │
  └── 5. Reset ~/.curator/session-state.json: proposal_count = 0
```

**Blast radius of SessionStart failure**: session continues with previous MEMORY.md contents. No data loss. User sees warning if tier ≥ 5 min.

### Pattern Proposal Pipeline

```
UserPromptSubmit hook fires (blocking)
  │
  ├── Read ~/.curator/session-state.json
  │
  ├── If proposal_count >= 1 → exit 0, no proposal this session
  │
  ├── If natural pause detected (heuristic: last assistant turn ended with
  │   a tool result, not mid-task narration):
  │     │
  │     ▼
  │   Run lightweight pattern detector on recent conversation slice
  │     (signal: user correction language, repeated file edits,
  │      explicit "don't do X" statements)
  │     │
  │     ▼
  │   If candidate exists:
  │     - Build proposal message: "偵測到 pattern: {text}. Y/n/d?"
  │     - Increment proposal_count
  │     - Emit via exit 2 with stderr (injects into model turn)
  │
  └── Otherwise → exit 0, pass through
```

**Defer path**: If user responds `d`, proposal is appended to `~/.curator/pending-proposals.jsonl`. Next `/memory` invocation reads this file and shows "N pending proposals — run `/memory --review` to batch-confirm".

**Write-path ownership clarification**: `pattern-signal.md` is written in two places with distinct purposes:
- **`/capture` (immediate)** — appends a single entry when the user explicitly captures something. Touches `mtime` so the Sonnet selector can surface it.
- **`Stop` hook (maintenance)** — prunes entries older than 7 days and rewrites the file with the rolling window. Does NOT add new entries; only removes stale ones.

This prevents double-writes and keeps the file bounded without racing with `/capture`.

---

## Error Handling

### Stale Projection Visibility (3-tier)

Reliability-engineer protocol:

| Staleness | Behavior | Rationale |
|---|---|---|
| < 5 minutes | **Silent** | MemPalace restart / MCP timeout is normal; not worth alerting |
| 5 min – 24 hours | **One-time inline warning** at SessionStart only: `[curator] ⚠ using cached memory (last sync 14h ago), MemPalace unreachable` | User informed once per session; no alert fatigue |
| > 24 hours | **Persistent**: SessionStart warning + `/memory` shows degraded badge | Sustained outage deserves sustained visibility |

**Machine-readable banner** in `MEMORY.md` header:

```
<!-- curator: projection-ts=2026-04-11T14:23:00Z source=fresh -->
```

Parseable by any hook or tool that needs to know projection freshness without querying MemPalace.

### Dual-Write Idempotency

- **Key**: `content_hash = sha256(payload + ts)` — the content itself is the key, never a sequence number (sequence numbers break under concurrent sessions)
- **Journal**: `~/.curator/pending_sync.jsonl` is append-only; successful writes mark entries as `pending=[]` rather than deleting them
- **Retry**: `SessionStart` scans the journal, attempts retry for any entries with `pending != []`
- **TTL**: Entries older than 7 days that are still pending get logged as warnings and dropped. Prevents unbounded journal growth.

### MemPalace Outage Degradation Tiers

| Outage type | v1 behavior |
|---|---|
| **MCP connection refused** | SessionStart skips projection; continues with previous `MEMORY.md`; stale banner injected |
| **MCP slow response (> 3s)** | SessionStart timeout; same as refused |
| **Wrong embedding returned** | v1 cannot detect silent corruption. Noted as v2 concern; would require content-hash comparison against `pattern-signal.md`. Deferred. |
| **`Stop` hook MemPalace write failure** | Append to `pending_sync.jsonl`; next SessionStart retries. User sees no interruption. |
| **Disk full during `Stop` hook** | Hook returns non-zero exit code; user sees error message. Data safety > silent success. |

---

## DX Hard Requirements (non-negotiable)

These three requirements are inherited from the debate and cannot be relaxed without invalidating the D2/D3 decisions.

### HR-1: `pattern-signal.md` ambient context isolation (testable)

- `pattern-signal.md` must NOT be referenced from `MEMORY.md` via `@include` or equivalent
- It must NOT appear in any CC `settings.json` auto-load list
- It exists only as an independent `memdir/` file, picked up by `findRelevantMemories` Sonnet selector on relevance

**Test**: Start a fresh session. Inspect the initial Claude context. Verify `pattern-signal.md` contents are NOT present. If a query then triggers it via selector relevance, that is expected behavior.

### HR-2: Pattern proposal is one-per-session, deferrable

- `~/.curator/session-state.json` has a `proposal_count` field that caps at 1 per session
- Proposal must appear at a natural pause point (tool result boundary), NOT at session end
- Defer (`d`) path writes to `~/.curator/pending-proposals.jsonl` for later batch review
- Session end never triggers batch pattern review

**Test**: In a single session, correct Claude 3 times. Verify only the first correction triggers a proposal. Verify no proposal appears at session end. Verify `d` response adds to pending queue visible in next `/memory`.

### HR-3: `/memory` shows connection + freshness state

Minimum output format:

```
[MEMORY.md]     L0 · N entries · X.XKB · schema v1
[pattern-signal] Y observations · last write <time>
[MemPalace]     connected · last sync Xm ago
                (or: disconnected · last sync Xh ago · Z pending writes)
[pending proposals] N items — run /memory --review to batch-confirm
```

User must be able to answer "is curator working right now?" from a single command.

---

## Routing Rules

`memory-bridge/routing-rules.yaml` replaces the v1 spec's procedural `router.sh` to prevent a god file.

```yaml
# memory-bridge/routing-rules.yaml
version: 1
rules:
  - match:
      type: feedback
      min_length: 50
    destinations:
      memory: immediate        # write to MEMORY.md L0 section
      mempalace: batch         # queued in pending_sync.jsonl for Stop hook
      priority: medium

  - match:
      type: architecture_decision
      min_length: 50
    destinations:
      memory: immediate
      mempalace: priority_push # flushed immediately by Stop hook
      priority: high

  - match:
      type: user_preference
    destinations:
      memory: immediate
      mempalace: skip          # preferences stay local only

  - match:
      type: session_observation
    destinations:
      memory: skip             # observations are not rules
      mempalace: batch
      priority: low

  - match:
      type: pattern
      min_confidence: 0.8
    destinations:
      memory: pattern_signal   # written to pattern-signal.md, not MEMORY.md
      mempalace: after_user_confirm
```

**Interpreter**: `router.sh` is a ~30-line bash wrapper over `yq eval`. Reads all `routing-rules.yaml` + `routing-rules.d/*.yaml`, merges, then dispatches each write through the matched rule.

**Extensibility**: Plugins can drop files into `routing-rules.d/`. They are merged after core rules (lower default priority). A plugin can override with `priority: plugin-high` in its rule.

---

## Testing Strategy

v1 ships with three test layers:

1. **Installer smoke test** (`core/scripts/health-check.sh`):
   - MemPalace MCP reachable
   - Skills discoverable
   - Hooks registered in `settings.json`
   - `yq` binary available
   - `~/.curator/` writable

2. **Round-trip test** (`test/roundtrip.sh`):
   - `/capture "test fact N"` → verify in MemPalace via `/recall`
   - Kill MemPalace mid-session → verify `/recall` falls back to `pattern-signal.md`
   - Restart MemPalace → verify `pending_sync.jsonl` reconciles on next SessionStart

3. **HR acceptance tests** (`test/hr-acceptance.sh`):
   - HR-1: fresh session, `pattern-signal.md` has content, verify not in Claude context
   - HR-2: 3 corrections, verify only 1 proposal, verify defer path
   - HR-3: `/memory` output format matches spec

Integration tests run against a real local MemPalace instance (Docker). No mocking of MemPalace internals (per the v1 feedback memory — "integration tests must hit real DB").

---

## Pre-Installation Environment Check

Curator v1 is deployed into a possibly-messy existing `~/.claude/` environment. The installer MUST run a preflight check before touching anything, and abort (not try to auto-merge) on any collision that needs human judgment.

### Preflight check responsibilities

`core/scripts/preflight-check.sh` (runs before `install.sh`):

1. **Hook slot audit**. Parse `~/.claude/settings.json` and `~/.claude/settings.local.json`. For each curator-required slot (`SessionStart`, `UserPromptSubmit`, `Stop`), report:
   - Slot is empty → clean install
   - Slot has other hooks → curator appends to the end of the hook array (order-dependent)
   - Stop slot ordering constraint: curator MemPalace-write hook must be placed **after** any quality-gate hooks (e.g., `pipeline-gate.sh`). Report existing ordering and recommend placement.

2. **Skill / command name collision**. Scan `~/.claude/skills/`, `~/.claude/commands/`, and all enabled plugin manifests for the names `capture`, `recall`, `memory`, `build`. Report any conflict. Abort if collision exists; user must rename.

3. **Existing memdir content**. Scan `~/.claude/projects/<repo>/memory/` for every repo. For each non-empty `MEMORY.md` or `pattern-signal.md`:
   - **Mandatory backup**: copy to `~/.claude/projects/<repo>/memory/backup-<timestamp>/` before any curator write
   - Report the list of repos with existing content so user knows what is being backed up

4. **MCP server availability**. Check `claude mcp list` (or read the MCP config path) for an existing `mempalace` entry.
   - If present → verify it is reachable
   - If absent → report "MemPalace MCP not installed" and refuse to proceed until user installs it (see Installation section below)

5. **Dependency check**. Verify `jq`, `yq`, `sha256sum`/`shasum` are on `PATH`. Report missing dependencies with install commands for macOS (`brew install yq`).

6. **Write a preflight report** to `~/.curator/preflight-<timestamp>.log` with every finding. User can review before approving install.

### Known current-environment collisions (for this user's machine)

These were detected on 2026-04-11 during spec authoring. Real install must re-scan.

| Category | Finding | Action |
|---|---|---|
| `Stop` hook | Already has 3 hooks: `terminal-notifier`, `check-debug-statements.js`, `pipeline-gate.sh` (120s timeout) | Curator appends a 4th; must run **after** `pipeline-gate.sh` so quality-rejected patterns are not persisted |
| `PreToolUse` hook | `secret-scan.sh` exists with Bash matcher | No v1 conflict; v2.1 reverse-pattern-match will add a separate entry with wildcard matcher |
| Existing memdir content | 7 repos have populated `MEMORY.md`: `stt-keyboard`, `tuanyigo-v2`, `tuan-hub`, `openclaw-ui`, `soul-pets`, `petdocs-app` (+1) | Mandatory backup before first SessionStart projection |
| `soul-pets/memory/patterns.md` | User has a file named `patterns.md` in one repo | Curator writes `pattern-signal.md` (different name, no collision). Warn user to avoid confusion. |
| MemPalace | **Not installed** (`mempalace` command not found, `~/.mempalace/` does not exist, no `mempalace` MCP server registered) | **Blocker**. User must install MemPalace before curator. |
| `jq` / `yq` | User has `jq`. `yq` status unverified. | Check in preflight. |

---

## Installation & Distribution

Curator ships as a Claude Code plugin in a git-hosted marketplace, consistent with the user's existing plugin ecosystem (`claude-plugins-official`, `everything-claude-code`, etc.).

### v1 distribution path: git-hosted CC plugin

**Structure** (curator repo serves double duty as plugin package):

```
curator/
├── .claude-plugin/
│   └── plugin.json             # Plugin manifest
├── core/                       # (same as implementation layout above)
├── memory-bridge/
├── skills/
└── docs/
```

**`plugin.json` manifest** (follows the format used by `everything-claude-code`):

```json
{
  "name": "curator",
  "version": "0.1.0",
  "description": "Portable Claude Code engineering workflow with MemPalace memory integration",
  "author": { "name": "Jack Chung" },
  "repository": "https://github.com/jackg825/curator",
  "requires": {
    "mcp_servers": ["mempalace"],
    "binaries": ["jq", "yq"]
  },
  "postInstall": "core/scripts/install.sh",
  "keywords": ["memory", "mempalace", "workflow", "cqrs"]
}
```

### Install on a new machine (target: one command)

```bash
# 1. Add curator marketplace (one-time, per user)
claude plugin marketplace add jackg825/curator

# 2. Install the plugin (runs postInstall hook which triggers preflight + install)
claude plugin install curator@jackg825

# 3. Plugin postInstall runs:
#    - core/scripts/preflight-check.sh  (checks conflicts, backs up memdir)
#    - core/scripts/install.sh          (symlinks hooks, writes settings.json patches,
#                                        creates ~/.curator/, generates device-id)
#    - prompts user to install MemPalace if not present
```

### What `install.sh` does

1. **Preflight** (aborts on unresolved conflict — user must re-run with `--force` after fixing)
2. **Write `~/.curator/device-id`** (generated once, never rotated)
3. **Append to `~/.claude/settings.json` hooks** (via `jq` patch, preserving existing entries):
   - Append curator `SessionStart` hook (new slot, clean)
   - Append curator `UserPromptSubmit` hook (new slot, clean)
   - Append curator `Stop` hook **at end of existing Stop hook array** (ordering preserved)
4. **Symlink skills** from `<curator-repo>/skills/*.md` to `~/.claude/skills/curator-*.md` (namespaced to avoid future collision)
5. **Deploy `routing-rules.yaml`** to `~/.curator/routing-rules.yaml` (user-editable, not in skill dir)
6. **Register MCP server** via `claude mcp add mempalace <command>` (user confirms the actual MemPalace launch command)
7. **Verify MemPalace reachability**: send a test `search` to confirm MCP connection works
8. **Write install receipt** to `~/.curator/install-receipt.json` with version, timestamp, device_id, and a snapshot of hook ordering — used by `uninstall.sh` to reverse changes cleanly

### Uninstall path

`core/scripts/uninstall.sh` reads the install receipt and reverses each change:
- Remove hook entries from `settings.json` (by matching command string)
- Remove skill symlinks
- Optionally preserve or delete `~/.curator/` state (flag: `--keep-state` / `--purge`)
- Does NOT touch MemPalace data (user's responsibility)

### First-time MemPalace setup (separate from curator install)

MemPalace is an independent Python project. Curator install scripts guide the user but don't auto-install. Quickstart.md provides two paths:

**Path A: Local Python install (single device)**:
```bash
pip install mempalace
mempalace serve --stdio  # MCP server over stdio
```
Then register: `claude mcp add mempalace -- mempalace serve --stdio`.

**Path B: Docker + network (single device, still localhost)**:
```bash
docker run -d --name mempalace -p 7890:7890 -v ~/.mempalace:/data mempalace/mempalace
```
Then register: `claude mcp add mempalace --url http://localhost:7890`.

**Path C: Mac Mini backend (multi-device)** — see next section.

---

## Multi-Device Architecture (Phase 2 Preview)

Phase 2 is explicitly out of v1 scope, but v1 must not block it. This section documents the target architecture and the v1 constraints that preserve it.

### Topology

```
┌──────────────────────────────────────────────────────────────┐
│                      Tailscale mesh                          │
│                      (100.x.x.x/10)                          │
│                                                              │
│   ┌─────────────────┐        ┌─────────────────┐             │
│   │  Laptop (dev)   │        │  Desktop        │             │
│   │  curator plugin │        │  curator plugin │             │
│   │  ~/.curator/    │        │  ~/.curator/    │             │
│   │   device-id:    │        │   device-id:    │             │
│   │   "mbp-k3x7"    │        │   "imac-p2q9"   │             │
│   └────────┬────────┘        └────────┬────────┘             │
│            │                          │                      │
│            │       MCP over Tailscale │                      │
│            └──────────┬───────────────┘                      │
│                       │                                      │
│                       ▼                                      │
│              ┌──────────────────┐                            │
│              │  Mac Mini        │                            │
│              │  (always-on)     │                            │
│              │                  │                            │
│              │  MemPalace MCP   │  ← CANONICAL STORE         │
│              │  server          │                            │
│              │  ~/.mempalace/   │                            │
│              │    (ChromaDB)    │                            │
│              │                  │                            │
│              │  curator plugin  │  ← Mac Mini is also        │
│              │  ~/.curator/     │     a curator client       │
│              │   device-id:     │                            │
│              │   "mini-xyz1"    │                            │
│              └──────────────────┘                            │
└──────────────────────────────────────────────────────────────┘
```

### What is shared vs what is device-local

| Data | Scope | Rationale |
|---|---|---|
| **MemPalace ChromaDB + drawers** | Shared (on Mac Mini only) | Single canonical semantic store |
| **`MEMORY.md` (L0 projection)** | Device-local | Projected from MemPalace each SessionStart; eventual consistency acceptable because projection is idempotent |
| **`pattern-signal.md`** | Device-local | Written by local `/capture` + Stop hook; reflects the work done ON that device |
| **`~/.curator/pending_sync.jsonl`** | **Device-local, never synced** | Each device has its own pending-write journal. Merging journals across devices would break idempotency semantics. |
| **`~/.curator/device-id`** | Device-local, never rotated | Stable identity for audit trails |
| **`~/.curator/session-state.json`** | Device-local, ephemeral | Per-session proposal counter; meaningless cross-device |
| **`~/.curator/events/*.jsonl`** | Device-local | v2.2 dashboard reads per-device; can be aggregated offline later if needed |

### Cross-device memory flow

1. **Write on Laptop**: `/capture "auth uses JWT refresh"` → MCP call to `mempalace-on-mini.ts.net:7890` → MemPalace stores drawer with `metadata.device_id = "mbp-k3x7"`
2. **Read on Desktop**: `/recall "auth refresh"` → MCP call to same Mac Mini MemPalace → returns drawer with provenance "captured on mbp-k3x7 at 2026-04-11"
3. **Desktop's next SessionStart**: projects L0 from Mac Mini MemPalace → pulls any rules written from Laptop → appears in `MEMORY.md` automatically

No additional sync logic. Content_hash idempotency plus the single-canonical-store invariant do all the work.

### Network failure modes (phase 2)

| Scenario | Behavior |
|---|---|
| **Mac Mini offline, Laptop online** | `/recall` fails over to local `pattern-signal.md`; `/capture` writes queue in `pending_sync.jsonl` on Laptop; next successful MCP call drains the queue |
| **Laptop offline, Mac Mini online** | No effect on Desktop or Mac Mini workflows; Laptop runs offline with stale local projection |
| **Tailscale tunnel down** | Same as "Mac Mini offline" from each device's perspective |
| **MemPalace process crashed on Mac Mini** | Same as above; Mac Mini curator itself degrades to local fallback (it is also a client of itself) |

### v1 requirements that preserve phase 2

Already captured in the Portability constraints section, but explicitly re-stated here for visibility:

1. **`CURATOR_MEMPALACE_URL` env var** — v1 reads this, default is `stdio` or `http://localhost:7890`. Phase 2 sets it to `http://100.x.x.x:7890` (Tailscale IP of Mac Mini). No code change.
2. **`device_id` in `pending_sync.jsonl`** — v1 writes this field from day 1. v1 does not read it. Phase 2 uses it for provenance and conflict diagnosis.
3. **`~/.curator/` is device-local** — documented as non-sync-safe. `.gitignore` template in curator repo has `*.curator/` pre-added.

### Tailscale setup (phase 2 quickstart, not implemented in v1)

1. Install Tailscale on all devices (`brew install tailscale` or GUI)
2. Log in each device to the same account
3. On Mac Mini: `claude mcp add mempalace --url http://0.0.0.0:7890` (bind all interfaces)
4. On other devices: `claude mcp add mempalace --url http://mini.tailnet-name.ts.net:7890`
5. Each device's `CURATOR_MEMPALACE_URL` env var points at the Tailscale hostname

---

## Future Work (Extension Points Preserved)

| Phase | Feature | Hook Point | Preserved by v1? |
|---|---|---|---|
| **v1.1** | `/recall` UX polish (paged results, result filtering) | Command layer | ✅ |
| **v1.2** | **build-loop workflow** (4-phase PLAN→IMPL→SIMPLIFY→REVIEW) | New `/build` skill + `Stop` hook integration | ✅ Skill stub reserved |
| **v2.1** | **主動警告** (PreToolUse reverse pattern match) | `PreToolUse` hook (sync blocking, confirmed `utils/hooks/hooksConfigManager.ts:29-36`) | ✅ Hook event available |
| **v2.2** | **Learning dashboard** | Read `~/.curator/events/*.jsonl` schema-versioned event log | ✅ Events written in v1 |
| **v2.3** | **Multi-user team mode** | New `MemoryAdapter` implementation with namespace parameter | ✅ `adapter-interface.md` preserves namespace stub |
| **v3.1** | **Mac Mini remote agent runtime** | JSONL event bus transport-agnostic | ✅ JSONL bus exists |

No v1 code needs to be rewritten for any of these. Each adds new files or new hook registrations only.

---

## Debate Record

This design was produced through a structured 5-expert panel debate (3 rounds + Devil's Advocate).

| Expert | Role | Key contribution |
|---|---|---|
| **Memory Systems Engineer** | CQRS purity, memory tiering | `/recall` live path vs projection cold path separation; confidence trajectory via ChromaDB metadata filter (not third store) |
| **Claude Code Internals Expert** | Source-code fact authority (fact-veto) | 26 user-space hooks confirmed; `Stop` vs `SessionEnd` 1.5s timeout finding; `memoryScan.ts:72` mtime sort that enabled the `pattern-signal.md` design |
| **DX Designer** (also Devil's Advocate) | User commands, learning curve, 4-command discipline | 4 commands max; one-at-a-time HR-2; signal dilution argument that forced reconsideration of (ii); HR-1/HR-2/HR-3 testable acceptance criteria |
| **Reliability Engineer** | Failure modes, graceful degradation | 3-tier stale visibility protocol; `pending_sync.jsonl` + SHA-256 content-hash idempotency; `asyncRewake` NOT suitable for compensation (continuation semantics, not repair) |
| **Platform Architect** | Layer boundaries, v2/v3 extension points | Extension-point matrix; curator-owned projection schema; YAML routing table; weekly-batch-cannot-replace-daily-recency argument |

### Round trajectory

- **Round 1**: All 5 experts converged on D1=B independently. D3=(ii) also 5/5. D2 split 4/1 with DX Designer dissenting on (i) L0+L1 only.
- **Round 2**: DX Designer assigned as Devil's Advocate (groupthink check triggered). DA case forced (i) Platform Architect to concede ChromaDB latency claim and switch to "process dependency" argument, (ii) Memory Engineer to distinguish encapsulated vs leaked complexity. DA then self-converged to (iv) L0-only via ambient-context signal-to-noise reasoning. Meanwhile CC Internals Expert verified `PreToolUse` blocking semantics and `Stop` vs `SessionEnd` 1.5s discovery.
- **Round 3**: Focused free debate on D2 only. All 5 converged on (vii) dual-file, enabled by CC Internals Expert's `memoryScan.ts:72` mtime discovery which made dx-designer's HR-1 satisfied-by-default.

Full debate transcripts preserved in `~/.claude/teams/harness-v2-debate/inboxes/moderator.json`.

---

## References

### Claude Code source code citations (all `file:line` verified)

- `entrypoints/sdk/coreTypes.ts:25-53` — 26 hook event types
- `utils/hooks/hooksConfigManager.ts:29-36` — `PreToolUse` blocking semantics, exit code 2 behavior
- `utils/hooks/hooksConfigManager.ts:95-99` — `Stop` hook definition
- `utils/hooks/hooksConfigManager.ts:154-161` — `SessionEnd` hook definition
- `utils/hooks.ts:166` — `TOOL_HOOK_EXECUTION_TIMEOUT_MS = 10 * 60 * 1000`
- `utils/hooks.ts:175` — `SESSION_END_HOOK_TIMEOUT_MS_DEFAULT = 1500`
- `utils/gracefulShutdown.ts:473-480` — SessionEnd silent exception handling
- `memdir/memdir.ts:35-38` — `MAX_ENTRYPOINT_LINES = 200`, `MAX_ENTRYPOINT_BYTES = 25_000`
- `memdir/memoryScan.ts:72` — `mtimeMs` descending sort
- `memdir/memoryScan.ts:84-94` — `formatMemoryManifest()` ISO timestamps
- `memdir/findRelevantMemories.ts:39-75` — Sonnet selector sidecar
- `memdir/paths.ts:223-235` — `getAutoMemPath` memoization
- `services/teamMemorySync/index.ts:151-161` — first-party OAuth gate
- `services/api/withRetry.ts:170-299` — rate-limit cascade with persistent retry
- `cost-tracker.ts:143-173` — per-session cost save/restore
- `query/stopHooks.ts:142-157` — `extractMemories` feature-flag gate

### External dependencies

- **MemPalace** (`milla-jovovich/mempalace`) — local ChromaDB semantic memory with MCP server, 96.6% LongMemEval R@5 raw mode
- **yq** — YAML command-line interpreter for `router.sh`
- **jq** — JSON command-line interpreter for JSONL parsing

### Design principles

1. **Ride CC native machinery**. Every line of curator code that duplicates Claude Code built-in functionality is technical debt.
2. **CQRS = different questions, different stores**. Not read/write separation. MemPalace answers "why did we decide this?"; `MEMORY.md` answers "what is the current rule?"
3. **Hooks are triggers, not logic**. `Stop` hook does the MemPalace write, but the write logic lives in `memory-bridge/router.sh`. Hooks are < 50 lines each.
4. **Deterministic routing**. No AI judgment for routing decisions. YAML rules + yq interpreter.
5. **Graceful degradation with visibility**. MemPalace can fail; curator continues; user is informed via 3-tier alerting.
6. **YAGNI for structure**. Day 1 = 4 directories. Add more only on real demand.
7. **Source-code grounding**. Every claim about Claude Code capabilities cites `file:line`.
