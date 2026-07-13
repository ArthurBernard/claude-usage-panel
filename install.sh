#!/usr/bin/env bash
# Unified installer for Claude Usage Panel — one entrypoint for all three
# clients (GNOME extension, macOS menu-bar app, Claude Code status line).
#
#   ./install.sh                    auto-detect this OS and install the sensible set
#   ./install.sh gnome              GNOME Shell extension only
#   ./install.sh statusline         Claude Code status line only
#   ./install.sh macos              build the macOS .app bundle
#   ./install.sh gnome statusline   any combination
#   ./install.sh update [target...]        reinstall what's already installed (upgrade)
#   ./install.sh update --pull             git pull --ff-only first, then upgrade
#   ./install.sh --uninstall [target...]   reverse an install (default: all detected)
#   ./install.sh --dry-run [target...]     print the actions without doing them (alias -n)
#   ./install.sh --list             show detected + installed targets
#   ./install.sh -h | --help
#
# Each target guards its own dependencies and is skipped with a clear message
# rather than failing the whole run. Re-running any target is safe (idempotent).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
UUID="claude-usage-panel@fschmutz.github.io"

# ── Single source of truth for the version (used by the macOS bundle). ──────────
version() {
    sed -nE 's/.*"version": *"([^"]+)".*/\1/p' "$ROOT/package.json" | head -1
}

info() { printf '\033[1m%s\033[0m\n' "$*"; }
skip() { printf '  \033[33mskip\033[0m %s\n' "$*"; }
ok() { printf '  \033[32mok\033[0m   %s\n' "$*"; }

# --dry-run: print each mutating action instead of doing it. Read-only probes
# (command -v, gsettings get, uname) always run. `act` wraps a plain command;
# heredoc merges (node/python) are guarded inline with `$DRY`.
DRY=false
PULL=false
act() {
    if $DRY; then printf '  would: %s\n' "$*"; else "$@"; fi
}

# ── GNOME Shell extension ──────────────────────────────────────────────────────
install_gnome() {
    info "GNOME extension"
    if ! command -v glib-compile-schemas >/dev/null; then
        skip "gnome: glib-compile-schemas not found (not a GNOME desktop?)"
        return 0
    fi
    local src="$ROOT/$UUID"
    local dest="$HOME/.local/share/gnome-shell/extensions/$UUID"
    act rm -rf "$dest"
    act mkdir -p "$dest"
    act cp -r "$src/." "$dest/"
    act glib-compile-schemas "$dest/schemas/"

    # Compile translations (po/*.po → locale/<lang>/LC_MESSAGES/<domain>.mo).
    if command -v msgfmt >/dev/null && [ -d "$src/po" ]; then
        for po in "$src"/po/*.po; do
            [ -e "$po" ] || continue
            local lang mo_dir
            lang="$(basename "$po" .po)"
            mo_dir="$dest/locale/$lang/LC_MESSAGES"
            act mkdir -p "$mo_dir"
            act msgfmt "$po" -o "$mo_dir/claude-usage-panel.mo"
        done
    fi

    # A global kill switch disables ALL user extensions; clear it if set.
    if [ "$(gsettings get org.gnome.shell disable-user-extensions 2>/dev/null)" = "true" ]; then
        act gsettings set org.gnome.shell disable-user-extensions false
        ok "cleared global 'disable-user-extensions' switch"
    fi
    if $DRY; then
        echo "  would: enable $UUID (via gnome-extensions, or register for next login)"
    elif gnome-extensions enable "$UUID" 2>/dev/null; then
        ok "enabled via gnome-extensions"
    else
        _gnome_enabled_key add
        ok "registered in enabled-extensions for next login"
    fi
    if $DRY; then
        ok "dry-run: no changes written"
        return 0
    fi
    ok "installed to $dest"
    echo "  Log out and back in (Wayland loads new extensions only at login)."
}

uninstall_gnome() {
    info "GNOME extension"
    if command -v gnome-extensions >/dev/null; then
        act gnome-extensions disable "$UUID" 2>/dev/null || true
    fi
    _gnome_enabled_key remove 2>/dev/null || true
    act rm -rf "$HOME/.local/share/gnome-shell/extensions/$UUID"
    ok "removed"
}

# Add/remove the UUID from org.gnome.shell enabled-extensions. $1 = add|remove.
_gnome_enabled_key() {
    command -v gsettings >/dev/null || return 0
    if $DRY; then
        echo "  would: $1 $UUID in org.gnome.shell enabled-extensions"
        return 0
    fi
    python3 - "$1" "$UUID" <<'PY'
import subprocess, sys, ast
action, uuid = sys.argv[1], sys.argv[2]
key = ["org.gnome.shell", "enabled-extensions"]
cur = subprocess.run(["gsettings", "get", *key], capture_output=True, text=True).stdout.strip()
try:
    items = ast.literal_eval(cur) if cur and cur != "@as []" else []
except (ValueError, SyntaxError):
    items = []
if action == "add" and uuid not in items:
    items.append(uuid)
elif action == "remove" and uuid in items:
    items.remove(uuid)
else:
    sys.exit(0)
subprocess.run(["gsettings", "set", *key,
                "[" + ", ".join("'%s'" % i for i in items) + "]"], check=True)
PY
}

# ── Claude Code status line ─────────────────────────────────────────────────────
install_statusline() {
    info "Claude Code status line"
    if ! command -v node >/dev/null; then
        skip "statusline: Node.js not found on PATH"
        return 0
    fi
    local src="$ROOT/claude-code/statusline.js"
    local dest_dir="$HOME/.claude"
    # .mjs so Node always treats it as ESM regardless of any nearby package.json.
    local dest="$dest_dir/claude-usage-statusline.mjs"
    act mkdir -p "$dest_dir"
    act cp "$src" "$dest"
    act chmod +x "$dest"

    if $DRY; then
        echo "  would: merge statusLine → node \"$dest\" into $dest_dir/settings.json"
        ok "dry-run: no changes written"
        return 0
    fi
    # Merge the statusLine key with Node so an existing settings.json is never
    # corrupted; all other keys are preserved.
    COMMAND="node \"$dest\"" node - "$dest_dir/settings.json" <<'JS'
const fs = require('fs');
const path = process.argv[2];
let settings = {};
try { settings = JSON.parse(fs.readFileSync(path, 'utf8')); } catch { /* fresh */ }
const existing = settings.statusLine;
settings.statusLine = {type: 'command', command: process.env.COMMAND};
fs.writeFileSync(path, JSON.stringify(settings, null, 2) + '\n');
if (existing && existing.command !== settings.statusLine.command)
  console.log('  replaced an existing statusLine command: ' + (existing.command || JSON.stringify(existing)));
JS
    ok "installed to $dest and merged statusLine into $dest_dir/settings.json"
    echo "  Open a Claude Code session or run /statusline to see it."
}

uninstall_statusline() {
    info "Claude Code status line"
    local dest_dir="$HOME/.claude"
    act rm -f "$dest_dir/claude-usage-statusline.mjs"
    if $DRY; then
        echo "  would: drop our statusLine entry from $dest_dir/settings.json (foreign ones kept)"
        ok "dry-run: no changes written"
        return 0
    fi
    # Remove only OUR statusLine entry (leave a foreign one untouched).
    if command -v node >/dev/null && [ -f "$dest_dir/settings.json" ]; then
        node - "$dest_dir/settings.json" <<'JS'
const fs = require('fs');
const path = process.argv[2];
let s; try { s = JSON.parse(fs.readFileSync(path, 'utf8')); } catch { process.exit(0); }
if (s.statusLine && /claude-usage-statusline\.mjs/.test(s.statusLine.command || '')) {
  delete s.statusLine;
  fs.writeFileSync(path, JSON.stringify(s, null, 2) + '\n');
}
JS
    fi
    ok "removed"
}

# ── macOS .app bundle ───────────────────────────────────────────────────────────
install_macos() {
    info "macOS app"
    if [ "$(uname -s)" != "Darwin" ]; then
        skip "macos: only builds on macOS (uname is $(uname -s))"
        return 0
    fi
    if ! command -v swift >/dev/null; then
        skip "macos: Swift toolchain not found"
        return 0
    fi
    local app="ClaudeUsagePanel"
    local bundle="$ROOT/macos/$app.app"
    local ver
    ver="$(version)"
    if $DRY; then
        echo "  would: swift build -c release + assemble $bundle (v$ver)"
        echo "  would: quit a running instance, ad-hoc codesign, cp -R to /Applications/$app.app, open it"
        ok "dry-run: no build performed"
        return 0
    fi
    (
        cd "$ROOT/macos"
        swift build -c release
        local bin
        bin="$(swift build -c release --show-bin-path)/$app"
        rm -rf "$bundle"
        mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
        cp "$bin" "$bundle/Contents/MacOS/$app"
        cat >"$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Claude Usage Panel</string>
  <key>CFBundleDisplayName</key><string>Claude Usage Panel</string>
  <key>CFBundleIdentifier</key><string>io.github.fschmutz.claude-usage-panel</string>
  <key>CFBundleVersion</key><string>$ver</string>
  <key>CFBundleShortVersionString</key><string>$ver</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$app</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
    )
    # Ad-hoc sign so "Start at login" (SMAppService) and Gatekeeper accept the
    # bundle for personal use; a Developer ID is only needed to distribute it
    # (see PUBLISHING.md). The signature is preserved by the copy below.
    codesign --deep --force --sign - "$bundle" >/dev/null 2>&1 || true
    ok "built $bundle (v$ver)"

    # Make it perpetual: install into /Applications and launch it. On first run
    # the app registers itself as a login item (toggle in Settings ▸ Start at login).
    # Quit any running instance first so we replace (not copy over) a busy bundle
    # and so `open` relaunches the NEW binary — this is what makes upgrades take.
    osascript -e 'quit app "Claude Usage Panel"' >/dev/null 2>&1 || true
    local installed="/Applications/$app.app"
    if rm -rf "$installed" 2>/dev/null && cp -R "$bundle" "$installed" 2>/dev/null; then
        open "$installed" 2>/dev/null || true
        ok "installed to $installed and launched"
        echo "  Starts at login by default — toggle it in Settings ▸ Start at login."
    else
        echo "  Could not write /Applications (needs admin). Install it yourself:"
        echo "    sudo cp -R '$bundle' '$installed' && open '$installed'"
    fi
}

uninstall_macos() {
    info "macOS app"
    act rm -rf "$ROOT/macos/ClaudeUsagePanel.app"
    act rm -rf "/Applications/ClaudeUsagePanel.app"
    ok "removed built + installed bundles (source untouched)"
    echo "  If it was set to start at login, remove it in System Settings ▸ General ▸ Login Items."
}

# ── Target resolution ───────────────────────────────────────────────────────────
ALL_TARGETS="gnome statusline macos"

# Print the targets that make sense for this machine, one per line.
detect_targets() {
    case "$(uname -s)" in
        Darwin) echo macos ;;
        Linux)
            if command -v gnome-extensions >/dev/null ||
                [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]]; then
                echo gnome
            fi
            ;;
    esac
    command -v node >/dev/null && echo statusline
}

# Print the targets currently installed on this machine, one per line. Drives
# `update` (reinstall only what's actually there) and `--list`.
installed_targets() {
    [ -d "$HOME/.local/share/gnome-shell/extensions/$UUID" ] && echo gnome
    [ -f "$HOME/.claude/claude-usage-statusline.mjs" ] && echo statusline
    [ -d "/Applications/ClaudeUsagePanel.app" ] && echo macos
    return 0
}

is_target() {
    local t
    for t in $ALL_TARGETS; do [ "$t" = "$1" ] && return 0; done
    return 1
}

usage() {
    # Print the leading comment block (after the shebang) as help text.
    awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
}

# ── Main ────────────────────────────────────────────────────────────────────────
action=install
targets=()
for arg in "$@"; do
    case "$arg" in
        -h | --help)
            usage
            exit 0
            ;;
        update) action=update ;;
        --uninstall) action=uninstall ;;
        --pull) PULL=true ;;
        --dry-run | -n) DRY=true ;;
        --list) action=list ;;
        -*)
            echo "Unknown option: $arg" >&2
            usage >&2
            exit 2
            ;;
        *)
            if is_target "$arg"; then
                targets+=("$arg")
            else
                echo "Unknown target: $arg (want: $ALL_TARGETS)" >&2
                exit 2
            fi
            ;;
    esac
done

if [ "$action" = list ]; then
    detected="$(detect_targets | paste -sd' ' -)"
    installed="$(installed_targets | paste -sd' ' -)"
    info "Claude Usage Panel — targets (version $(version))"
    echo "  all:        $ALL_TARGETS"
    echo "  detected:   ${detected:-<none>}   (bare ./install.sh installs these)"
    echo "  installed:  ${installed:-<none>}   (./install.sh update reinstalls these)"
    exit 0
fi

# --pull: refresh the checkout before (re)installing, so `update` is one command.
if $PULL; then
    if $DRY; then
        echo "would: git -C \"$ROOT\" pull --ff-only"
        echo
    else
        info "Pulling latest…"
        git -C "$ROOT" pull --ff-only
        echo
    fi
fi

# Default target set: `update` reinstalls what's already installed; install and
# uninstall fall back to what fits this OS.
if [ ${#targets[@]} -eq 0 ]; then
    if [ "$action" = update ]; then
        mapfile -t targets < <(installed_targets)
    else
        mapfile -t targets < <(detect_targets)
    fi
fi

if [ ${#targets[@]} -eq 0 ]; then
    if [ "$action" = update ]; then
        echo "Nothing installed to update. Install first: ./install.sh [target...]" >&2
    else
        echo "No installable target detected. Name one explicitly: $ALL_TARGETS" >&2
    fi
    exit 1
fi

info "==> ${action}: ${targets[*]}$($DRY && echo '  (dry-run)')"
echo
for t in "${targets[@]}"; do
    # `update` is a reinstall in place (install_macos also quits + relaunches).
    if [ "$action" = update ]; then install_"$t"; else "${action}_${t}"; fi
    echo
done
info "Done. Requires an active Claude Code login (~/.claude/.credentials.json)."
