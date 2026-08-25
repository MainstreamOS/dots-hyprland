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
# Serialise applies. Two runs at once interleave their writes to config.json,
# colors.json and last-applied.txt, and whichever theme wins one file is not
# necessarily the one that wins the others — the grid then marks a theme the
# desktop isn't wearing. Reachable whenever a second apply starts before the
# first finishes, such as the Day/Night scheduler firing while a theme is
# being applied by hand. Wait rather than give up so the later pick still
# lands, and carry on unlocked if flock isn't available.
APPLY_LOCK_FILE="$XDG_RUNTIME_DIR/quickshell-theme-apply.lock"
if command -v flock >/dev/null 2>&1 && { exec 9>"$APPLY_LOCK_FILE"; } 2>/dev/null; then
    flock -w 120 9 2>/dev/null || dlog "lock wait timed out; applying anyway"
fi

# Record the pick before doing the work, not after. Readers watch this file to
# decide which theme to mark as active, and the rest of an apply takes long
# enough that leaving the previous slug in place makes them show the old theme
# for several seconds — a settings page that already moved to the new one gets
# pulled back and then forward again. cleanup() puts the old value back unless
# the run reaches the end.
write_last_applied() {
    mkdir -p "$THEMES_DIR" 2>/dev/null || true
    # Empty means there was no previous pick, so the marker is removed rather
    # than left alone.
    if [ -z "$1" ]; then
        rm -f "$LAST_APPLIED" 2>/dev/null || true
        return 0
    fi
    printf '%s' "$1" > "$LAST_APPLIED.tmp" 2>/dev/null && mv -f "$LAST_APPLIED.tmp" "$LAST_APPLIED" 2>/dev/null || return 0
}
PREV_APPLIED=$(cat "$LAST_APPLIED" 2>/dev/null || true)

# Set up before anything can fail, since the state file below tells the shell
# to stop writing config.json and only this trap turns that back off.
BACKUP=""
STAGED=0
SUCCESS=0
CHILD_PID=""

cleanup() {
    if [ "$SUCCESS" != "1" ]; then
        # Any ending short of the last line — set -e, a cancellation, a logout —
        # leaves the staged config live with the previous theme's colours behind
        # it, so the backup is put back.
        if [ "$STAGED" = "1" ] && [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
            mv -f "$BACKUP" "$SHELL_CONFIG" 2>/dev/null || true
            BACKUP=""
            dlog "cleanup: restored backup over $SHELL_CONFIG"
        fi
        write_last_applied "$PREV_APPLIED"
    fi
    [ -n "$BACKUP" ] && [ -f "$BACKUP" ] && rm -f "$BACKUP" 2>/dev/null
    write_apply_state "idle"
}
trap cleanup EXIT

on_signal() {
    trap - TERM INT
    # Cancelled to start a different theme. Bash doesn't pass the signal on to
    # what it is waiting for, so the colour run has to be taken down by hand or
    # it keeps writing the cancelled theme's palette over the incoming one.
    [ -n "$CHILD_PID" ] && kill -TERM "$CHILD_PID" 2>/dev/null
    exit 143
}
trap on_signal TERM INT

write_apply_state "applying"

[ -d "$THEME_DIR" ] || { echo "theme dir missing: $THEME_DIR" >&2; exit 3; }
[ -f "$THEME_DIR/config.json" ] || { echo "theme config missing" >&2; exit 4; }

write_last_applied "$SLUG"

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
    write_last_applied "$PREV_APPLIED"
    exit 5
}

# ── 2. Stage merged config.json with wallpaperPath rewritten + user meta-state preserved ─
# Some Config fields are user-level preferences that happen to live in the same
# config.json themes snapshot, but conceptually outlive any one theme. If we
# blindly overwrote them with whatever was current when the theme was saved,
# we'd see weird carry-over: the user picks a Day/Night theme, saves a
# different theme later, and when they re-apply that other theme their
# Day/Night selection silently rolls back to whatever was active at save time.
# Read these from the live config BEFORE overwriting and re-inject after.
TMP=$(mktemp --tmpdir="$(dirname "$SHELL_CONFIG")" config.json.XXXXXX)
PRESERVE_THEME_SCHED=""
PRESERVE_LIGHT_NIGHT=""
PRESERVE_CURSOR=""
PRESERVE_SEEDED=""
PRESERVE_APPS=""
PRESERVE_DOCK_PINS=""
PRESERVE_UPDATES=""
if [ -f "$SHELL_CONFIG" ]; then
    # What the live config keeps regardless of what a theme carries, read in
    # one pass. Each of these was its own jq, so the file was forked over and
    # parsed in full seven times on a path the user is waiting through.
    #
    #   appearance.themeSchedule  when the machine changes mode, not a look.
    #   light.night               schedule, automatic flag, mode and color
    #                             temperature are preferences a theme must not
    #                             reset. The save side drops this from new
    #                             snapshots; this protects older ones that
    #                             still carry it.
    #   cursor                    shake-to-locate is behavior, not appearance.
    #   bar.seededWidgets         which widgets have already been offered to
    #                             this machine. A snapshot taken before a
    #                             widget existed would hand the shell back its
    #                             one chance to re-add one the user removed.
    #   dock.pinnedApps           this machine's apps rather than a look;
    #                             a theme carrying them strands a user with
    #                             launchers for software they do not have.
    #   apps, updates             apps.* is the command each button runs by way
    #                             of `bash -c`, and updates.* names the
    #                             manifest this machine believes about
    #                             releases. A theme carrying either would be
    #                             choosing what runs here.
    #
    # One value per line, which is safe because tojson escapes any newline
    # inside a value rather than emitting it. Reading them tab separated would
    # not be: that escapes backslashes too, and apps.* holds shell commands.
    # `// empty` also treats false as absent, so that is matched here.
    mapfile -t _PRESERVED < <(jq -r '
        [.appearance.themeSchedule, .light.night, .cursor, .bar.seededWidgets,
         .dock.pinnedApps, .apps, .updates]
        | map(if . == null or . == false then "" else tojson end) | .[]' \
        "$SHELL_CONFIG" 2>/dev/null || true)
    PRESERVE_THEME_SCHED="${_PRESERVED[0]:-}"
    PRESERVE_LIGHT_NIGHT="${_PRESERVED[1]:-}"
    PRESERVE_CURSOR="${_PRESERVED[2]:-}"
    PRESERVE_SEEDED="${_PRESERVED[3]:-}"
    PRESERVE_DOCK_PINS="${_PRESERVED[4]:-}"
    PRESERVE_APPS="${_PRESERVED[5]:-}"
    PRESERVE_UPDATES="${_PRESERVED[6]:-}"
fi
JQ_FILTER='.'
JQ_ARGS=()
[ -n "$WP_ABS" ]                  && { JQ_FILTER+=' | .background.wallpaperPath = $p';            JQ_ARGS+=(--arg p "$WP_ABS"); }
# The wallpaper slideshow belongs to whichever theme is on, so a theme saved
# with a single wallpaper has to stop one the previous theme started. A key
# that is merely absent from the snapshot won't do it — the shell's config
# adapter keeps the value it already has when a key disappears from the file —
# so say it outright. Themes saved before the slideshow existed land here too,
# which is what makes them turn it off rather than inherit it.
jq -e '.background.slideshow' "$THEME_DIR/config.json" >/dev/null 2>&1 \
    || JQ_FILTER+=' | .background.slideshow.enable = false'
# An imported theme has had the folder stripped out of it, since it named a
# directory in someone else's home. Empty rather than missing, so it resolves
# to the local wallpaper directory instead of whatever this machine last used.
jq -e '.background.slideshow | has("folder")' "$THEME_DIR/config.json" >/dev/null 2>&1 \
    || JQ_FILTER+=' | .background.slideshow.folder = ""'
# How see-through the bar is and what color its pills take belong to the theme,
# so a snapshot naming none of it means stock rather than whatever the last theme
# was wearing — the rule the decorations restore further down states, for the
# same reason: every theme saved before these existed was saved wearing stock, so
# stock is the honest reading of one. Asked one at a time because a snapshot can
# hold some and not others; the keys it carries deserve their values and the
# rest deserve stock.
# A right-biased object merge, because presence is the whole test: false and 0
# are both settings someone chose, and only a key the snapshot never wrote may
# take the stock value.
# How big the dock's icons are, what it marks its running apps with and whether
# it keeps the buttons at its ends belong to the look as much as its colors do,
# so they ride along with the rest of its dress. A theme that names none of them
# was saved wearing stock and reads as stock, the same as one naming no color.
JQ_FILTER+=' | .bar = ({backgroundOpacity: -1, widgetOpacity: -1, widgetRadius: -1, floatRadius: -1, widgetColorDark: "", widgetColorLight: "", backgroundColorDark: "", backgroundColorLight: "", floatStyleShadow: true} + (.bar // {}))'
JQ_FILTER+=' | .dock = ({showBackground: true, backgroundOpacity: -1, backgroundColorDark: "", backgroundColorLight: "", badgeColorDark: "", badgeColorLight: "", badgeTextColorDark: "", badgeTextColorLight: "", radius: -1, cornerStyle: "float", topRadius: -1, iconSize: -1, indicatorStyle: "dashes", showOverviewButton: true, showPinButton: true} + (.dock // {}))'
# Which edge the dock sits on belongs to the theme, but only when the theme has
# an opinion. A snapshot taken before the setting existed names no edge, and an
# absent key is the worst of both: the adapter keeps showing the dock where it
# is while the file says nothing, so the next start moves it somewhere the user
# never chose. Write the live edge in instead, so the screen and the file agree.
if ! jq -e '.dock | has("position")' "$THEME_DIR/config.json" >/dev/null 2>&1; then
    PRESERVE_DOCK_POS=$(jq -c '.dock.position // empty' "$SHELL_CONFIG" 2>/dev/null || true)
    [ -n "$PRESERVE_DOCK_POS" ] && { JQ_FILTER+=' | .dock.position = $dockpos'; JQ_ARGS+=(--argjson dockpos "$PRESERVE_DOCK_POS"); }
fi
[ -n "$PRESERVE_THEME_SCHED" ]    && { JQ_FILTER+=' | .appearance.themeSchedule = $sched';        JQ_ARGS+=(--argjson sched "$PRESERVE_THEME_SCHED"); }
[ -n "$PRESERVE_LIGHT_NIGHT" ]    && { JQ_FILTER+=' | .light.night = $night';                     JQ_ARGS+=(--argjson night "$PRESERVE_LIGHT_NIGHT"); }
[ -n "$PRESERVE_CURSOR" ]         && { JQ_FILTER+=' | .cursor = $cursor';                          JQ_ARGS+=(--argjson cursor "$PRESERVE_CURSOR"); }
[ -n "$PRESERVE_SEEDED" ]         && { JQ_FILTER+=' | .bar.seededWidgets = $seeded';               JQ_ARGS+=(--argjson seeded "$PRESERVE_SEEDED"); }
# Nothing live to put back means the snapshot's copy is dropped rather than
# inherited: absent is the safe answer here, since the shell falls back to its
# own defaults for these.
[ -n "$PRESERVE_DOCK_PINS" ]      && { JQ_FILTER+=' | .dock.pinnedApps = $pins';               JQ_ARGS+=(--argjson pins "$PRESERVE_DOCK_PINS"); }
if [ -n "$PRESERVE_APPS" ]; then    JQ_FILTER+=' | .apps = $apps';    JQ_ARGS+=(--argjson apps "$PRESERVE_APPS");
else                                JQ_FILTER+=' | del(.apps)'; fi
if [ -n "$PRESERVE_UPDATES" ]; then JQ_FILTER+=' | .updates = $upd';  JQ_ARGS+=(--argjson upd "$PRESERVE_UPDATES");
else                                JQ_FILTER+=' | del(.updates)'; fi
if [ "$JQ_FILTER" = '.' ]; then
    cp -f "$THEME_DIR/config.json" "$TMP" || { rm -f "$TMP"; rollback "failed to copy config.json"; }
else
    jq "${JQ_ARGS[@]}" "$JQ_FILTER" "$THEME_DIR/config.json" > "$TMP" \
        || { rm -f "$TMP"; rollback "failed to stage config.json"; }
fi
mv -f "$TMP" "$SHELL_CONFIG"
STAGED=1

# switchwall gives up with a success code when there is no image to read, and
# the colours already on disk would satisfy every check below. Checked here,
# where the reason is known, rather than inferred later from an unchanged file.
EFFECTIVE_WP=$(jq -r '.background.wallpaperPath // ""' "$SHELL_CONFIG" 2>/dev/null || echo "")
[ -n "$EFFECTIVE_WP" ] || rollback "theme has no wallpaper to generate colours from"

# ── 3. Regenerate colors via switchwall --noswitch ──────────────────────────
# Pass --mode when the theme captured one so matugen regenerates the palette
# in the right brightness AND pre_process() in switchwall flips the GNOME
# color-scheme gsetting too (apps like nautilus/gnome-text-editor watch it).
SWITCHWALL_ARGS=(--noswitch --config-staged)
[ -n "$MODE" ] && SWITCHWALL_ARGS+=(--mode "$MODE")
if [ -x "$SWITCHWALL" ] || [ -f "$SWITCHWALL" ]; then
    # Backgrounded and waited on, because bash holds trapped signals until a
    # foreground child finishes and a cancellation has to be acted on now.
    # Descriptor 9 carries this run's lock and is closed for the whole colour
    # run: switchwall starts things that outlive it — mpvpaper for a video
    # wallpaper lasts the session — and an inherited lock is never given back.
    SW_RC=0
    bash "$SWITCHWALL" "${SWITCHWALL_ARGS[@]}" 9>&- &
    CHILD_PID=$!
    wait "$CHILD_PID" || SW_RC=$?
    CHILD_PID=""
    [ "$SW_RC" -eq 0 ] || rollback "switchwall.sh exited non-zero (rc=$SW_RC)"
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
# Targets the Lua-config tree introduced in Hyprland 0.55.
GENERAL_CONF="$XDG_CONFIG_HOME/hypr/hyprland/general.lua"
CUSTOM_CONF="$XDG_CONFIG_HOME/hypr/custom/general.lua"
DECORATIONS_PY="$SCRIPT_DIR/decorations.py"
# A theme can carry the animation profile its snapshot names; the file has to
# be in place before the restore below points the compositor at it. Shipped
# names are never written — every install has its own copies, and a theme is
# not how the stock set updates.
ANIM_SRC="$THEME_DIR/animations"
ANIM_DST="$XDG_CONFIG_HOME/hypr/hyprland/animations"
if [ -d "$ANIM_SRC" ] && [ -f "$DECORATIONS_PY" ]; then
    SHIPPED=$(python3 "$DECORATIONS_PY" shipped "$GENERAL_CONF" 2>/dev/null | tr '\n' ' ')
    mkdir -p "$ANIM_DST"
    for ANIM_FILE in "$ANIM_SRC"/*.lua; do
        [ -f "$ANIM_FILE" ] || continue
        ANIM_BASE=$(basename "$ANIM_FILE" .lua)
        printf '%s' "$ANIM_BASE" | grep -qE '^[A-Za-z0-9_-]+$' || continue
        case " $SHIPPED " in *" $ANIM_BASE "*) continue ;; esac
        cp -f "$ANIM_FILE" "$ANIM_DST/$ANIM_BASE.lua" 2>/dev/null || dlog "animation profile install failed: $ANIM_BASE"
    done
fi

# restore rather than write: keys the snapshot doesn't name go to their stock
# values, because they didn't exist as settings when the theme was saved —
# leaving them alone kept the previous theme's look bleeding into this one.
# --push hands the same completed set to the compositor from inside the one
# interpreter, so the change shows before the reload at the end gets there.
if [ -f "$DECO_JSON" ] && [ -f "$DECORATIONS_PY" ]; then
    python3 "$DECORATIONS_PY" restore "$GENERAL_CONF" "$DECO_JSON" \
        --flag-dir "$(dirname "$CUSTOM_CONF")" --push >/dev/null 2>&1 \
        || dlog "decoration restore failed"
fi

# ── 5b. Restore interface look (gsettings) if the theme snapshotted it ──────
# Themes saved before this feature have no interface.json → live gsettings are
# left alone. Applied AFTER switchwall so the saved App style / Icons / Mouse
# cursor / cursor size win over matugen's icon-theme recolor.
IFACE_JSON="$THEME_DIR/interface.json"
if [ -f "$IFACE_JSON" ] && command -v gsettings >/dev/null 2>&1; then
    GTK_THEME=$(jq -r '.gtkTheme // empty' "$IFACE_JSON" 2>/dev/null || true)
    ICON_THEME=$(jq -r '.iconTheme // empty' "$IFACE_JSON" 2>/dev/null || true)
    CURSOR_THEME=$(jq -r '.cursorTheme // empty' "$IFACE_JSON" 2>/dev/null || true)
    CURSOR_SIZE=$(jq -r '.cursorSize // empty' "$IFACE_JSON" 2>/dev/null || true)
    [ -n "$GTK_THEME" ]    && gsettings set org.gnome.desktop.interface gtk-theme    "$GTK_THEME"    2>/dev/null || true
    [ -n "$ICON_THEME" ]   && gsettings set org.gnome.desktop.interface icon-theme   "$ICON_THEME"   2>/dev/null || true
    [ -n "$CURSOR_THEME" ] && gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME" 2>/dev/null || true
    [ -n "$CURSOR_SIZE" ]  && gsettings set org.gnome.desktop.interface cursor-size  "$CURSOR_SIZE"  2>/dev/null || true
    # gsettings alone doesn't repaint the Hyprland cursor — push it live.
    [ -n "$CURSOR_THEME" ] && [ -n "$CURSOR_SIZE" ] && command -v hyprctl >/dev/null 2>&1 \
        && hyprctl setcursor "$CURSOR_THEME" "$CURSOR_SIZE" >/dev/null 2>&1 || true
fi

# ── 5c. Mirror the theme's shell fonts into the GTK/Qt interface fonts ──────
# Reads the just-restored config.json; no-op if apply-gtk-font.sh is absent.
[ -x "$SCRIPT_DIR/apply-gtk-font.sh" ] && bash "$SCRIPT_DIR/apply-gtk-font.sh" 2>/dev/null || true

# ── 5d. Restore window rules if the theme snapshotted them ──────────────────
# Same contract as decorations: a theme saved before rules existed has no
# windowrules.json and leaves the live rules alone; one that carries the file
# wins wholesale, empty list included — no rules at save time is part of the
# look. Routed through the owner script's write verb rather than copied, so a
# theme that arrived as an import gets the same validation the settings page
# gets, and the generated Lua plus reload come along for free.
WR_JSON="$THEME_DIR/windowrules.json"
WINDOWRULES_PY="$XDG_CONFIG_HOME/quickshell/ii/scripts/hyprland/windowrules.py"
if [ -f "$WR_JSON" ] && [ -f "$WINDOWRULES_PY" ]; then
    python3 "$WINDOWRULES_PY" write \
        "$XDG_CONFIG_HOME/hypr/hyprland/userrules.json" \
        "$XDG_CONFIG_HOME/hypr/hyprland/userrules.lua" --no-reload \
        < "$WR_JSON" >/dev/null 2>&1 || dlog "window rules restore failed"
fi

# ── 6. Re-assert last-applied (recorded up front; see write_last_applied) ──
write_last_applied "$SLUG"

# ── 7. Reload hyprland, then restore kitty ─────────────────────────────────
# The decorations already went live in step 5; this reload is what the rest of
# the config needs.
if command -v hyprctl >/dev/null 2>&1; then

    # Full reload is still needed for matugen's hyprland color templates
    # (sourced files) and the titlebar plugin (hyprbars.so can't be toggled
    # live). hyprctl reload is synchronous -- it returns only after Hyprland
    # has finished re-parsing everything.
    hyprctl reload >/dev/null 2>&1 || true

    # hyprctl reload briefly disrupts every Wayland client's surface state.
    # kitty ends up in a stuck configure handshake: it receives input again
    # only after the compositor sends it a new configure event, which normally
    # only happens on move/resize. Without intervention the terminal also stays
    # on the previous colour scheme because the SIGUSR1 sent earlier by
    # applycolor.sh fired before the reload wiped the rendered state.
    #
    # Fix: wait for Hyprland's surfaces to settle, then SIGUSR1 every kitty
    # process. SIGUSR1 tells kitty to reload its config -- it picks up the
    # freshly generated kitty-theme.conf AND issues a new Wayland surface
    # commit that clears the stuck state and restores input responsiveness.
    # No kitty process is killed; the signal is handled gracefully by kitty.
    #
    # Nothing else waits on this, so it settles on its own rather than holding
    # the run open -- the wait is measured from the reload either way. It closes
    # the lock on descriptor 9 first, or it would keep the next apply waiting on
    # a lock this one has already finished with.
    (
        sleep 0.3
        # comm-file matching instead of pkill: cmdline scans hang while any task
        # is wedged in the kernel holding its mm lock; comm reads don't.
        for _p in /proc/[0-9]*; do
            read -r _comm < "$_p/comm" 2>/dev/null || continue
            [[ "$_comm" == "kitty" ]] && kill -SIGUSR1 "${_p#/proc/}" 2>/dev/null
        done
    ) >/dev/null 2>&1 9>&- &

fi

# ── 8. Restage the desktop portal, now the whole look has settled ───────────
RESTAGE_PORTALS="$SCRIPT_DIR/../colors/restage-portals.sh"
[ -f "$RESTAGE_PORTALS" ] && bash "$RESTAGE_PORTALS" >/dev/null 2>&1 9>&- &

SUCCESS=1
echo "OK"
