#!/usr/bin/env bash
# memory-bridge/reconcile.sh — retry pending_sync.jsonl writes against MemPalace.
# Runs during SessionStart hook. Idempotent by content_hash.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/journal.sh"
source "$CURATOR_HOME/core/lib/mcp-client.sh"

# 1. Prune entries older than 7 days first (always)
journal_prune_older_than 7 || true

# 2. Iterate pending entries and retry each
journal_pending_entries | while IFS= read -r entry; do
  if [ -z "$entry" ]; then
    continue
  fi
  local_hash=$(echo "$entry" | jq -r '.content_hash')
  local_type=$(echo "$entry" | jq -r '.type')
  local_payload=$(echo "$entry" | jq -c '.payload')

  if mcp_write "$local_type" "$local_payload"; then
    journal_mark_resolved "$local_hash" "mempalace"
    curator_log INFO "reconciled: $local_hash"
  else
    curator_log WARN "reconcile failed for $local_hash (will retry next session)"
  fi
done

exit 0
