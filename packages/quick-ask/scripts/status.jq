# The widget's output: the agents to choose from with their models and effort levels, the current conversation with
# the answer as it arrives, and the history. The arguments come from status.sh.
def efforts: {instant: "Instant", low: "Low", medium: "Medium", high: "High", xhigh: "Extra high", max: "Max", ultra: "Ultra"};
def names: {claude: "Claude Code", codex: "Codex"};
def ago: (now - .) as $seconds
  | if $seconds < 60 then "just now"
    elif $seconds < 3600 then "\($seconds / 60 | floor) min ago"
    elif $seconds < 86400 then "\($seconds / 3600 | floor) h ago"
    else strflocaltime("%d %b") end;
def plural($count; $noun): "\($count) \($noun)\(if $count == 1 then "" else "s" end)";
def command($action): "\"$PACKAGE_DIR/scripts/ask.sh\" \($action)";

def chosen: select(. != null and . != "");

($codexModels | map(select(.value == $codexDefault)) | first) as $codexDefaultModel
| ($settings.codex.model // "") as $codexModel
| (if $codexModel == "" then $codexDefaultModel else ($codexModels | map(select(.value == $codexModel)) | first) end) as $codexChosen
| ($settings.claude.model // "") as $claudeModel
| [
    {value: "", title: "Default", detail: "Your Claude Code default"},
    {value: "fable", title: "Fable", detail: "The most capable, for the hardest questions"},
    {value: "opus", title: "Opus", detail: "Deep reasoning for hard problems"},
    {value: "sonnet", title: "Sonnet", detail: "Fast and smart for everyday questions"},
    {value: "haiku", title: "Haiku", detail: "The quickest answers"}
  ] as $claudeModels
| (($claudeModels | map({key: "claude:\(.value)", value: .title})) + ($codexModels | map({key: "codex:\(.value)", value: .title}))
   + [{key: "codex:", value: "Default"}] | from_entries) as $modelTitles
| ($conversation.turns // []) as $turns
| ($live != null) as $running
| {
  text: "",
  icon: (if $running then "ellipsis.bubble.fill" else "sparkles" end),
  fields: {
    agent: ($settings.agent // "claude"),
    chat: (if $view == "history" then "" else "1" end),
    history: (if $view == "history" then "1" else "" end),
    conversation: (if $conversation == null then "" else "1" end),
    running: (if $running then "1" else "" end),
    hasHistory: (if ($history | length) > 0 then "1" else "" end),
    noHistory: (if ($history | length) == 0 then "Nothing yet. Every chat you start appears here." else "" end)
  },
  lists: {
    turns: ($turns | to_entries | map(
      .key as $index
      | ($index == ($turns | length) - 1) as $isLast
      | ($running and $isLast) as $arriving
      | .value
      | (if $arriving then $live else . end) as $answer
      | (if $arriving or ($answer.answer // "") == "" then "" else command("copy \($index)") end) as $copy
      | (if $isLast and ($running | not) then command("retry") else "" end) as $retry
      | {
        question,
        answer: ($answer.answer // ""),
        status: (if $arriving and ($answer.answer // "") == "" then "Thinking" else "" end),
        thoughts: (if $arriving and ($answer.answer // "") == "" then ($answer.thinking // "" | if length > 600 then "…" + .[-600:] else . end) else "" end),
        note: (if ($answer.error // "") != "" then "Couldn’t answer: \($answer.error)" elif .stopped == true then "Stopped." else "" end),
        copy: $copy,
        retry: $retry,
        actions: (if $copy + $retry == "" then "" else "1" end)
      })),
    agents: [
      {value: "claude", title: "Claude Code", icon: "sparkle",
       detail: (if $claudePath == "" then "Install Claude Code to ask it." else "Runs \($claudePath) without tools." end),
       option: $claudeModel, level: (($settings.claude.effort | chosen) // "medium"), levelsTitle: "Effort"},
      {value: "codex", title: "Codex", icon: "curlybraces",
       detail: (if $codexPath == "" then "Install Codex to ask it." else "Runs \($codexPath) in a read-only sandbox." end),
       option: $codexModel,
       level: (($settings.codex.effort | chosen) // (if $codexModel == "" then $codexEffort | chosen else null end) // $codexChosen.effort // "medium"),
       levelsTitle: "Effort"}
    ],
    models: (
      ($claudeModels | map(. + {group: "claude"}))
      + [{group: "codex", value: "", title: "Default",
          detail: ("Your Codex default" + (if $codexDefaultModel then ", \($codexDefaultModel.title)" else "" end))}]
      + ($codexModels | map({group: "codex", value, title, detail}))
    ),
    efforts: (
      (["instant", "low", "medium", "high", "xhigh", "max"] | map({group: "claude", value: ., title: efforts[.]}))
      + (($codexChosen.efforts // ["low", "medium", "high", "xhigh"]) | map({group: "codex", value: ., title: (efforts[.] // .)}))
    ),
    stars: ($settings.stars // []),
    history: ($history | map(((.turns | last | .agent) // .agent) as $agent | {
      title: .turns[0].question,
      detail: "\(names[$agent]) · \((.turns | last | .model // "") as $model | $modelTitles[$agent + ":" + $model] // $model) · \(.turns | length | plural(.; "question")) · \(.created | ago)",
      open: command("open \(.id | @sh)"),
      replay: command("replay \(.id | @sh)"),
      delete: command("delete \(.id | @sh)")
    }))
  }
}
