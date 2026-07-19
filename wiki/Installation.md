# Installation

One line — it fetches the repo into `~/.local/share/claude-usage-panel` and
auto-detects your OS to install the sensible set:

```bash
curl -fsSL https://fschmutz.github.io/claude-usage-panel/install | bash
```

Pass targets and flags through with `bash -s -- …`:

```bash
curl -fsSL https://fschmutz.github.io/claude-usage-panel/install | bash -s -- statusline mcp
```

Or from a clone: one `install.sh` at the repo root installs, updates, and
uninstalls every client.

| Command | Does |
|---|---|
| `./install.sh` | auto-detect OS → the sensible set |
| `./install.sh gnome` | GNOME Shell extension |
| `./install.sh statusline` | Claude Code status line |
| `./install.sh mcp` | `get_usage` MCP tool → Claude Code + Cursor |
| `./install.sh macos` | build + install the macOS `.app` |
| `./install.sh update [target…]` | reinstall what's already installed (upgrade) |
| `./install.sh update --pull` | `git pull` first, then upgrade |
| `./install.sh --uninstall [target…]` | reverse an install |
| `./install.sh --dry-run [target…]` | print the actions without doing them |
| `./install.sh --list` | show detected + installed targets |

Each target guards its own dependencies and is skipped with a clear message if
they're missing, rather than failing the whole run. Re-running is safe.

## GNOME (Linux)

Requirements: GNOME Shell 45–50, an active Claude Code login.

The `gnome` target copies the extension, compiles its GSettings schema, clears the
global `disable-user-extensions` switch if set, and enables the extension for every
login. Then **log out and back in** — Wayland only loads new extensions at login.

```bash
gnome-extensions info claude-usage-panel@fschmutz.github.io   # State: ACTIVE
```

### From a packaged release

Download the `…shell-extension.zip` asset (not "Source code") from the
[latest release](https://github.com/fschmutz/claude-usage-panel/releases/latest):

```bash
gnome-extensions install --force claude-usage-panel@fschmutz.github.io.shell-extension.zip
```

## macOS

Requirements: macOS 13+, Xcode 15+ or the Swift toolchain.

```bash
./install.sh macos       # build, install to /Applications, and launch it
```

This builds `ClaudeUsagePanel.app`, ad-hoc signs it, copies it to `/Applications`,
and opens it. On first run it **registers itself to start at login** (toggle in
Settings ▸ Start at login). Just want to run it without installing?
`cd macos && swift run`. See [[macOS]] for login-item and Keychain details.

## MCP tool — no clone needed

The `get_usage` tool also installs without touching the repo:

```bash
# Claude Code plugin (inside a session)
/plugin marketplace add fschmutz/claude-usage-panel
/plugin install claude-usage@claude-usage-panel

# or one CLI line
claude mcp add claude-usage -- npx -y github:fschmutz/claude-usage-panel

# Cursor: click "Add to Cursor" on the landing page
```

See [[MCP Tool]].

## Updating

To upgrade an existing install to the latest code:

```bash
./install.sh update --pull      # git pull, then reinstall whatever you have
```

`update` reinstalls only the targets already present (see `./install.sh --list`),
so it won't add clients you never installed. `--pull` fast-forwards the checkout
first. Per target: the **status line** and **MCP server** take effect next
session; **GNOME** needs a log out / back in (Wayland); **macOS** quits the
running app, replaces it in `/Applications`, and relaunches the new build.
