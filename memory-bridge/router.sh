#!/usr/bin/env bash
# memory-bridge/router.sh — declarative routing dispatcher.
# Reads routing-rules.yaml and returns destination config for a given type/text/metadata.

: "${CURATOR_HOME:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${CURATOR_RULES:=$CURATOR_HOME/memory-bridge/routing-rules.yaml}"

# Args:
#   $1: type (e.g., feedback, pattern)
#   $2: text
#   $3: optional metadata (key=value pairs, space-separated), e.g., "confidence=0.9"
# Output: "memory:<dest>,mempalace:<dest>[,priority:<p>]"
router_match() {
  local type="$1"
  local text="${2:-}"
  local metadata="${3:-}"
  local text_len=${#text}

  local confidence=0
  if [[ "$metadata" == *confidence=* ]]; then
    confidence=$(echo "$metadata" | sed -n 's/.*confidence=\([0-9.]*\).*/\1/p')
  fi

  local rule_count
  rule_count=$(yq '.rules | length' "$CURATOR_RULES")

  local i
  for ((i = 0; i < rule_count; i++)); do
    local rule_type rule_min_len rule_min_conf
    rule_type=$(yq ".rules[$i].match.type // \"\"" "$CURATOR_RULES")
    rule_min_len=$(yq ".rules[$i].match.min_length // 0" "$CURATOR_RULES")
    rule_min_conf=$(yq ".rules[$i].match.min_confidence // 0" "$CURATOR_RULES")

    if [ "$rule_type" != "$type" ]; then
      continue
    fi
    if [ "$text_len" -lt "$rule_min_len" ]; then
      continue
    fi
    if awk -v c="$confidence" -v m="$rule_min_conf" 'BEGIN{exit !(c+0 < m+0)}'; then
      continue
    fi

    local mem_dest mp_dest prio
    mem_dest=$(yq ".rules[$i].destinations.memory // \"skip\"" "$CURATOR_RULES")
    mp_dest=$(yq ".rules[$i].destinations.mempalace // \"skip\"" "$CURATOR_RULES")
    prio=$(yq ".rules[$i].destinations.priority // \"medium\"" "$CURATOR_RULES")

    echo "memory:$mem_dest,mempalace:$mp_dest,priority:$prio"
    return 0
  done

  echo "memory:skip,mempalace:skip,priority:low"
  return 0
}
