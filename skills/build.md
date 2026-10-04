---
name: build
description: Explain the unimplemented /curator:build placeholder only when explicitly invoked or asked about; do not use it for ordinary coding, planning, or status tasks.
allowed-tools: Bash
---

# /curator:build

This command is an informational stub. It does not implement a build loop or orchestrate engineering work. Do not promise a release date or impose the historical four-phase plan on the current task.

When explicitly invoked, explain that limitation and point to the implemented commands:

- `/curator:capture <text>` records a local observation that expires after seven days.
- `/curator:recall <query>` searches MemPalace when available, otherwise the local pattern-signal log.
- `/curator:memory` reports local state; `--review` lists deferred proposals.

Completion is a brief, accurate explanation; no files, project settings, or workflows need to be changed. Read `$CURATOR_HOME/docs/superpowers/specs/2026-04-11-curator-design.md` from the plugin source root (not the current project) only when the user asks about the historical build-loop proposal, and label it as unimplemented design history.
