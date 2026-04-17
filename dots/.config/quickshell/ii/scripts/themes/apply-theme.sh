#!/usr/bin/env bash
# apply-theme.sh — transactional theme application
#
# Flow: back up the live config, stage the theme's config.json + wallpaperPath,
# run switchwall.sh --noswitch to regenerate colors, then validate that matugen
# actually produced a usable colors.json. On validation failure the backup is
# restored so the shell never sees a half-applied theme.
#
# Usage: apply-theme.sh <slug>

set -euo pipefail

SLUG="${1:-}"
[ -z "$SLUG" ] && { echo "usage: apply-theme.sh <slug>" >&2; exit 2; }

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWITCHWALL="$SCRIPT_DIR/../colors/switchwall.sh"

THEMES_DIR="$XDG_CONFIG_HOME/mainstream/themes"
THEME_DIR="$THEMES_DIR/$SLUG"
LAST_APPLIED="$THEMES_DIR/last-applied.txt"

SHELL_CONFIG="$XDG_CONFIG_HOME/illogical-impulse/config.json"
COLORS_JSON="$XDG_STATE_HOME/quickshell/user/generated/colors.json"

# Minimal logger kept for the rollback path only — validation-failure reasons
# otherwise only reach stderr and are lost.
DEBUG_LOG="/tmp/theme-debug.log"
dlog() {
    printf '[%s] [apply-theme pid=%s] %s\n' "$(date '+%H:%M:%S.%3N')" "$$" "$*" >> "$DEBUG_LOG" 2>/dev/null || true
}

# Shared state file read by Config.qml in every quickshell process (main shell
# AND settings window) so both block their own writeAdapter() calls while we
# own config.json. Without this, the settings process races our jq/mv writes
# and clobbers changes after reloading its adapter.
APPLY_STATE_FILE="$XDG_RUNTIME_DIR/quickshell-theme-apply.state"
mkdir -p "$(dirname "$APPLY_STATE_FILE")"
write_apply_state() {
    printf '%s' "$1" > "$APPLY_STATE_FILE.tmp" 2>/dev/null || return 0
    mv -f "$APPLY_STATE_FILE.tmp" "$APPLY_STATE_FILE" 2>/dev/null || return 0
}
write_apply_state "applying"

[ -d "$THEME_DIR" ] || { write_apply_state "idle"; echo "theme dir missing: $THEME_DIR" >&2; exit 3; }
[ -f "$THEME_DIR/config.json" ] || { write_apply_state "idle"; echo "theme config missing" >&2; exit 4; }

# Resolve wallpaper (stored as meta.wallpaperFile, relative to $THEME_DIR) and
# the dark/light mode the theme was saved under. Empty MODE = pre-feature theme,
# in which case switchwall falls back to the GNOME color-scheme setting.
WP_FILE=""
MODE=""
if [ -f "$THEME_DIR/meta.json" ]; then
    WP_FILE=$(jq -r '.wallpaperFile // ""' "$THEME_DIR/meta.json" 2>/dev/null || echo "")
    MODE=$(jq -r '.mode // ""' "$THEME_DIR/meta.json" 2>/dev/null || echo "")
fi
WP_ABS=""
[ -n "$WP_FILE" ] && [ -f "$THEME_DIR/$WP_FILE" ] && WP_ABS="$THEME_DIR/$WP_FILE"

# ── 1. Backup live config for rollback ──────────────────────────────────────
mkdir -p "$(dirname "$SHELL_CONFIG")"
BACKUP=""
if [ -f "$SHELL_CONFIG" ]; then
    BACKUP=$(mktemp --tmpdir="$(dirname "$SHELL_CONFIG")" config.json.backup.XXXXXX)
    cp -f "$SHELL_CONFIG" "$BACKUP"
fi

rollback() {
    local reason="$1"
    dlog "rollback: $reason"
    echo "[apply-theme] validation failed: $reason — rolling back" >&2
    if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
        mv -f "$BACKUP" "$SHELL_CONFIG"
        BACKUP=""
        dlog "rollback: restored backup over $SHELL_CONFIG"
    fi
    exit 5
}

cleanup() {
    [ -n "$BACKUP" ] && [ -f "$BACKUP" ] && rm -f "$BACKUP"
    write_apply_state "idle"
}
trap cleanup EXIT

# ── 2. Stage merged config.json with wallpaperPath rewritten ────────────────
TMP=$(mktemp --tmpdir="$(dirname "$SHELL_CONFIG")" config.json.XXXXXX)
if [ -n "$WP_ABS" ]; then
    jq --arg p "$WP_ABS" '.background.wallpaperPath = $p' "$THEME_DIR/config.json" > "$TMP" \
        || { rm -f "$TMP"; rollback "failed to stage config.json"; }
else
    cp -f "$THEME_DIR/config.json" "$TMP" || { rm -f "$TMP"; rollback "failed to copy config.json"; }
fi
mv -f "$TMP" "$SHELL_CONFIG"

# ── 3. Regenerate colors via switchwall --noswitch ──────────────────────────
# Pass --mode when the theme captured one so matugen regenerates the palette
# in the right brightness AND pre_process() in switchwall flips the GNOME
# color-scheme gsetting too (apps like nautilus/gnome-text-editor watch it).
SWITCHWALL_ARGS=(--noswitch)
[ -n "$MODE" ] && SWITCHWALL_ARGS+=(--mode "$MODE")
if [ -x "$SWITCHWALL" ] || [ -f "$SWITCHWALL" ]; then
    bash "$SWITCHWALL" "${SWITCHWALL_ARGS[@]}" || rollback "switchwall.sh exited non-zero"
else
    rollback "switchwall.sh not found at $SWITCHWALL"
fi

# ── 4. Validate colors.json: exists, parses, has primary ───────────────────
# matugen emits unprefixed material tokens (primary, on_primary, surface, …),
# so "primary" is the canonical sentinel that regeneration actually produced
# a usable palette. It must be non-null AND non-empty — jq -e alone would pass
# on an empty string, which would defeat the purpose of the check.
[ -f "$COLORS_JSON" ] || rollback "colors.json missing at $COLORS_JSON"
jq -e . "$COLORS_JSON" >/dev/null 2>&1 || rollback "colors.json is not valid JSON"
jq -e '(.primary // "") | length > 0' "$COLORS_JSON" >/dev/null 2>&1 \
    || rollback "colors.json missing primary token"

# ── 5. Restore decoration state if the theme snapshotted it ─────────────────
# Themes saved before this feature existed won't have decorations.json, so
# this is optional — missing file leaves the live decoration config alone.
DECO_JSON="$THEME_DIR/decorations.json"
GENERAL_CONF="$XDG_CONFIG_HOME/hypr/hyprland/general.conf"
CUSTOM_CONF="$XDG_CONFIG_HOME/hypr/custom/general.conf"
if [ -f "$DECO_JSON" ]; then
    python3 - "$DECO_JSON" "$GENERAL_CONF" "$CUSTOM_CONF" <<'PY' || dlog "decoration restore failed"
import json, re, sys
deco_path, general, custom = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    flags = json.load(open(deco_path))
except Exception:
    sys.exit(0)

def set_block_enabled(text, block, enabled):
    val = "true" if enabled else "false"
    pat = r'(' + re.escape(block) + r'\s*\{[^}]*?)(enabled\s*=\s*)\w+'
    return re.sub(pat, r'\1\2' + val, text, count=1, flags=re.S)

def set_borders(text, enabled):
    fields = ["border_size", "col.active_border", "col.inactive_border", "resize_on_border"]
    out = []
    for line in text.splitlines(keepends=True):
        stripped = line.lstrip()
        indent = line[:len(line) - len(stripped)]
        matched = False
        for f in fields:
            if enabled:
                if stripped.startswith('# ' + f + ' ') or stripped.startswith('#' + f + ' ') \
                   or stripped.startswith('# ' + f + '=') or stripped.startswith('#' + f + '='):
                    line = indent + stripped.lstrip('# ')
                    matched = True
                    break
            else:
                if stripped.startswith(f + ' ') or stripped.startswith(f + '='):
                    line = indent + '# ' + stripped
                    matched = True
                    break
        if not matched:
            if stripped.startswith('gaps_in'):
                line = indent + 'gaps_in = ' + ('4' if enabled else '0') + '\n'
            elif stripped.startswith('gaps_out'):
                line = indent + 'gaps_out = ' + ('5' if enabled else '0') + '\n'
        out.append(line)
    return ''.join(out)

def set_rounding(text, enabled):
    val = "10" if enabled else "0"
    return re.sub(r'(rounding\s*=\s*)\d+', r'\g<1>' + val, text, count=1)

try:
    text = open(general).read()
    if "animations" in flags: text = set_block_enabled(text, "animations", flags["animations"])
    if "blur" in flags:       text = set_block_enabled(text, "blur", flags["blur"])
    if "shadow" in flags:     text = set_block_enabled(text, "shadow", flags["shadow"])
    if "borders" in flags:    text = set_borders(text, flags["borders"])
    if "roundCorners" in flags: text = set_rounding(text, flags["roundCorners"])
    open(general, "w").write(text)
except FileNotFoundError: pass

if "titleBars" in flags:
    try:
        text = open(custom).read()
        if flags["titleBars"]:
            text = re.sub(r'^([ \t]*)#[ \t]*(plugin[ \t]*=[ \t]*.*hyprbars\.so)', r'\1\2', text, flags=re.M)
        else:
            text = re.sub(r'^([ \t]*)(plugin[ \t]*=[ \t]*.*hyprbars\.so)', r'\1# \2', text, flags=re.M)
        open(custom, "w").write(text)
    except FileNotFoundError: pass
PY
fi

# ── 6. Record last-applied (consumed by ThemesConfig for ordering) ─────────
mkdir -p "$THEMES_DIR"
printf '%s' "$SLUG" > "$LAST_APPLIED.tmp" && mv -f "$LAST_APPLIED.tmp" "$LAST_APPLIED"

# ── 7. Reload hyprland so matugen's hypr color template output and any
#        decoration edits above are picked up by the running session. ─────
command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true

echo "OK"
