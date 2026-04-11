#!/usr/bin/env bash
# core/lib/mcp-client.sh — MemPalace MCP call wrapper.
# Supported URL schemes:
#   stdio                  → spawn via `claude mcp call mempalace`
#   mock://<path>          → pipe into a local script (tests only)
#   http://host:port       → POST via curl
# Requires common.sh sourced first.

: "${CURATOR_MEMPALACE_URL:=stdio}"
: "${CURATOR_MCP_TIMEOUT:=10}"  # seconds

# Internal: dispatch a JSON request to the configured MCP endpoint.
# Stdin: JSON request.
# Stdout: JSON response.
_mcp_dispatch() {
  local url="$CURATOR_MEMPALACE_URL"
  case "$url" in
    stdio)
      # Real CC-managed MCP call
      if command -v claude >/dev/null 2>&1; then
        claude mcp call mempalace --timeout "$CURATOR_MCP_TIMEOUT"
      else
        curator_log ERROR "claude CLI not found; cannot dispatch stdio MCP call"
        return 1
      fi
      ;;
    mock://*)
      local script="${url#mock://}"
      if [ ! -x "$script" ]; then
        curator_log ERROR "mock MCP script not executable: $script"
        return 1
      fi
      "$script"
      ;;
    http://*|https://*)
      if ! command -v curl >/dev/null 2>&1; then
        curator_log ERROR "curl missing; cannot use http:// MCP URL"
        return 1
      fi
      curl -s --max-time "$CURATOR_MCP_TIMEOUT" -H "Content-Type: application/json" -d @- "$url"
      ;;
    *)
      curator_log ERROR "unknown CURATOR_MEMPALACE_URL scheme: $url"
      return 1
      ;;
  esac
}

# Public: liveness check.
mcp_ping() {
  local resp
  if ! resp="$(echo '{"method":"ping"}' | _mcp_dispatch 2>/dev/null)"; then
    return 1
  fi
  echo "$resp" | jq -e '.result == "pong"' > /dev/null
}

# Public: semantic search. Prints response JSON on stdout.
# Args: $1 query, [$2 wing], [$3 hall]
mcp_search() {
  local query="$1"
  local wing="${2:-}"
  local hall="${3:-}"
  jq -cn --arg q "$query" --arg w "$wing" --arg h "$hall" \
    '{method:"search", params:{query:$q, wing:$w, hall:$h}}' \
    | _mcp_dispatch
}

# Public: write. Args: $1 type, $2 payload JSON.
mcp_write() {
  local type="$1"
  local payload="$2"
  local resp
  resp="$(jq -cn --arg t "$type" --argjson p "$payload" \
    '{method:"write", params:{type:$t, payload:$p}}' \
    | _mcp_dispatch)" || return 1
  # Success if response has .result and not .error
  echo "$resp" | jq -e '.result != null' > /dev/null
}
