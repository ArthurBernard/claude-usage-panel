# Troubleshooting

## The panel doesn't appear (GNOME)

- New extensions load only at login on Wayland. **Log out and back in.**
- Check the global kill switch:

  ```bash
  gsettings get org.gnome.shell disable-user-extensions   # must be false
  gnome-extensions enable claude-usage-panel@fschmutz.github.io
  ```

- Confirm state: `gnome-extensions info claude-usage-panel@fschmutz.github.io` → `State: ACTIVE`.

## "No Claude credentials found"

- **Linux:** sign in with Claude Code (creates `~/.claude/.credentials.json`).
- **macOS:** the token is in the Keychain — allow Keychain access on first launch.
- If the token expired, run any Claude Code command to refresh it.

## Cost shows "unavailable"

Install Node/`npx` (or a global `ccusage`). Cost is computed by `ccusage`, not the API.

## Cursor section errors

Re-check the Admin API key and that your account is a **team admin** (the Admin API is team-only).

## Clicking Refresh closed the popup

Fixed in v1.2.1 — update and relog.

## Logs (GNOME)

```bash
journalctl --user -b 0 | grep claude-usage-panel
```
