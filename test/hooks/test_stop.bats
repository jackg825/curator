#!/usr/bin/env bats
# v1.2: Stop hook prunes pattern-signal.md only. Reconcile path deleted.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_HOME="$REPO_ROOT"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CLAUDE_PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$CLAUDE_PROJECT_ROOT/memory" "$CURATOR_STATE"
  echo "mac-test" > "$CURATOR_STATE/device-id"
}

@test "stop prunes pattern-signal entries older than 7 days" {
  local ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
  cat > "$ps" <<'EOF'
<!-- curator-pattern-signal schema_version=1 -->
- 2020-01-01T00:00:00Z | ancient pattern | device=old
- __RECENT__ | fresh pattern | device=new
EOF
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sed -i.bak "s|__RECENT__|$now|" "$ps" && rm "$ps.bak"

  "$REPO_ROOT/core/hooks/stop.sh"
  grep -q "fresh pattern" "$ps"
  ! grep -q "ancient pattern" "$ps"
}

@test "stop touches pattern-signal mtime even when content unchanged" {
  local ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
  touch -t 202001010000 "$ps" 2>/dev/null || touch "$ps"
  local old_mtime
  old_mtime=$(stat -f "%m" "$ps" 2>/dev/null || stat -c "%Y" "$ps")

  "$REPO_ROOT/core/hooks/stop.sh"

  local new_mtime
  new_mtime=$(stat -f "%m" "$ps" 2>/dev/null || stat -c "%Y" "$ps")
  [ "$new_mtime" -gt "$old_mtime" ]
}

@test "stop exits 0 when no pattern-signal exists yet" {
  run "$REPO_ROOT/core/hooks/stop.sh"
  [ "$status" -eq 0 ]
}

@test "stop is fast (under 5 seconds without pattern-signal)" {
  local start
  start=$(date +%s)
  "$REPO_ROOT/core/hooks/stop.sh"
  local end
  end=$(date +%s)
  [ "$((end - start))" -lt 5 ]
}
