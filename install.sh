#!/usr/bin/env bash
# Install Claude Usage Panel into the user's GNOME Shell extensions directory
# and enable it so it auto-starts on every login.
set -euo pipefail

UUID="claude-usage-panel@fschmutz.github.io"
SRC="$(cd "$(dirname "$0")" && pwd)/$UUID"
DEST="$HOME/.local/share/gnome-shell/extensions/$UUID"

if [ ! -d "$SRC" ]; then
    echo "Source directory not found: $SRC" >&2
    exit 1
fi

echo "Installing to $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -r "$SRC/." "$DEST/"

# Compile the GSettings schema in place.
glib-compile-schemas "$DEST/schemas/"

# Enable so it auto-starts on every login. Try the CLI first (works when the
# shell already knows the extension); otherwise write the enabled-extensions
# dconf key directly so it loads on the next login regardless.
enable_extension() {
    if gnome-extensions enable "$UUID" 2>/dev/null; then
        echo "Enabled via gnome-extensions."
        return
    fi
    echo "Shell not aware yet — registering in enabled-extensions for next login."
    python3 - "$UUID" <<'PY'
import subprocess, sys, ast
uuid = sys.argv[1]
key = ["org.gnome.shell", "enabled-extensions"]
cur = subprocess.run(["gsettings", "get", *key], capture_output=True, text=True).stdout.strip()
try:
    items = ast.literal_eval(cur) if cur and cur != "@as []" else []
except (ValueError, SyntaxError):
    items = []
if uuid not in items:
    items.append(uuid)
    subprocess.run(["gsettings", "set", *key,
                    "[" + ", ".join("'%s'" % i for i in items) + "]"], check=True)
    print("Added to enabled-extensions.")
else:
    print("Already in enabled-extensions.")
PY
}
enable_extension

echo
echo "Installed and enabled. It will start automatically on every login."
echo "If it is not visible yet, log out and back in (Wayland loads new"
echo "extensions only at login), then confirm with:"
echo "  gnome-extensions info $UUID"
echo
echo "Requires an active Claude Code login (~/.claude/.credentials.json)."
