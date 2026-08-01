# Installation

One line - it fetches the repo into `~/.local/share/claude-usage-panel` and
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
| `./install.sh autoupdate` | daily check for a new release + auto-install |
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
login. Then **log out and back in** - Wayland only loads new extensions at login.

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

## MCP tool - no clone needed

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

## Staying up to date

### Automatically (on by default)

Installing from a git checkout also schedules a **daily update check** - the
`autoupdate` target. Once a day it reads the highest released `vX.Y.Z` tag on
`origin`; if that's newer than your `package.json` version it fast-forwards the
checkout and runs `install.sh update`, so every client you have moves to the new
release without you doing anything. A desktop notification says when it lands.

| | |
|---|---|
| Linux | systemd user timer `claude-usage-panel-update.timer` (`OnCalendar=daily`, `Persistent=true`, so a missed day runs at next login) |
| macOS | launchd agent `io.github.fschmutz.claude-usage-panel.update`, daily at 11:17 |
| Neither | a `cron` line tagged `# claude-usage-panel auto-update` |

```bash
scripts/auto-update.sh --status     # installed vs latest, and when it last looked
scripts/auto-update.sh --check      # look now, install nothing (exit 10 = update waiting)
scripts/auto-update.sh              # look now, and install it if there is one
./install.sh --uninstall autoupdate # turn the daily check off
```

It is deliberately timid about your checkout: it **only ever fast-forwards**
(no merge, rebase, reset or stash), and it skips - logging the reason, changing
nothing - when the worktree is dirty, the branch is diverged or detached, there
is no `origin`, or the network is down. It also reinstalls **only** the targets
already installed, so it never adds a client you didn't want. The rolling log
is `~/.local/state/claude-usage-panel/auto-update.log`.

### By hand

```bash
./install.sh update --pull      # git pull, then reinstall whatever you have
```

`update` reinstalls only the targets already present (see `./install.sh --list`),
so it won't add clients you never installed. `--pull` fast-forwards the checkout
first. Per target: the **status line** and **MCP server** take effect next
session; **GNOME** needs a log out / back in (Wayland); **macOS** quits the
running app, replaces it in `/Applications`, and relaunches the new build.
