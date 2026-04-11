#!/usr/bin/env bash
# core/lib/mempalace-cli.sh — thin wrapper around the `mempalace` CLI binary.
# Curator v1.2 talks to MemPalace through its CLI subcommands instead of MCP,
# because the Claude Code CLI has no `mcp call` invocation path (see issue #1).
# Requires common.sh sourced first.
#
# Resolution order for the mempalace binary:
#   1. $CURATOR_MEMPALACE_BIN if set (test override)
#   2. `mempalace` on PATH
#   3. ~/.local/share/mempalace/venv/bin/python -m mempalace (the recommended
#      Homebrew-Python install path documented in issue #1 v1.1 comment)
#
# All public functions return non-zero when mempalace is unavailable so callers
# can fall back gracefully.

_curator_mempalace_resolve() {
  if [ -n "${CURATOR_MEMPALACE_BIN:-}" ]; then
    if [ -x "$CURATOR_MEMPALACE_BIN" ] || command -v "$CURATOR_MEMPALACE_BIN" >/dev/null 2>&1; then
      echo "$CURATOR_MEMPALACE_BIN"
      return 0
    fi
    return 1
  fi
  if command -v mempalace >/dev/null 2>&1; then
    echo "mempalace"
    return 0
  fi
  local venv="$HOME/.local/share/mempalace/venv/bin/python"
  if [ -x "$venv" ]; then
    echo "$venv -m mempalace"
    return 0
  fi
  return 1
}

# Public: returns 0 iff a mempalace CLI is reachable.
mempalace_available() {
  _curator_mempalace_resolve >/dev/null
}

# Public: print resolved invocation form (for diagnostics).
mempalace_resolved_command() {
  _curator_mempalace_resolve
}

# Public: print mempalace version. Echoes "unknown" if it can't be determined.
# mempalace has no --version flag, so we read it via `pip show` against the
# resolved python interpreter when possible; otherwise falls back to a probe.
mempalace_version() {
  local cmd
  cmd="$(_curator_mempalace_resolve)" || { echo "unavailable"; return 1; }
  case "$cmd" in
    *python*-m*mempalace)
      local py="${cmd%% -m mempalace}"
      "$py" -c "import mempalace; print(getattr(mempalace, '__version__', 'unknown'))" 2>/dev/null || echo "unknown"
      ;;
    *)
      # Bare mempalace binary: no --version, try `pip show` against any py3 on PATH.
      if command -v pip3 >/dev/null 2>&1; then
        pip3 show mempalace 2>/dev/null | awk -F': ' '/^Version/{print $2}' | head -n 1 \
          || echo "unknown"
      else
        echo "unknown"
      fi
      ;;
  esac
}

# Public: semantic search. Args: $1 query, [$2 wing], [$3 results-cap (default 5)]
# Prints raw search output to stdout. Returns 0 if mempalace ran, even when no
# matches — callers parse output to detect "No results found".
mempalace_search() {
  local query="$1"
  local wing="${2:-}"
  local results="${3:-5}"
  local cmd
  cmd="$(_curator_mempalace_resolve)" || {
    curator_log WARN "mempalace not available; cannot search"
    return 1
  }
  local args=("search" "$query" "--results" "$results")
  if [ -n "$wing" ]; then
    args+=("--wing" "$wing")
  fi
  # Filter out the noisy "Number of requested results N is greater..." stderr line.
  $cmd "${args[@]}" 2> >(grep -v "Number of requested results" >&2)
}
