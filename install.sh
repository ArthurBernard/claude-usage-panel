#!/usr/bin/env bash
# Unified installer for Claude Usage Panel — one entrypoint for all three
# clients (GNOME extension, macOS menu-bar app, Claude Code status line).
#
#   ./install.sh                    auto-detect this OS and install the sensible set
#   ./install.sh gnome              GNOME Shell extension only
#   ./install.sh statusline         Claude Code status line only
#   ./install.sh macos              build the macOS .app bundle
#   ./install.sh gnome statusline   any combination
#   ./install.sh --uninstall [target...]   reverse an install (default: all detected)
#   ./install.sh --dry-run [target...]     print the actions without doing them (alias -n)
#   ./install.sh --list             show what each target would do / detects
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
    ok "built $bundle (v$ver)"
    echo "  Run it:  open '$bundle'"
    echo "  Sign it: codesign --deep --force --sign - '$bundle'   # ad-hoc; see PUBLISHING.md"
}

uninstall_macos() {
    info "macOS app"
    act rm -rf "$ROOT/macos/ClaudeUsagePanel.app"
    ok "removed built bundle (source untouched)"
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
        --uninstall) action=uninstall ;;
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

if [ ${#targets[@]} -eq 0 ]; then
    mapfile -t targets < <(detect_targets)
fi

if [ "$action" = list ]; then
    info "Detected on this machine ($(uname -s)):"
    printf '  %s\n' "${targets[@]:-<none>}"
    echo "All targets: $ALL_TARGETS   Version: $(version)"
    exit 0
fi

if [ ${#targets[@]} -eq 0 ]; then
    echo "No installable target detected. Name one explicitly: $ALL_TARGETS" >&2
    exit 1
fi

info "==> ${action}: ${targets[*]}$($DRY && echo '  (dry-run)')"
echo
for t in "${targets[@]}"; do
    "${action}_${t}"
    echo
done
info "Done. Requires an active Claude Code login (~/.claude/.credentials.json)."
