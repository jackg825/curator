#!/usr/bin/env bash
# core/lib/common.sh — Shared helpers for all curator scripts.
# This file is sourced, not executed.

set -euo pipefail

# Resolve state directory. Override via CURATOR_STATE env var for tests.
: "${CURATOR_STATE:=$HOME/.curator}"

# Log a line to stderr with [curator] prefix, level, and ISO timestamp.
curator_log() {
  local level="$1"
  shift
  local msg="$*"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[curator] ${ts} ${level} ${msg}" >&2
}

# SHA-256 hex of stdin or argument.
curator_sha256() {
  local input="${1:-}"
  if [ -n "$input" ]; then
    printf "%s" "$input" | shasum -a 256 | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

# Return the device identifier. Creates it on first call.
curator_device_id() {
  local id_file="$CURATOR_STATE/device-id"
  if [ -f "$id_file" ]; then
    cat "$id_file"
    return 0
  fi

  mkdir -p "$CURATOR_STATE"
  local hostname_slug suffix
  hostname_slug="$(hostname -s | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/-*$//')"
  suffix="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 4)"
  printf "%s-%s" "$hostname_slug" "$suffix" > "$id_file"
  cat "$id_file"
}

# Verify a binary is on PATH. Fail loudly if not.
curator_require_bin() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "curator: missing required binary: $bin" >&2
    return 1
  fi
}
