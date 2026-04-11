#!/usr/bin/env bats
# Unit tests for core/lib/common.sh

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=../../core/lib/common.sh
  source "$REPO_ROOT/core/lib/common.sh"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  mkdir -p "$CURATOR_STATE"
}

@test "curator_log writes to stderr with timestamp prefix" {
  run curator_log INFO "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[curator]"* ]]
  [[ "$output" == *"INFO"* ]]
  [[ "$output" == *"hello world"* ]]
}

@test "curator_sha256 returns 64 hex chars for a known string" {
  run curator_sha256 "curator test"
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 64 ]
  [[ "$output" =~ ^[a-f0-9]{64}$ ]]
}

@test "curator_sha256 is deterministic" {
  run curator_sha256 "same input"
  first="$output"
  run curator_sha256 "same input"
  [ "$first" = "$output" ]
}

@test "curator_device_id returns existing device-id when file present" {
  echo "laptop-abcd" > "$CURATOR_STATE/device-id"
  run curator_device_id
  [ "$status" -eq 0 ]
  [ "$output" = "laptop-abcd" ]
}

@test "curator_device_id generates new id when file absent" {
  rm -f "$CURATOR_STATE/device-id"
  run curator_device_id
  [ "$status" -eq 0 ]
  [ -f "$CURATOR_STATE/device-id" ]
  # Format: hostname-4chars
  [[ "$output" =~ ^[a-zA-Z0-9]+-[a-z0-9]{4}$ ]]
}

@test "curator_device_id is stable across calls" {
  run curator_device_id
  first="$output"
  run curator_device_id
  [ "$first" = "$output" ]
}

@test "curator_require_bin reports missing dependency clearly" {
  run curator_require_bin this_binary_does_not_exist_12345
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing"* ]]
  [[ "$output" == *"this_binary_does_not_exist_12345"* ]]
}

@test "curator_require_bin succeeds for existing binary" {
  run curator_require_bin bash
  [ "$status" -eq 0 ]
}
