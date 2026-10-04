# Curator

A small Claude Code plugin that adds two things on top of native CC behavior:

1. **Y/n/d pattern proposal** — when curator detects a candidate pattern in the current session, the next `UserPromptSubmit` hook surfaces it once and asks the user to confirm, skip, or defer. One proposal per session, hard-capped (HR-2).
2. **Local 7-day pattern-signal log** — `/curator:capture <text>` appends an observation to `<repo>/memory/pattern-signal.md`; the Stop hook prunes entries older than 7 days. CC's native Sonnet selector picks the file up on demand via mtime ordering.

That's it. Curator does **not** own persistent storage, MCP integration, or cross-session semantic memory.

## What changed in v1.2

v1.0 shipped with a write-through MCP architecture targeting MemPalace. After verification ([issue #1](https://github.com/jackg825/curator/issues/1)) we discovered the spec assumed a `claude mcp call` CLI that does not exist, AND that MemPalace has no concept of "absolute rules" that could be projected reliably.

v1.2 drops the entire MCP integration and the L0 projection. What remains is the part that always worked locally: the Y/n/d UX and the pattern-signal log. For real persistent semantic memory, **install [MemPalace](https://github.com/milla-jovovich/mempalace) directly** — its own native Claude Code plugin handles auto-save Stop hooks. Curator complements it; it doesn't replace it.

`/curator:recall <query>` shells out to the `mempalace search` CLI when available, and falls back to `grep` over the local pattern-signal otherwise.

## Install

See [`docs/quickstart.md`](docs/quickstart.md).

## Commands

| Command | Behavior |
|---|---|
| `/curator:capture <text>` | Append to `pattern-signal.md` (local 7d rolling) |
| `/curator:recall <query>` | `mempalace search` if available, else `grep` over `pattern-signal.md` |
| `/curator:memory` | Status: pattern-signal entries, mempalace CLI availability, pending proposals |
| `/curator:memory --review` | List deferred pattern proposals |
| `/curator:build` | Informational stub; no build loop is implemented |

## Hooks

| Hook | Behavior |
|---|---|
| `SessionStart` | Reset per-session state (`session-state.json`, proposal count) |
| `UserPromptSubmit` | Emit one Y/n/d pattern proposal per session if a candidate exists |
| `Stop` | Prune `pattern-signal.md` to last 7 days |

## Status

**v1.2.0 — production-ready for the limited scope above.**

- 48 bats unit tests + roundtrip integration + HR-1/HR-2/HR-3 acceptance
- No external runtime dependencies (mempalace is optional)
- Idempotent install / uninstall via jq-patched `settings.json`

## Design history

- v1.0 → v1.2 evolution and the F6 deep-dive: [issue #1](https://github.com/jackg825/curator/issues/1)
- Original spec (now historical): [`docs/superpowers/specs/2026-04-11-curator-design.md`](docs/superpowers/specs/2026-04-11-curator-design.md)
- Original implementation plan: [`docs/superpowers/plans/2026-04-11-curator-plan.md`](docs/superpowers/plans/2026-04-11-curator-plan.md)

## License

MIT
