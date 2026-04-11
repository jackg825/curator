# Curator Quickstart (v1.2)

Curator is a small Claude Code plugin: Y/n/d pattern proposal UX + a 7-day rolling pattern-signal log + a `recall` command that shells out to `mempalace search` when available.

## 1. (Optional) Install MemPalace for semantic recall

Curator works without MemPalace — `/curator:recall` will fall back to `grep` over the local pattern-signal log. If you want real semantic search, install MemPalace as a separate plugin:

```bash
# Recommended: isolated venv (avoids Homebrew Python PEP 668 issues)
mkdir -p ~/.local/share/mempalace
uv venv ~/.local/share/mempalace/venv
VIRTUAL_ENV=~/.local/share/mempalace/venv uv pip install mempalace

# Verify
~/.local/share/mempalace/venv/bin/python -c "import mempalace; print(mempalace.__version__)"
```

Curator's `mempalace-cli.sh` looks for `mempalace` on `$PATH` first, then falls back to `~/.local/share/mempalace/venv/bin/python -m mempalace`.

For long-term storage, also install MemPalace's own Claude Code plugin (it has its own auto-save Stop hook):
```bash
claude plugin marketplace add milla-jovovich/mempalace
claude plugin install --scope user mempalace
```

## 2. Install curator

```bash
claude plugin marketplace add jackg825/curator
claude plugin install curator@jackg825
```

The post-install script runs preflight + install automatically. Review the preflight report at `~/.curator/preflight-*.log`.

## 3. First session

Open a Claude Code session in any repo. At session start, curator:
- Resets `~/.curator/session-state.json` (HR-2 proposal count)
- Does NOT touch `MEMORY.md` or any project files (v1.2 has no projection)

Try the commands:

```
/curator:memory                   # show [pattern-signal] [MemPalace CLI] [pending proposals]
/curator:capture use pnpm         # append observation to pattern-signal.md
/curator:recall pnpm              # mempalace search (or local grep fallback)
```

## 4. Inspect state

```bash
ls ~/.curator/
#  device-id  install-receipt.json  session-state.json  preflight-*.log  pattern-candidates/

cat <repo>/memory/pattern-signal.md
#  <!-- curator-pattern-signal schema_version=1 -->
#  - 2026-04-11T11:30:00Z | use pnpm | device=macbookpro-xxxx
```

Note: there is no `pending_sync.jsonl`. v1.2 dropped that journal because curator no longer writes to MemPalace (mempalace's own auto-save handles that).

## 5. Uninstall

```bash
~/.claude/plugins/.../curator/core/scripts/uninstall.sh --keep-state
# or --purge to also delete ~/.curator
```

## What about real cross-session memory?

Curator does NOT do this. For persistent semantic memory, install MemPalace's own plugin (above). Curator focuses on the lightweight UX bits that MemPalace doesn't cover:
- One-per-session Y/n/d pattern proposal cadence (HR-2)
- Local 7-day rolling pattern-signal log
- A status overview command

See [issue #1](https://github.com/jackg825/curator/issues/1) for the v1.0 → v1.2 design history.
