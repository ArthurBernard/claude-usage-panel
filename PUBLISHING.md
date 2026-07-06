# Publishing / distribution

## GNOME — extensions.gnome.org (EGO)

A packaged zip is attached to each GitHub release
(`claude-usage-panel@fschmutz.github.io.shell-extension.zip`), or rebuild it:

```bash
cd claude-usage-panel@fschmutz.github.io
gnome-extensions pack . \
  --extra-source=lib --extra-source=icons \
  --schema=schemas/org.gnome.shell.extensions.claude-usage-panel.gschema.xml \
  --force -o ..
```

Submit:

1. Sign in at <https://extensions.gnome.org/upload/> (Google/GitHub).
2. Upload the `.shell-extension.zip`.
3. Wait for reviewer approval (manual, usually a few days). Once approved it's
   installable via the GNOME Extensions app / <https://extensions.gnome.org>.

Notes for the reviewer: the extension reads `~/.claude/.credentials.json`
(read-only) and makes one HTTPS request per refresh to `api.anthropic.com`; the
optional Cursor section calls `api.cursor.com` only when enabled with a key.

## macOS — .app bundle

```bash
cd macos
./build-app.sh          # produces ClaudeUsagePanel.app
open ClaudeUsagePanel.app
```

The bundle is a menu-bar agent (`LSUIElement`), no Dock icon.

### Signing & notarization (for distribution)

Local/personal use needs only an ad-hoc signature:

```bash
codesign --deep --force --sign - ClaudeUsagePanel.app
```

To distribute to others without Gatekeeper warnings you need an Apple Developer
account:

```bash
# 1. Sign with your Developer ID
codesign --deep --force --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" ClaudeUsagePanel.app

# 2. Zip and notarize
ditto -c -k --keepParent ClaudeUsagePanel.app ClaudeUsagePanel.zip
xcrun notarytool submit ClaudeUsagePanel.zip \
  --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PW --wait

# 3. Staple the ticket
xcrun stapler staple ClaudeUsagePanel.app
```

## macOS — Homebrew cask (optional)

Once a signed `.app` (or zip) is attached to a GitHub release, a cask can install
it. Template — put it in a tap (`homebrew-tap/Casks/claude-usage-panel.rb`) and
fill in the release URL + sha256:

```ruby
cask "claude-usage-panel" do
  version "1.2.0"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/fschmutz/claude-usage-panel/releases/download/v#{version}/ClaudeUsagePanel.zip"
  name "Claude Usage Panel"
  desc "Menu-bar panel for Claude Code plan usage"
  homepage "https://github.com/fschmutz/claude-usage-panel"

  app "ClaudeUsagePanel.app"

  zap trash: [
    "~/Library/Preferences/io.github.fschmutz.claude-usage-panel.plist",
  ]
end
```

Install: `brew install --cask <yourtap>/claude-usage-panel`.
