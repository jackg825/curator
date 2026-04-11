#!/usr/bin/env bash
# core/scripts/health-check.sh — emit JSON health summary.
# Usage: health-check.sh
# Exit code: 0 if all checks green, 1 if any red.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/mcp-client.sh"

bin_status() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 && echo "ok" || echo "missing"
}

mcp_status() {
  if mcp_ping 2>/dev/null; then
    echo "connected"
  else
    echo "unreachable"
  fi
}

state_status() {
  [ -d "$CURATOR_STATE" ] && echo "present" || echo "absent"
}

receipt_version() {
  local receipt="$CURATOR_STATE/install-receipt.json"
  if [ -f "$receipt" ]; then
    jq -r '.version // "unknown"' "$receipt"
  else
    echo "not-installed"
  fi
}

main() {
  local jq_status yq_status shasum_status
  jq_status="$(bin_status jq)"
  yq_status="$(bin_status yq)"
  shasum_status="$(bin_status shasum)"
  local mcp
  mcp="$(mcp_status)"
  local state
  state="$(state_status)"
  local ver
  ver="$(receipt_version)"

  jq -cn \
    --arg jq_s "$jq_status" \
    --arg yq_s "$yq_status" \
    --arg sha_s "$shasum_status" \
    --arg mcp_s "$mcp" \
    --arg state_s "$state" \
    --arg ver "$ver" \
    '{
      binaries: {jq:$jq_s, yq:$yq_s, shasum:$sha_s},
      mempalace: $mcp_s,
      state: $state_s,
      version: $ver
    }'

  # Exit non-zero if anything critical is broken
  if [ "$jq_status" = "missing" ] || [ "$yq_status" = "missing" ] || [ "$shasum_status" = "missing" ]; then
    exit 1
  fi
}

main "$@"
