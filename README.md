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

**v1.0 — alpha. Real MCP integration is deferred to v1.1.**

Curator v1 is structurally complete (24 implementation tasks, 67 unit tests, end-to-end roundtrip + HR acceptance pass), but the `mcp-client.sh` stdio transport assumes a `claude mcp call` CLI that does not exist. As a result, anything that needs to talk to a real MemPalace instance (write-through capture, semantic recall, SessionStart L0 projection) currently no-ops or falls back to local-only behavior. The Y/n/d pattern proposal pipeline, journal, install/uninstall, and `/curator:memory` status command all work without MCP and are usable today.

See **[issue #1](https://github.com/jackg825/curator/issues/1)** for the F6 follow-up evidence and the three proposed fix paths for v1.1.

`build-loop` workflow (`/curator:build`) is a stub (v1.2). 主動警告, dashboard, and multi-user team mode are deferred (v2.x). Multi-device Mac Mini runtime is phase 2.

## License

MIT
