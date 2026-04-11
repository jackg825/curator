# settings.json.patch.jq — merge curator hooks into existing settings.json
# Usage: jq -f settings.json.patch.jq --argjson curator "$CURATOR_CONFIG" settings.json

. as $existing
| .hooks //= {}
| .hooks.SessionStart //= []
| .hooks.UserPromptSubmit //= []
| .hooks.Stop //= []
# Append curator hook entries (dedup by command string)
| .hooks.SessionStart |= (
    . + ($curator.session_start | map(select(
      [.hooks[0].command] as $new_cmd |
      ([$existing.hooks.SessionStart[]?.hooks[0].command] | index($new_cmd[0])) == null
    )))
  )
| .hooks.UserPromptSubmit |= (
    . + ($curator.user_prompt_submit | map(select(
      [.hooks[0].command] as $new_cmd |
      ([$existing.hooks.UserPromptSubmit[]?.hooks[0].command] | index($new_cmd[0])) == null
    )))
  )
| .hooks.Stop |= (
    . + ($curator.stop | map(select(
      [.hooks[0].command] as $new_cmd |
      ([$existing.hooks.Stop[]?.hooks[0].command] | index($new_cmd[0])) == null
    )))
  )
