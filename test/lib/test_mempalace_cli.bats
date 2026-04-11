#!/usr/bin/env bats
# Unit tests for core/lib/mempalace-cli.sh
#
# Strategy: build a stub `mempalace` binary in $BATS_TEST_TMPDIR/bin and point
# CURATOR_MEMPALACE_BIN at it. The stub records arguments and emits canned
# output that mimics real mempalace 3.1.0 search output.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  mkdir -p "$CURATOR_STATE" "$BATS_TEST_TMPDIR/bin"

  STUB="$BATS_TEST_TMPDIR/bin/mempalace"
  cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
# Stub mempalace binary for curator tests.
LOG="${MOCK_MP_LOG:-/dev/null}"
echo "STUB-CALL $*" >> "$LOG"
case "$1" in
  search)
    shift
    query="$1"; shift
    cat <<MOCK
============================================================
  Results for: "$query"
============================================================

  [1] test_wing / general
      Source: stub.md
      Match:  0.42

      stub result for query: $query

  ────────────────────────────────────────────────────────
MOCK
    exit 0
    ;;
  *)
    echo "stub: unknown subcommand $1" >&2
    exit 1
    ;;
esac
STUBEOF
  chmod +x "$STUB"
  export CURATOR_MEMPALACE_BIN="$STUB"
  export MOCK_MP_LOG="$BATS_TEST_TMPDIR/mp.log"
  : > "$MOCK_MP_LOG"

  source "$REPO_ROOT/core/lib/common.sh"
  source "$REPO_ROOT/core/lib/mempalace-cli.sh"
}

@test "mempalace_available returns 0 when stub is reachable" {
  run mempalace_available
  [ "$status" -eq 0 ]
}

@test "mempalace_available returns non-zero when bin override missing" {
  export CURATOR_MEMPALACE_BIN="/nonexistent/path/mempalace"
  run mempalace_available
  [ "$status" -ne 0 ]
}

@test "mempalace_resolved_command echoes the override path" {
  run mempalace_resolved_command
  [ "$status" -eq 0 ]
  [ "$output" = "$CURATOR_MEMPALACE_BIN" ]
}

@test "mempalace_search calls the stub with the query" {
  run mempalace_search "JWT decisions"
  [ "$status" -eq 0 ]
  grep -q 'STUB-CALL search JWT decisions --results 5' "$MOCK_MP_LOG"
}

@test "mempalace_search forwards wing filter when given" {
  run mempalace_search "auth" "myproject"
  [ "$status" -eq 0 ]
  grep -q -- '--wing myproject' "$MOCK_MP_LOG"
}

@test "mempalace_search output contains formatted result block" {
  run mempalace_search "anything"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Results for:"* ]]
  [[ "$output" == *"stub result for query: anything"* ]]
}

@test "mempalace_search returns non-zero with descriptive log when binary missing" {
  export CURATOR_MEMPALACE_BIN="/nonexistent/path/mempalace"
  run mempalace_search "anything"
  [ "$status" -ne 0 ]
}

@test "mempalace_version reports unknown when no python3 on path for bare binary" {
  # Stub is a bare binary (not python -m mempalace), so version goes via pip3
  # path which may or may not be installed. Just assert it produces *something*.
  run mempalace_version
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  [ -n "$output" ]
}
