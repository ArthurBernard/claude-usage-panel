# Contributing

Thanks for your interest! This repo hosts a GNOME Shell extension (GJS) and a
native macOS SwiftUI app that share one data model.

## Setup

```bash
pipx install pre-commit
pre-commit install
```

`pre-commit` runs ESLint, `swift-format`, shellcheck, shfmt, markdownlint, and
gitleaks — the same set runs in CI on every push.

## Layout

See the [Architecture](https://github.com/fschmutz/claude-usage-panel/wiki/Architecture)
wiki page. Keep the GNOME (`lib/*.js`) and macOS (`Sources/**/*.swift`) data
layers in sync — they mirror the same API shape.

## Rules

- Keep changes read-only with respect to the user's credentials.
- Never commit secrets, keys, or real usage/billing figures (gitleaks enforces this).
- One concern per commit; conventional-commit messages.
- Add/adjust the matching platform when you change shared behavior.

## Testing GNOME changes

Wayland can't hot-reload an extension. Test in a nested shell:

```bash
dbus-run-session -- gnome-shell --headless --virtual-monitor 1280x800 --unsafe-mode --wayland
```
