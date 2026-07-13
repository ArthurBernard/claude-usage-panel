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
# Interactive configuration for the status line: a segment checklist and a
# token-total radio, both with a live preview. Colors only on a real terminal.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    SL_B=$'\033[1m'
    SL_D=$'\033[2m'
    SL_RS=$'\033[0m'
    SL_CY=$'\033[36m'
    SL_GN=$'\033[32m'
else
    SL_B=''
    SL_D=''
    SL_RS=''
    SL_CY=''
    SL_GN=''
fi
SL_SEG_KEYS="context limits tokens"
SL_PREVIEW_STDIN=""
SL_PREVIEW_TRANSCRIPT=""

# Read one keypress into SL_KEY. Arrows arrive as ESC [ A; Enter reads as "" and
# end-of-input as "EOF".
sl_read_key() {
    SL_KEY=""
    IFS= read -rsn1 SL_KEY 2>/dev/null || {
        SL_KEY="EOF"
        return 0
    }
    if [ "$SL_KEY" = $'\033' ]; then
        local rest=""
        IFS= read -rsn2 -t 1 rest 2>/dev/null || rest=""
        SL_KEY="$SL_KEY$rest"
    fi
    return 0
}
sl_cursor_hide() { if [ -t 1 ]; then printf '\033[?25l'; fi; }
sl_cursor_show() { if [ -t 1 ]; then printf '\033[?25h'; fi; }
sl_seg_desc() {
    case "$1" in
        context) printf 'context-window usage of this session' ;;
        limits) printf 'Session (5 h) and Week (7 d) plan limits' ;;
        tokens) printf '∑ total tokens this window has consumed' ;;
    esac
}

# Render the real status line from representative sample data so previews match
# what Claude Code will show. The temp transcript is global so a trap can clean
# it up.
sl_setup_preview() {
    local now
    now="$(date +%s)"
    SL_PREVIEW_TRANSCRIPT="$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/clt-preview.$$")"
    {
        printf '%s\n' '{"type":"assistant","message":{"id":"1","usage":{"input_tokens":5200,"output_tokens":840,"cache_creation_input_tokens":3100,"cache_read_input_tokens":260000}}}'
        printf '%s\n' '{"type":"assistant","message":{"id":"2","usage":{"input_tokens":6100,"output_tokens":1200,"cache_creation_input_tokens":0,"cache_read_input_tokens":290000}}}'
        printf '%s\n' '{"type":"assistant","message":{"id":"3","usage":{"input_tokens":4300,"output_tokens":560,"cache_creation_input_tokens":1500,"cache_read_input_tokens":310000}}}'
    } >"$SL_PREVIEW_TRANSCRIPT"
    SL_PREVIEW_STDIN="$(printf '{"context_window":{"used_percentage":8},"rate_limits":{"five_hour":{"used_percentage":26,"resets_at":%s},"seven_day":{"used_percentage":24,"resets_at":%s}},"transcript_path":"%s"}' "$((now + 3540))" "$((now + 353000))" "$SL_PREVIEW_TRANSCRIPT")"
}
sl_preview() { # $1=dest  $2=segments  $3=tokens
    local flags=(--segments="$2")
    [ -n "$3" ] && flags+=(--tokens="$3")
    printf '%s' "$SL_PREVIEW_STDIN" | node "$1" "${flags[@]}" 2>/dev/null || true
}

# Segment checklist. ↑/↓ move, space toggles, < > reorder, Enter confirms.
# Reads/updates SL_SEGMENTS; $1 is the installed .mjs used for previews.
sl_select_segments() {
    local dest="$1" order=() enabled=() i k found j seg_list=()
    for i in $SL_SEG_KEYS; do enabled+=("$i:0"); done
    local OLDIFS="$IFS"
    IFS=','
    read -ra seg_list <<<"$SL_SEGMENTS"
    IFS="$OLDIFS"
    for k in "${seg_list[@]}"; do
        [ -n "$k" ] || continue
        for i in $SL_SEG_KEYS; do
            if [ "$i" = "$k" ]; then
                order+=("$i")
                enabled=("${enabled[@]/$i:0/$i:1}")
            fi
        done
    done
    for i in $SL_SEG_KEYS; do
        found=0
        for j in "${order[@]:-}"; do [ "$j" = "$i" ] && found=1; done
        [ "$found" = 0 ] && order+=("$i")
    done
    local cur=0 count=${#order[@]} rows=$((${#order[@]} + 2))
    sl_is_on() { case " ${enabled[*]} " in *" $1:1 "*) return 0 ;; *) return 1 ;; esac }
    sl_cur_segs() {
        local n s=""
        for n in "${order[@]}"; do sl_is_on "$n" && s="${s:+$s,}$n"; done
        printf '%s' "$s"
    }
    sl_draw_segs() {
        local n name box ptr
        for n in "${order[@]}"; do
            if sl_is_on "$n"; then box="${SL_GN}◉${SL_RS}"; else box="${SL_D}◯${SL_RS}"; fi
            if [ "$n" = "${order[cur]}" ]; then
                ptr="${SL_CY}❯${SL_RS}"
                name="${SL_B}$(printf '%-7s' "$n")${SL_RS}"
            else
                ptr=' '
                name="$(printf '%-7s' "$n")"
            fi
            printf '  %s %s %s %s%s%s\033[K\n' "$ptr" "$box" "$name" "$SL_D" "$(sl_seg_desc "$n")" "$SL_RS"
        done
        printf '  %s↑/↓ move · space toggle · < > reorder · enter confirm%s\033[K\n' "$SL_D" "$SL_RS"
        printf '  %spreview%s  %s\033[K\n' "$SL_D" "$SL_RS" "$(sl_preview "$dest" "$(sl_cur_segs)" "$SL_TOKENS")"
    }
    sl_cursor_hide
    sl_draw_segs
    while :; do
        sl_read_key
        case "$SL_KEY" in
            $'\033[A') if [ "$cur" -gt 0 ]; then cur=$((cur - 1)); fi ;;
            $'\033[B') if [ "$cur" -lt $((count - 1)) ]; then cur=$((cur + 1)); fi ;;
            ' ')
                k="${order[cur]}"
                if sl_is_on "$k"; then enabled=("${enabled[@]/$k:1/$k:0}"); else enabled=("${enabled[@]/$k:0/$k:1}"); fi
                ;;
            '<') if [ "$cur" -gt 0 ]; then
                k="${order[cur]}"
                order[cur]="${order[cur - 1]}"
                order[cur - 1]="$k"
                cur=$((cur - 1))
            fi ;;
            '>') if [ "$cur" -lt $((count - 1)) ]; then
                k="${order[cur]}"
                order[cur]="${order[cur + 1]}"
                order[cur + 1]="$k"
                cur=$((cur + 1))
            fi ;;
            '') if [ -n "$(sl_cur_segs)" ]; then break; fi ;;
            EOF) break ;;
        esac
        printf '\033[%dA' "$rows"
        sl_draw_segs
    done
    sl_cursor_show
    SL_SEGMENTS="$(sl_cur_segs)"
    [ -n "$SL_SEGMENTS" ] || SL_SEGMENTS="context,limits,tokens"
}

# Token-total radio (all / fresh), each with its live figure. ↑/↓ + Enter.
sl_select_tokens() {
    local dest="$1" cur=0 rows=3 pa pf
    [ "$SL_TOKENS" = fresh ] && cur=1
    pa="$(sl_preview "$dest" tokens all)"
    pf="$(sl_preview "$dest" tokens fresh)"
    sl_draw_tok() {
        local p0 b0 p1 b1
        if [ "$cur" = 0 ]; then
            p0="${SL_CY}❯${SL_RS}"
            b0="${SL_GN}◉${SL_RS}"
        else
            p0=' '
            b0="${SL_D}◯${SL_RS}"
        fi
        if [ "$cur" = 1 ]; then
            p1="${SL_CY}❯${SL_RS}"
            b1="${SL_GN}◉${SL_RS}"
        else
            p1=' '
            b1="${SL_D}◯${SL_RS}"
        fi
        printf '  %s %s %sall  %s %sincl. cache reads · true throughput%s  %s\033[K\n' "$p0" "$b0" "$SL_B" "$SL_RS" "$SL_D" "$SL_RS" "$pa"
        printf '  %s %s %sfresh%s %sexcl. cache reads · new tokens only%s  %s\033[K\n' "$p1" "$b1" "$SL_B" "$SL_RS" "$SL_D" "$SL_RS" "$pf"
        printf '  %s↑/↓ choose · enter confirm%s\033[K\n' "$SL_D" "$SL_RS"
    }
    sl_cursor_hide
    sl_draw_tok
    while :; do
        sl_read_key
        case "$SL_KEY" in
            $'\033[A') if [ "$cur" -gt 0 ]; then cur=$((cur - 1)); fi ;;
            $'\033[B') if [ "$cur" -lt 1 ]; then cur=$((cur + 1)); fi ;;
            '' | EOF) break ;;
        esac
        printf '\033[%dA' "$rows"
        sl_draw_tok
    done
    sl_cursor_show
    if [ "$cur" = 1 ]; then SL_TOKENS=fresh; else SL_TOKENS=all; fi
}

# Drive the two menus; $1 is the installed .mjs. Sets SL_SEGMENTS / SL_TOKENS.
_statusline_configure() {
    SL_SEGMENTS="context,limits,tokens"
    SL_TOKENS="all"
    sl_setup_preview
    trap 'rm -f "$SL_PREVIEW_TRANSCRIPT"; sl_cursor_show' EXIT
    printf '  %sSegments%s %s— top-to-bottom is left-to-right on the line%s\n' "$SL_B" "$SL_RS" "$SL_D" "$SL_RS"
    sl_select_segments "$1"
    case ",$SL_SEGMENTS," in
        *,tokens,*)
            printf '  %sToken counter total%s\n' "$SL_B" "$SL_RS"
            sl_select_tokens "$1"
            ;;
    esac
    rm -f "$SL_PREVIEW_TRANSCRIPT"
    trap - EXIT
}

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

    # Configure segments + token total interactively (a real terminal only);
    # scripted / piped / dry-run installs take the defaults.
    local segments="context,limits,tokens" tokens_mode="all"
    if ! $DRY && [ -t 0 ] && [ -t 1 ]; then
        _statusline_configure "$dest"
        segments="$SL_SEGMENTS"
        tokens_mode="$SL_TOKENS"
    fi
    local command="node \"$dest\" --segments=$segments --tokens=$tokens_mode"

    if $DRY; then
        echo "  would: merge statusLine → $command into $dest_dir/settings.json"
        ok "dry-run: no changes written"
        return 0
    fi
    # Merge the statusLine key with Node so an existing settings.json is never
    # corrupted; all other keys are preserved.
    COMMAND="$command" node - "$dest_dir/settings.json" <<'JS'
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
