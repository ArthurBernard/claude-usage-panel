# Settings

## GNOME

Open via the dropdown's **Settings**, or:

```bash
gnome-extensions prefs claude-usage-panel@fschmutz.github.io
```

## macOS

Quick toggles (Cost, Alerts, Refresh) live in the dropdown; a full **Settings** window
(⌘, or the dropdown's **Settings…**) holds every option including Cursor.

## Options

| Option | What it does |
|---|---|
| **Refresh interval** | Minutes between polls (default 10). |
| **Top bar shows** (GNOME) | Worst limit, or the current session. |
| **Limit-crossing alerts** | Notify when a limit reaches 90% / 100%. |
| **Show session cost** | Compute session cost locally via `ccusage`. |
| **Show Cursor usage** | Add the Cursor team-spend section (see [[Cursor Integration]]). |

Preferences persist in dconf (GNOME) / `UserDefaults` (macOS).
