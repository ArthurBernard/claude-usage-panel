# Claude Usage Panel — Wiki

See your **Claude Code** plan usage everywhere: the GNOME top bar, the macOS menu
bar, a status line under the Claude Code prompt, or by just asking Claude / Cursor
(MCP). Optional **Cursor** team spend.

- 🌐 **Landing site + one-click installs:** <https://fschmutz.github.io/claude-usage-panel/>
- 💾 **Releases:** <https://github.com/fschmutz/claude-usage-panel/releases>

One-line install (auto-detects your platform):

```bash
curl -fsSL https://fschmutz.github.io/claude-usage-panel/install | bash
```

## Pages

- [[Installation]] — every client: GNOME, macOS, status line, MCP
- [[Settings]] — all preferences
- [[Cursor Integration]] — optional team-spend section
- [[macOS]] — the SwiftUI menu-bar app
- [[Status Line]] — condensed usage under the Claude Code prompt
- [[MCP Tool]] — ask Claude or Cursor for your usage in-conversation
- [[Troubleshooting]] — common issues and fixes
- [[Architecture]] — how the code is laid out
- [[FAQ]]

## What it shows

Session, weekly (all models), and **per-model** weekly limits (Fable, Opus…) from the official
`api.anthropic.com/api/oauth/usage` endpoint — with severity colors, reset timers, limit-crossing
alerts, a usage sparkline, and an optional session cost.
