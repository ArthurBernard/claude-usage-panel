# MCP Tool — ask Claude or Cursor for your usage

One MCP tool, **`get_usage`**, lets any MCP client answer *"how much of my plan
have I used?"* in-conversation with live numbers: session, weekly, and
per-model limits (Fable, Opus…) with percent, severity, and reset countdown —
the same data as the desktop panels, from the official Anthropic usage
endpoint.

Each limit carries `group` (`session` / `weekly`) and `scoped`. A scoped limit
(Fable) is a **sub-cap of its group's pool** — that usage also counts toward
`weekly_all` and shares its reset — so the rendered line says "share of the
weekly all-models limit" instead of implying extra quota.

Zero dependencies, stdio transport, read-only: it reads the OAuth token Claude
Code already stores locally (`~/.claude/.credentials.json` on Linux, the login
Keychain on macOS) and never writes it.

## Install

All paths register the exact same server — pick one:

```bash
# 1. The unified installer (registers Claude Code + Cursor in one go)
./install.sh mcp

# 2. Claude Code plugin (inside a session, no clone)
/plugin marketplace add fschmutz/claude-usage-panel
/plugin install claude-usage@claude-usage-panel

# 3. Claude Code CLI, straight from GitHub (no clone)
claude mcp add claude-usage -- npx -y github:fschmutz/claude-usage-panel

# 4. Cursor: click "Add to Cursor" on https://fschmutz.github.io/claude-usage-panel/
```

`./install.sh --uninstall mcp` reverses option 1 (deregisters both apps,
leaves other MCP servers untouched).

## What it returns

One entry per active limit, as text plus structured content:

```json
{"limits": [
  {"key": "session", "label": "Current session", "percent": 26,
   "severity": "normal", "resetsAt": "2026-07-19T16:00:00Z", "active": true}
]}
```

Errors (no token, expired session, network) come back as tool errors with a
one-line fix hint — e.g. *"Claude session expired. Run any Claude Code command
to refresh it."*

## Details

See [mcp/README.md](https://github.com/fschmutz/claude-usage-panel/blob/main/mcp/README.md).
The server is the fourth port of the shared normalization contract — see
[[Architecture]].
