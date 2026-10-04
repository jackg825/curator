# Project guidance

## Scope and hard requirements

Curator's implemented scope is the Claude Code pattern-proposal UX, a local seven-day `memory/pattern-signal.md` log, and optional recall via the MemPalace CLI. It does not provide MCP writes, persistent semantic storage, or projection into `MEMORY.md`. Do not reintroduce the historical `claude mcp call` design as if it were implemented.

Preserve the existing acceptance contracts:

- HR-1: the pattern-signal log must not be automatically injected into ambient context or `MEMORY.md`.
- HR-2: emit at most one Y/n/d proposal per session; preserve skip/defer behavior and the non-blocking session-start hook.
- HR-3: status reports pattern-signal state, MemPalace availability, and pending proposals.

Source hooks and libraries live in `core/`; command skills live in `skills/`. The installer symlinks those skills and patches Claude settings. Edit these owned sources, not installed plugin copies. Keep the command names and installed filenames compatible with `core/scripts/install.sh` and `uninstall.sh`.

## Checks and local state

For hook, library, installation, or command behavior changes, run the existing gates from the repository root:

```sh
bats test/lib/*.bats test/scripts/*.bats test/hooks/*.bats
bash test/roundtrip.sh
bash test/hr-acceptance.sh
```

The tests use temporary `CLAUDE_HOME`, `CURATOR_STATE`, and project directories; MemPalace calls are stubbed or disabled. Preserve that isolation. Required tooling includes Bash, bats for unit tests, jq, yq, and shasum; report unavailable tools instead of testing against real user state.

`core/scripts/install.sh` and `uninstall.sh` default to the user's Claude settings/state, so running either directly is an installation change, not a read-only check. Use the isolated tests for validation. Do not commit `.curator/` state, local observations, settings backups, or test artifacts.

Read `README.md` and `docs/quickstart.md` for current behavior and installation. `docs/superpowers/` contains design history and deferred plans; load a specific file only when the task concerns that design. `/curator:build` remains an informational stub, not an engineering workflow or a trigger for ordinary coding tasks.
