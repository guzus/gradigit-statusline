# claude-statusline

A feature-rich, true-color statusline for [Claude Code](https://claude.ai/claude-code) using the [Catppuccin Mocha](https://github.com/catppuccin/catppuccin) palette. Designed for [Ghostty](https://ghostty.org/) with 24-bit color support.

## Features

- **Model + thinking mode** — shows current model name and reasoning effort
- **Session cost** — tracks total USD cost in real-time
- **Usage quota** — 5-hour and 7-day rate limit remaining, with countdown timers
- **Context window** — current usage % with color-coded warnings (green → orange → red)
- **Session duration** — human-readable elapsed time
- **Git branch** — auto-detected from workspace directory
- **Vim mode** — displays current vim mode when active
- **Agent name** — shows active subagent name
- **OSC 8 links** — clickable directory path in Ghostty

## Preview

```
/Users/you/project  │  main  │  4m 32s
Claude Sonnet 4.6   │  v1.x  │  $0.12  │  87% left 1h30m  │  95% left 2d3h
ctx 23% ⚠️  46.0K/200.0K
```

## Setup

1. Save `statusline.sh` to a location of your choice (e.g., `~/.claude/statusline.sh`)
2. Make it executable:
   ```sh
   chmod +x ~/.claude/statusline.sh
   ```
3. Configure Claude Code to use it in `~/.claude/settings.json`:
   ```json
   {
     "statusline": {
       "command": "/Users/you/.claude/statusline.sh"
     }
   }
   ```

## Requirements

- **macOS** — uses `security`, `date -r`, `date -jf` (BSD date)
- **jq** — for JSON parsing
- **curl** — for quota fetching
- **Ghostty** (recommended) — for 24-bit color and OSC 8 clickable links; works in any truecolor terminal

## How it works

Claude Code pipes a JSON blob to the statusline script on each update. The script extracts model info, token counts, cost, session duration, and quota data, then renders three lines of colorized output using ANSI true-color escape codes.

Quota data is fetched from `api.anthropic.com/api/oauth/usage` using the stored Claude Code OAuth token (via macOS Keychain), cached for 60 seconds with stale-while-revalidate background refresh.
