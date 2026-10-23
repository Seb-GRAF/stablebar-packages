# Reads Claude Code's or Codex's JSON events, one per line, and gives the answer, thinking and session so far.
# A line still being written isn't JSON yet and is skipped.
def message: (fromjson? | .error.message // .message) // .;

reduce (inputs | fromjson? // empty) as $event ({answer: "", thinking: "", session: "", error: ""};
  if $event.type == "stream_event" and $event.event.type == "content_block_delta" then
    if $event.event.delta.type == "text_delta" then .answer += $event.event.delta.text
    elif $event.event.delta.type == "thinking_delta" then .thinking += $event.event.delta.thinking
    else . end
  elif $event.type == "system" and $event.subtype == "init" then .session = $event.session_id
  elif $event.type == "result" then
    .session = $event.session_id | if $event.is_error then .error = ($event.result // "Claude Code failed." | message) else . end
  elif $event.type == "thread.started" then .session = $event.thread_id
  elif $event.type == "item.completed" and $event.item.type == "agent_message" then
    .answer += (if .answer == "" then "" else "\n\n" end) + $event.item.text
  elif $event.type == "item.completed" and $event.item.type == "reasoning" then .thinking += $event.item.text + "\n\n"
  elif $event.type == "turn.failed" then .error = ($event.error.message // "Codex failed." | message)
  elif $event.type == "error" then .error = ($event.message // "Codex failed." | message)
  else . end)
