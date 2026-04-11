#!/usr/bin/env bash
# test/fixtures/mock-mempalace.sh — canned responder for curator tests.
# Reads a single MCP-style request from stdin and emits a canned response.
# Records the request to MOCK_MCP_LOG for assertion.

: "${MOCK_MCP_LOG:=/tmp/mock-mempalace.log}"
: "${MOCK_MCP_MODE:=ok}"  # ok | fail | timeout

input="$(cat)"
echo "---REQUEST---" >> "$MOCK_MCP_LOG"
echo "$input" >> "$MOCK_MCP_LOG"

case "$MOCK_MCP_MODE" in
  fail)
    echo '{"error":"simulated failure"}'
    exit 1
    ;;
  timeout)
    sleep 30
    exit 0
    ;;
  ok)
    # Parse method and respond
    method="$(echo "$input" | jq -r '.method // empty')"
    case "$method" in
      ping)
        echo '{"result":"pong"}'
        ;;
      search)
        echo '{"result":[{"text":"mock memory","wing":"test","hall":"hall_facts"}]}'
        ;;
      write)
        echo '{"result":{"id":"mock-drawer-1"}}'
        ;;
      *)
        echo '{"result":null}'
        ;;
    esac
    ;;
esac
