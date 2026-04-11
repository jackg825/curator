# Curator Quickstart (5 minutes)

Curator is a Claude Code plugin that gives you persistent, searchable memory across sessions and repos, backed by MemPalace.

## 1. Install MemPalace first (if not already installed)

Curator depends on MemPalace as a separate MCP server. Choose one path:

**Local stdio (single machine):**
```bash
pip install mempalace
claude mcp add mempalace -- mempalace serve --stdio
```

**Docker:**
```bash
docker run -d --name mempalace -p 7890:7890 -v ~/.mempalace:/data mempalace/mempalace
claude mcp add mempalace --url http://localhost:7890
```

Verify:
```bash
claude mcp list | grep mempalace
```

## 2. Install curator

```bash
claude plugin marketplace add jackg825/curator
claude plugin install curator@jackg825
```

The postInstall hook runs preflight + install automatically. Review the preflight report at `~/.curator/preflight-*.log` before continuing.

## 3. First session

Open a Claude Code session in any repo. At session start you should see:
- `~/.claude/projects/<repo>/memory/MEMORY.md` auto-generated with L0 template
- `~/.curator/device-id` created (check with `cat ~/.curator/device-id`)

Try the commands:

```
/curator:memory                   # should show [MEMORY.md] [pattern-signal] [MemPalace] status
/curator:capture use pnpm         # write a feedback memory
/curator:recall "pnpm"            # search for it
```

## 4. Inspect state

```bash
ls ~/.curator/
#  device-id  install-receipt.json  pending_sync.jsonl  session-state.json  preflight-*.log
```

## 5. Uninstall (cleanly)

```bash
~/.claude/plugins/.../curator/core/scripts/uninstall.sh --keep-state
# or --purge to also delete ~/.curator
```

## Next steps

- Read the full spec: [`docs/superpowers/specs/2026-04-11-curator-design.md`](superpowers/specs/2026-04-11-curator-design.md)
- Phase 2 multi-device: see spec § Multi-Device Architecture
