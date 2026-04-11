# Curator

> **Claude Code memory layer backed by MemPalace** — persistent, searchable, cross-repo memory and pattern learning for your CC sessions.

**Status:** 📐 **Design complete, implementation pending.** Spec and plan are committed; no code yet.

---

## TL;DR

Claude Code has no cross-session semantic memory. Its `memdir/` is per-session static files, and its `teamMemorySync` service is OAuth-only with keyword-based recall (not vector). Curator fills the gap by wiring [MemPalace](https://github.com/milla-jovovich/mempalace) (ChromaDB semantic memory, 96.6% LongMemEval R@5) into the CC lifecycle — **without forking or replacing any native functionality**.

You get:

- **`/curator:capture <text>`** — write a memory now, idempotently (retries on next session if MemPalace is down)
- **`/curator:recall <query>`** — live semantic search against MemPalace, with local fallback
- **`/curator:memory`** — see what curator remembers + connection status
- **Auto pattern proposals** — after a session detects a candidate pattern (e.g., "user prefers pnpm over npm"), curator proposes it once per session with `Y/n/d` UX. User confirms, curator writes. No background AI auto-capture.
- **Cross-repo rules** — L0 rules persist across all your projects via MemPalace

Architecture in one sentence: **Dual-layer CQRS** — MemPalace is the canonical store, `memdir/` is the per-session projection cache, harness owns the projection and slash commands.

---

## Current Repo State

```
curator/ (still named harness/ pending rename)
├── README.md                                         ← you are here
├── docs/superpowers/
│   ├── specs/
│   │   ├── 2026-04-10-harness-workflow-design.md    [RETRACTED — superseded banner]
│   │   └── 2026-04-11-curator-design.md             ← CURRENT design spec (855 lines)
│   └── plans/
│       ├── 2026-04-10-harness-workflow.md           [RETRACTED]
│       └── 2026-04-11-curator-plan.md               ← CURRENT implementation plan (24 tasks)
└── .git/                                             4 design commits, no code yet
```

The repo is named `harness/` for historical reasons. Rename to `curator/` is a manual step before implementation starts — see "Before You Start" below.

---

## How to Use This Repo (3 phases)

### Phase 1: Understand the design (read-only, ~30 min)

1. **Read the TL;DR above.** You're already done if you just want the overview.
2. **Read [`docs/superpowers/specs/2026-04-11-curator-design.md`](docs/superpowers/specs/2026-04-11-curator-design.md)** for the full design:
   - Overview + Why v2 re-design (what premises the v1 got wrong about Claude Code)
   - Three architecture decisions (D1/D2/D3) with rationale
   - Architecture diagram + data flow
   - DX Hard Requirements (HR-1/HR-2/HR-3)
   - Pre-installation environment check + installation via CC plugin
   - Multi-Device Architecture preview (Phase 2: Mac Mini + Tailscale)
   - 16 Claude Code source-code citations (every CC claim has `file:line`)
   - Full 3-round debate record with 5 expert positions

3. **Skim [`docs/superpowers/plans/2026-04-11-curator-plan.md`](docs/superpowers/plans/2026-04-11-curator-plan.md)** for the task breakdown (24 bite-sized tasks, TDD structure with `bats-core`).

### Phase 2: Implement (fresh CC session, ~4-6 hours)

Prerequisites before starting:

```bash
# Dev tools
brew install bats-core yq jq

# MemPalace (required runtime dependency)
pip install mempalace
claude mcp add mempalace -- mempalace serve --stdio
claude mcp list | grep mempalace  # verify
```

**Strongly recommended:** rename the repo directory first so paths align:

```bash
cd ~/Workspace/GitHub
mv harness curator
cd curator
git remote -v   # update if remote URL points at jackg825/harness
```

Open a **fresh** Claude Code session in the renamed directory, then ask:

> Execute `docs/superpowers/plans/2026-04-11-curator-plan.md` using subagent-driven development. Start with Task 0 and run through Task 23.

Claude Code will invoke the `superpowers:subagent-driven-development` skill, spawn a fresh subagent per task, review between tasks, and land ~150 commits on a working branch named `curator-v1-impl`.

### Phase 3: Install locally (~5 min)

After implementation merges to `master`:

```bash
cd ~/Workspace/GitHub/curator
./core/scripts/preflight-check.sh        # review ~/.curator/preflight-*.log
./core/scripts/install.sh                # runs preflight, patches settings.json, registers MCP

# Try it out
/curator:memory
/curator:capture "this is a test memory"
/curator:recall test
```

Or once published as a CC plugin marketplace:

```bash
claude plugin marketplace add jackg825/curator
claude plugin install curator@jackg825
```

---

## Hard Requirements (non-negotiable from the design)

These are the testable constraints the implementation must satisfy. See spec § DX Hard Requirements for the full text; `test/hr-acceptance.sh` verifies them.

- **HR-1:** `pattern-signal.md` must NOT auto-inject into Claude's ambient context. It exists only as an on-demand memdir file, picked up by CC's native Sonnet selector.
- **HR-2:** Pattern proposal is capped at **one per session**, deferrable via `d` response. No session-end batch review.
- **HR-3:** `/curator:memory` must show MEMORY.md state + pattern-signal status + MemPalace connection + pending writes in a single command output.

---

## What Curator Is NOT

- **Not a Claude Code fork** — zero CC source code changes. Pure plugin + skill pack.
- **Not a MemPalace replacement** — harness delegates all semantic search to MemPalace MCP.
- **Not a build-loop framework** — `/curator:build` is a stub in v1. The 4-phase PLAN→IMPL→SIMPLIFY→REVIEW workflow is deferred to v1.2.
- **Not a team memory service** — v1 is single-user. Multi-user team mode is v2.3 via a new `MemoryAdapter` implementation.
- **Not a distributed system** — v1 is single-device. Mac Mini + Tailscale multi-device is Phase 2 (design preserved in v1, not implemented).
- **Not AI-auto-curated** — aligned with MemPalace's philosophy, curator never auto-writes patterns without user confirmation.

---

## Design Non-Goals

- No attempt to recover from a corrupted MemPalace database (that's MemPalace's job).
- No custom event bus (CC has 26 hook events; `utils/hooks/hookEvents.ts` is the native event bus).
- No custom cost tracker (CC's `cost-tracker.ts` already does this).
- No custom retry/rate-limit cascade (CC's `services/api/withRetry.ts` handles this).

---

## Dependencies

| Dependency | Purpose | Install |
|---|---|---|
| [MemPalace](https://github.com/milla-jovovich/mempalace) | Canonical semantic memory store (ChromaDB) | `pip install mempalace` |
| [Claude Code](https://claude.com/claude-code) | Host CLI, provides hooks and MCP | (you're using it) |
| `jq` | JSON manipulation in shell | `brew install jq` |
| `yq` | YAML rule interpreter for `routing-rules.yaml` | `brew install yq` |
| `bats-core` | Shell test framework (dev only) | `brew install bats-core` |

Tailscale is listed in the spec for Phase 2 multi-device setup but is NOT required for v1.

---

## Version & Status

- **v0.1.0** — spec + plan complete, no implementation (current)
- **v1.0** — target for first installable release (after plan execution)
- **v1.1** — differentiated routing types (architecture_decision, pattern, etc.)
- **v1.2** — build-loop 4-phase workflow
- **v2.1** — 主動警告 (PreToolUse reverse-pattern match)
- **v2.2** — learning dashboard
- **v2.3** — multi-user team mode
- **v3.1** — Mac Mini remote agent runtime (Phase 2 multi-device)

See spec § Future Work for the full roadmap with extension point mappings.

---

## Credits

- Design produced through a 3-round 5-expert structured debate with Devil's Advocate. Full transcript in `~/.claude/teams/harness-v2-debate/inboxes/moderator.json`.
- Built on the philosophical foundation of [MemPalace](https://github.com/milla-jovovich/mempalace) ("store everything, let search find it").
- Every Claude Code capability claim in the spec is backed by a `file:line` citation to the [Claude Code source code](https://claude.com/claude-code).

## License

MIT
