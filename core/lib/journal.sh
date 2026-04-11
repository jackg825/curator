#!/usr/bin/env bash
# core/lib/journal.sh — pending_sync.jsonl I/O with content-hash idempotency.
# Requires common.sh to be sourced first (curator_log, curator_sha256, curator_device_id).

: "${CURATOR_STATE:=$HOME/.curator}"
JOURNAL_PATH="$CURATOR_STATE/pending_sync.jsonl"

# Append a write-attempt to the journal.
# Args:
#   $1: type (e.g., "feedback", "pattern", "capture")
#   $2: payload (JSON string)
# Writes: one JSONL line with content_hash, ts, device_id, type, payload, pending.
journal_append() {
  local type="$1"
  local payload="$2"
  mkdir -p "$CURATOR_STATE"

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local device_id
  device_id="$(curator_device_id)"
  # Content hash covers type + payload + ts (idempotent retries of same content hit the same hash)
  local content_hash
  content_hash="$(printf "%s\0%s\0%s" "$type" "$payload" "$ts" | shasum -a 256 | awk '{print $1}')"

  # Build entry with jq to ensure valid JSON
  jq -cn --arg hash "$content_hash" \
        --arg ts "$ts" \
        --arg dev "$device_id" \
        --arg type "$type" \
        --argjson payload "$payload" \
        '{content_hash:$hash, ts:$ts, device_id:$dev, type:$type, payload:$payload, pending:["mempalace"]}' \
    >> "$JOURNAL_PATH"
}

# Mark a target as resolved for a given content_hash.
# Args:
#   $1: content_hash
#   $2: target to remove from pending (e.g., "mempalace")
# Strategy: append a resolution marker entry (keeps append-only semantics).
journal_mark_resolved() {
  local hash="$1"
  local target="$2"
  [ -f "$JOURNAL_PATH" ] || return 0

  # Rewrite in-place: for entries matching the hash, remove target from pending array.
  local tmp
  tmp="$(mktemp)"
  jq -c --arg hash "$hash" --arg target "$target" '
    if .content_hash == $hash then
      .pending = (.pending - [$target])
    else
      .
    end
  ' "$JOURNAL_PATH" > "$tmp"
  mv "$tmp" "$JOURNAL_PATH"
}

# Emit all entries whose pending array is non-empty.
journal_pending_entries() {
  [ -f "$JOURNAL_PATH" ] || return 0
  jq -c 'select(.pending | length > 0)' "$JOURNAL_PATH"
}

# Drop entries older than N days.
# Args:
#   $1: days (integer)
journal_prune_older_than() {
  local days="$1"
  [ -f "$JOURNAL_PATH" ] || return 0

  local cutoff
  cutoff="$(date -u -v-"${days}d" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "${days} days ago" +%Y-%m-%dT%H:%M:%SZ)"

  local tmp
  tmp="$(mktemp)"
  jq -c --arg cutoff "$cutoff" 'select(.ts >= $cutoff)' "$JOURNAL_PATH" > "$tmp"
  mv "$tmp" "$JOURNAL_PATH"
}
