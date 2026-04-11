#!/usr/bin/env bats
# Unit tests for core/lib/journal.sh

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  mkdir -p "$CURATOR_STATE"
  # shellcheck source=../../core/lib/common.sh
  source "$REPO_ROOT/core/lib/common.sh"
  # shellcheck source=../../core/lib/journal.sh
  source "$REPO_ROOT/core/lib/journal.sh"
}

@test "journal_append creates pending_sync.jsonl with one entry" {
  journal_append "feedback" '{"text":"hello"}'
  [ -f "$CURATOR_STATE/pending_sync.jsonl" ]
  local line_count
  line_count=$(wc -l < "$CURATOR_STATE/pending_sync.jsonl")
  [ "$line_count" -eq 1 ]
}

@test "journal_append emits a JSON object with required fields" {
  journal_append "feedback" '{"text":"hello"}'
  local entry
  entry=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl")
  # Verify fields present
  echo "$entry" | jq -e '.content_hash, .ts, .device_id, .type, .payload, .pending' > /dev/null
}

@test "journal_append computes content_hash deterministically" {
  journal_append "feedback" '{"text":"same"}'
  local hash1
  hash1=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl" | jq -r .content_hash)
  rm "$CURATOR_STATE/pending_sync.jsonl"
  journal_append "feedback" '{"text":"same"}'
  local hash2
  hash2=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl" | jq -r .content_hash)
  [ "$hash1" = "$hash2" ]
}

@test "journal_append includes device_id in each entry" {
  echo "mac-test" > "$CURATOR_STATE/device-id"
  journal_append "feedback" '{"text":"hi"}'
  local entry_device
  entry_device=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl" | jq -r .device_id)
  [ "$entry_device" = "mac-test" ]
}

@test "journal_append sets pending array to [mempalace] by default" {
  journal_append "feedback" '{"text":"hi"}'
  local pending
  pending=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl" | jq -c .pending)
  [ "$pending" = '["mempalace"]' ]
}

@test "journal_mark_resolved removes target from pending array" {
  journal_append "feedback" '{"text":"hello"}'
  local hash
  hash=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl" | jq -r .content_hash)
  journal_mark_resolved "$hash" "mempalace"
  local pending
  pending=$(grep "$hash" "$CURATOR_STATE/pending_sync.jsonl" | tail -n 1 | jq -c .pending)
  [ "$pending" = '[]' ]
}

@test "journal_pending_entries returns only entries with non-empty pending" {
  journal_append "feedback" '{"text":"first"}'
  local hash1
  hash1=$(head -n 1 "$CURATOR_STATE/pending_sync.jsonl" | jq -r .content_hash)
  journal_append "feedback" '{"text":"second"}'
  journal_mark_resolved "$hash1" "mempalace"

  run journal_pending_entries
  [ "$status" -eq 0 ]
  # Only "second" should be pending
  [[ "$output" == *"second"* ]]
  [[ "$output" != *"first"* ]]
}

@test "journal_append is append-only (does not overwrite existing entries)" {
  journal_append "feedback" '{"text":"first"}'
  journal_append "pattern" '{"text":"second"}'
  local count
  count=$(wc -l < "$CURATOR_STATE/pending_sync.jsonl")
  [ "$count" -eq 2 ]
}

@test "journal_prune_older_than drops entries older than N days" {
  # Manually insert an old entry
  mkdir -p "$CURATOR_STATE"
  cat > "$CURATOR_STATE/pending_sync.jsonl" <<'OLD'
{"content_hash":"old1","ts":"2020-01-01T00:00:00Z","device_id":"x","type":"feedback","payload":{},"pending":["mempalace"]}
OLD
  journal_append "feedback" '{"text":"fresh"}'

  journal_prune_older_than 7  # 7 days

  run cat "$CURATOR_STATE/pending_sync.jsonl"
  [[ "$output" != *"old1"* ]]
  [[ "$output" == *"fresh"* ]]
}
