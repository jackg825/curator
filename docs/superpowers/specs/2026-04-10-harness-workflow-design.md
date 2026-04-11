# Harness Engineering Workflow Design (RETRACTED)

> **⚠️ SUPERSEDED 2026-04-11** — This draft was retracted after Claude Code source-code exploration revealed several false premises. See the replacement: [`2026-04-11-curator-design.md`](./2026-04-11-curator-design.md).
>
> **Why retracted**: This draft claimed Claude Code has "only 4 hook event types, synchronous, blocking" and proposed a custom JSONL event queue. Source code (`entrypoints/sdk/coreTypes.ts:25-53`) shows 26 user-space hook events, `AsyncHookRegistry` with `asyncRewake:true`, and `utils/hooks/hookEvents.ts` as an internal event bus. The entire Decision A (event architecture) rested on this false premise.
>
> **What changed**: The project was renamed from `harness` to `curator`. The new design uses Claude Code native hooks instead of a custom event bus, adopts dual-layer CQRS with MemPalace as canonical store and `memdir/` as projection cache, and adds a 3-round expert debate record with source-code citations.
>
> This document is kept in git history as a record of the design evolution. Do NOT use it as the current design.

---

**Date:** 2026-04-10
**Status:** ~~Approved~~ **Retracted 2026-04-11**
**Authors:** Jack Chung + 6-expert panel debate

## Overview

A portable Claude Code harness engineering monorepo that combines:
- **MemPalace** (long-term semantic memory) with **Claude Code native auto memory** (session-level)
- **build-loop** (4-phase Generator-Evaluator cycle) with **event-driven feedback loops**
- **Automatic pattern extraction** with confidence scoring and decay/reinforcement

Architecture: **Layer Cake** (L0-L4) with internal **event-driven hooks**.

---

## Architecture Layers

```
┌─────────────────────────────────────────┐
│  L4: Dashboard & Analytics              │  memory quality, pattern trends, eval scores
├─────────────────────────────────────────┤
│  L3: Eval Harness & Benchmarks          │  session replay, memory recall accuracy
├─────────────────────────────────────────┤
│  L2: Workflow Engine                    │  build-loop, feedback triggers, learn-eval
│      (skills + commands + hooks)        │
├─────────────────────────────────────────┤
│  L1: Memory Bridge (CQRS)              │  Native Memory (write model) ↔
│      MemPalace (audit log + read model) │  routing, sync, WAL
├─────────────────────────────────────────┤
│  L0: Core Config & Bootstrap            │  CLAUDE.md templates, install.sh,
│      (installer, hooks, settings)       │  MemPalace health check
└─────────────────────────────────────────┘
```

---

## Decision A: Event Architecture

### Problem

Claude Code hooks are synchronous, blocking, with no retry/timeout/error propagation. They support only 4 event types (SessionStart, PreToolUse, PostToolUse, SessionEnd). Using them directly as an event bus would freeze sessions and silently lose events.

### Solution: JSONL Queue + Dual-Track Events

**Hooks as thin triggers only.** All business logic delegated to async processing.

```
Claude Code Hooks (4 lifecycle events)
    │
    ▼
hook-wrapper.sh (< 50ms, synchronous)
    ├── append to ~/.harness/events/session-{id}.jsonl
    └── return immediately, never block session

Workflow Engine (build-loop internal business events)
    ├── test-fail, review-pass, phase-transition, user-correction
    └── also append to events/*.jsonl

SessionStart hook:
    ├── scan uncommitted WAL → merge into session context
    └── watchdog: verify MemPalace MCP is alive

SessionEnd hook:
    ├── batch sync → MemPalace (architecture decisions first)
    ├── if pending events exist → print terminal warning
    └── "[harness] 3 events pending — run /harness-sync to flush"
```

### Event Record Format

```jsonl
{"id":"uuid","type":"post_tool_use","ts":"2026-04-10T10:30:00Z","session_id":"abc123","payload":{"tool":"Bash","result":"exit 0"},"content_hash":"sha256:..."}
{"id":"uuid","type":"phase_transition","ts":"2026-04-10T10:31:00Z","session_id":"abc123","payload":{"from":"IMPLEMENT","to":"SIMPLIFY"}}
{"id":"uuid","type":"feedback_captured","ts":"2026-04-10T10:32:00Z","session_id":"abc123","payload":{"rule":"no mock in integration tests","confidence":0.6}}
```

### Key Design Choices

| Choice | Rationale |
|--------|-----------|
| JSONL over SQLite WAL | Zero dependency, human-readable (`cat`, `tail -f`, `grep`), crash-safe (append-only). SQLite available as `HARNESS_QUEUE=sqlite` opt-in for concurrent sessions. |
| Dual-track events | Hooks cover lifecycle (4 types). Workflow engine covers business events (unlimited). Solves the event vocabulary problem without replacing hooks. |
| Per-session files | `session-{id}.jsonl` avoids concurrent write conflicts. Each file is self-contained for replay. |
| SessionStart WAL recovery | Uncommitted events from crashed sessions are auto-replayed at next session start. No data loss. |

---

## Decision B: Memory Bridge (CQRS Model)

### Problem

MemPalace and Claude Code native memory have overlapping categories (feedback, project decisions, architecture patterns). Dual-write causes consistency nightmares. Single-write forces choosing between semantic search and zero-dependency loading.

### Solution: CQRS — Different Responsibilities, Not Different Copies

Native Memory and MemPalace serve fundamentally different questions:

| Question | Source |
|----------|--------|
| "What is the current rule?" | Native Memory (write model) |
| "Why was this decision made?" | MemPalace (audit log) |
| "Are there similar decisions?" | MemPalace (semantic search) |

This is not dual-write of the same data. It is writing different facets to different stores. No reconciliation needed.

### Routing Rules (Deterministic, Not AI-Judged)

| Memory Type | Native Memory | MemPalace | Write Timing |
|-------------|:---:|:---:|------|
| Feedback rule | Rule body | Conversation context (audit) | Native: immediate / MP: batch |
| Architecture decision | Conclusion | Discussion context (audit) | Native: immediate / MP: **priority push** |
| Project decision | Conclusion + date | Full discussion (audit) | Native: immediate / MP: batch |
| User preference | Preference setting | Not needed | Native only |
| Session observation | Not stored | WAL → batch | SessionEnd |
| Pattern (confidence > 0.8) | Promoted to rule | Pattern library | Requires human confirm or quarantine period |

### Write Timing Strategy

```
Memory write event occurs
    │
    ├── ALL memories → immediate write to Native Memory (< 10ms)
    │   (pure filesystem write, zero external dependency)
    │
    ├── Simultaneously append to events/session-{id}.jsonl (WAL)
    │
    └── SessionEnd batch sync to MemPalace:
        ├── HIGH priority (architecture decisions) → push first, don't wait
        ├── MEDIUM priority (feedback context, decision rationale) → batch
        └── LOW priority (session observations, debug context) → batch
```

### Failure Handling

| Scenario | Behavior |
|----------|----------|
| MemPalace MCP not running | Write to `pending_sync.jsonl`, auto-replay at next SessionStart |
| Session crash (no SessionEnd) | WAL files survive, recovered at next SessionStart |
| Sync partially fails | Failed items stay in pending, retry with idempotency key (`content_hash`) |
| Filtered memories | Written to `filtered.jsonl` (7-day retention, with filter reason). User can manually promote. |

### Promotion Rules (Deterministic, AND logic)

```
Promote to MemPalace when ALL conditions met:
1. type ∈ {feedback, project_decision, architecture_pattern}
2. content length > 50 characters
3. no session-scoped transient language ("just now", "this time")
4. content_hash not already in MemPalace (or delta > 20%)
```

### Pattern Auto-Promotion

Patterns extracted by learn-eval with confidence > 0.8 are NOT auto-promoted to MemPalace. They enter a **quarantine period** (3 sessions) where they are applied but flagged as `[provisional]`. After 3 sessions without user override, they are promoted. User can override at any time via `/harness-demote`.

---

## Decision C: MVP Directory Structure

### Day 1 (4 directories)

```
harness/
├── core/                              # L0: Bootstrap
│   ├── hooks/                         # hook-wrapper.sh, queue writer
│   │   ├── session-start.sh
│   │   ├── post-tool-use.sh
│   │   └── session-end.sh
│   ├── templates/                     # CLAUDE.md template, settings.json
│   │   ├── CLAUDE.md.template
│   │   └── settings.json.template
│   └── scripts/                       # install.sh, bootstrap.sh
│       ├── install.sh                 # symlinks to ~/.claude/, deploys templates
│       └── health-check.sh            # verify MemPalace MCP, check deps
├── memory-bridge/                     # L1: Memory Bridge
│   ├── router.sh                      # deterministic routing rules
│   ├── sync.sh                        # batch push to MemPalace
│   ├── recover.sh                     # WAL recovery at SessionStart
│   └── adapter-interface.md           # MemoryAdapter contract (Day 1 minimum)
├── workflows/                         # L2: Workflow Engine
│   ├── commands/                      # slash commands
│   │   └── build-loop.md
│   └── skills/                        # learn-eval, pattern-extract
│       ├── learn-eval.md
│       └── pattern-extract.md
├── docs/
│   ├── quickstart.md                  # 5-minute onboarding guide
│   ├── memory-routing.md              # decision tree for memory routing
│   └── superpowers/specs/             # design documents
└── README.md                          # first line points to quickstart
```

### Day N (demand-driven additions)

| Directory | Trigger Condition |
|-----------|-------------------|
| `eval/` | When benchmark or session replay is needed |
| `plugins/` | When third-party extensions exist AND adapter interface is stable |
| `dashboard/` | When UI/reporting is needed |
| `contracts/` | When a second adapter implementation (non-MemPalace) needs to integrate |
| `.harness/` | When multi-project config conflicts arise |

### Protection Measures (from Devil's Advocate)

1. **`core/scripts/install.sh`** — Explicit deploy script. Without it, L0 Bootstrap is a directory of suggestions, not an operational layer.
2. **`adapter-interface.md`** — Day 1 contract definition. Code implementation follows. Ensures future plugin compatibility.
3. **Tool-enforced boundaries** — Day N, after module boundaries stabilize. Add lint rules to prevent cross-layer imports.

---

## Session Lifecycle Integration

### Typical Session Flow

```
Start session
  │
  ├─ [Hook: SessionStart]
  │   ├─ core/hooks/session-start.sh
  │   ├─ health-check: MemPalace MCP alive?
  │   ├─ WAL recovery: scan pending events → merge into context
  │   ├─ MemPalace: load L0+L1 palace map (~170 tokens)
  │   └─ Native memory: load user/feedback/project/reference
  │
  ├─ User: "implement new subscription feature"
  │
  ├─ /build-loop ──┐
  │   PLAN          │ → MemPalace search: past similar decisions
  │   IMPLEMENT     │ → [Hook: post-tool-use] → append to events JSONL
  │                 │ → [Event: test-fail] → write feedback to native memory
  │   SIMPLIFY      │ → parallel review agents
  │   REVIEW        │ → [Event: review-pass/fail]
  │                 │   → PASS: pattern extraction (confidence score)
  │                 │   → FAIL: failure reason → native memory + WAL
  │                 │
  │                 │  Pattern confidence lifecycle:
  │                 │     > 0.8 → quarantine (3 sessions) → promote
  │                 │     0.4-0.8 → observe, re-evaluate
  │                 │     < 0.4 → decay, eventually purge
  │  ◄──────────────┘
  │
  ├─ [Hook: SessionEnd]
  │   ├─ core/hooks/session-end.sh
  │   ├─ learn-eval: scan session for patterns, corrections, decisions
  │   ├─ batch sync to MemPalace:
  │   │   ├─ architecture decisions → priority push
  │   │   ├─ feedback context → batch
  │   │   └─ session observations → batch
  │   ├─ MemPalace: diary entry (session summary)
  │   ├─ if pending_sync.jsonl non-empty → terminal warning
  │   └─ filtered memories → filtered.jsonl with reasons
  │
  └─ session ends
```

### Event Trigger Map

| Event | Source | Hook Type | Memory Action |
|-------|--------|-----------|---------------|
| Session start | Claude Code | SessionStart | Load MemPalace L0+L1, WAL recovery |
| Tool call | Claude Code | PostToolUse | Append event to JSONL |
| Commit | Claude Code | PostToolUse (Bash:git) | Append diff summary to WAL |
| Test fail | Workflow engine | Internal event | Write hypothesis to native feedback |
| Test pass | Workflow engine | Internal event | Log to WAL |
| Review pass | Workflow engine | Internal event | Trigger pattern extraction |
| Review fail | Workflow engine | Internal event | Write failure reason to native + WAL |
| User correction | Claude Code | PostToolUse | Immediate write to native feedback |
| Phase transition | Workflow engine | Internal event | Log to WAL |
| Session end | Claude Code | SessionEnd | Batch sync, learn-eval, diary |

---

## Design Principles

1. **JSONL everywhere** — Human-readable, zero-dependency, crash-safe event persistence. Runtime data lives in `~/.harness/` (events/, pending_sync.jsonl, filtered.jsonl). Repo contains only code and templates.
2. **CQRS for memory** — Native is "what is now", MemPalace is "why it became this way"
3. **Hooks are triggers, not logic** — < 50ms, fire-and-forget to JSONL
4. **Deterministic routing** — No AI judgment for memory routing decisions
5. **Graceful degradation** — MemPalace down? Everything still works via native memory + pending queue
6. **YAGNI for structure** — 4 directories on Day 1, add more only when pain is real
7. **Quarantine before promotion** — Patterns earn trust over 3 sessions, not instantly

---

## Debate Record

This design was produced through a structured 6-expert panel debate (3 rounds):

| Expert | Role | Key Contribution |
|--------|------|-----------------|
| Platform Architect | Architecture purity | Dual-track event system, packages/ layer concept |
| Memory Systems Engineer | Memory design | CQRS model (breakthrough), value-tier routing |
| DevOps Engineer | Reliability/ops | WAL continuous logging, deterministic filter rules |
| DX Designer | Developer experience | JSONL advocacy, MVP minimalism, quickstart.md mandate |
| Reliability Engineer | Failure modes | sync_pending protocol, quarantine period, hash-based idempotency |
| Devil's Advocate | Stress testing | Deploy script mandate, YAGNI enforcement, boundary protection |

Full debate transcript available in session history.
