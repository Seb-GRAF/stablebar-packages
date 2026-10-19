# Agent status

Counts sessions waiting for permission or input, including finished turns. The widget uses
the `warning` state when that count is nonzero. Its popup lists each project's latest status.
Click a row to bring the terminal or editor app forward, using the bundle ID inherited by
the hook in `__CFBundleIdentifier`. It opens the app, not a particular tab. If that variable
is absent, the row still shows the status but cannot open an app.

Requires `jq` on the PATH of StableBar's login shell and the terminals running your agents.
The hook uses macOS to find the installed StableBar app and send an event in the background.
You do not need a `StableBar` command on PATH.

## Claude Code

After installing and enabling the package, merge these entries into the `hooks` object in
`~/.claude/settings.json`. Keep your existing hooks. The commands below use the default
StableBar configuration and the installed version `1.0.1`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "\"$HOME/.config/stablebar/packages/agent-status/1.0.1/scripts/hook.sh\" claude \"$HOME/.config/stablebar/config.json\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$HOME/.config/stablebar/packages/agent-status/1.0.1/scripts/hook.sh\" claude \"$HOME/.config/stablebar/config.json\""
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$HOME/.config/stablebar/packages/agent-status/1.0.1/scripts/hook.sh\" claude \"$HOME/.config/stablebar/config.json\""
          }
        ]
      }
    ]
  }
}
```

`Notification` records **Waiting**, `Stop` records **Finished**, and `UserPromptSubmit`
records **Working**. Status changes when the next configured hook fires. See the
[Claude Code hooks reference](https://code.claude.com/docs/en/hooks).

## Codex

Add this top-level setting to `~/.codex/config.toml`. Replace `/Users/you` with your home
directory; Codex's command array does not expand `$HOME`:

```toml
notify = [
  "/Users/you/.config/stablebar/packages/agent-status/1.0.1/scripts/hook.sh",
  "codex",
  "/Users/you/.config/stablebar/config.json"
]
```

If you already use `notify`, call this hook from your existing notification program instead
of replacing it. Pass `codex`, the StableBar configuration path, then the JSON argument.

Codex's [`notify` hook](https://developers.openai.com/codex/config-advanced/#notifications)
reports completed turns only. It records **Finished**; it cannot report permission requests
or clear the status when another turn starts.

## Session files

Each hook writes one JSON file in `agent-status/` beside the selected StableBar configuration,
then sends the `agent` event to that configuration through the installed app. Files hold the latest
status even when StableBar coalesces events. The widget runs once at startup and then on
`agent` events; it does not poll.

Session files remain after an agent exits. Remove the corresponding file, then run
`open -g -n -b org.stablebar.app --args --config /path/to/config.json --trigger agent`
to clear an old session from the widget. No transcript or prompt is saved.

For a different StableBar configuration, change both paths in the hook setup. Package files
live in `packages/agent-status/1.0.1/` beside that configuration. Update the hook path when
you install a new package version. Installing this package does not edit your agent settings.
