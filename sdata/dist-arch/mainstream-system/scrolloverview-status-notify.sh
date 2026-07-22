#!/usr/bin/env bash
# =============================================================================
# scrolloverview-status-notify
#
# Surface scrolloverview plugin health to the user as desktop notifications.
# Runs once per Hyprland session via exec-once (see custom/execs.conf).
#
# Decision flow:
#
#   plugin loaded?  rebuild status  action
#   --------------  --------------  -------------------------------------------
#   yes             failed          silent — old .so still works, timer retries
#   no              failed          notify "off for now" (once per hypr ver)
#   yes             recovered       notify "back" iff prior "off" was shown
#   no              recovered       silent — defer until next session loads .so
#   any             absent          clear seen, silent
#
# Quick early-exits:
#   * user has scrolloverview disabled in config (no `plugin = ... scrolloverview.so`
#     uncommented anywhere) -> exit silently. Don't talk about a feature
#     they're not using.
#
# Reads /var/lib/scrolloverview/status (root-written by rebuild.sh) and tracks
# what was last shown via $XDG_CACHE_HOME/scrolloverview/last-shown so the
# same notification doesn't fire on every login.
#
# Wording is deliberately non-technical. The user sees status, not internals.
# =============================================================================

set -eu

STATUS_FILE=/var/lib/scrolloverview/status
SEEN_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/scrolloverview"
SEEN_FILE="$SEEN_DIR/last-shown"

# ----- predicates -----

# Does the user actually want scrolloverview active? Per the dots-hyprland
# convention, the load directive lives in custom/general.conf, uncommented
# by default (the bar's top-left hot corner depends on it). If the user
# has manually commented it out (or the file is absent), don't nag.
is_scrolloverview_intended() {
    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/custom/general.conf"
    [[ -f "$conf" ]] || return 1
    grep -qE '^[[:space:]]*plugin[[:space:]]*=.*scrolloverview\.so' "$conf"
}

# Is scrolloverview currently loaded in the running compositor? Decisive
# signal: a build failure that hasn't yet caused the .so to unload (because
# the user is still in their pre-upgrade Hyprland and the .so on disk
# still matches what's in memory) is not user-visible, so don't surface it.
is_scrolloverview_loaded() {
    command -v hyprctl >/dev/null 2>&1 || return 1
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 1
    hyprctl plugin list 2>/dev/null | grep -qi 'scrolloverview'
}

# Have we already notified the user that the overview is off for THIS exact
# Hyprland version? Resets across version changes — a new upgrade that
# breaks things again gets its own notification.
already_shown_off_for() {
    [[ -f "$SEEN_FILE" ]] || return 1
    [[ "$(cat "$SEEN_FILE" 2>/dev/null)" == "off-shown:${1}" ]]
}

# A "back" notification only makes sense if we previously told the user
# the overview was off. Otherwise a recovery notification appears out of
# nowhere and is more confusing than helpful.
prior_off_was_shown() {
    [[ -f "$SEEN_FILE" ]]
}

# ----- mutators -----

write_seen_off() {
    mkdir -p "$SEEN_DIR"
    echo "off-shown:$1" > "$SEEN_FILE"
}

clear_seen() {
    rm -f "$SEEN_FILE" 2>/dev/null || true
}

# Notification daemon may not be on the bus the instant Hyprland fires
# exec-once entries (AGS / mako / dunst still starting). Retry briefly.
notify() {
    local urgency="$1" title="$2" body="$3"
    command -v notify-send >/dev/null 2>&1 || return 1
    local _
    for _ in 1 2 3 4 5 6; do
        if notify-send -u "$urgency" -a "Hyprland" -i preferences-desktop \
                       "$title" "$body" 2>/dev/null; then
            return 0
        fi
        sleep 3
    done
    return 1
}

# ----- main -----

# Don't talk to the user about a feature they have disabled. Also clear any
# stale seen-marker so a later re-enable starts from a clean state.
if ! is_scrolloverview_intended; then
    clear_seen
    exit 0
fi

# No status file -> rebuild.sh sees the system as healthy. Reset our marker.
if [[ ! -f "$STATUS_FILE" || ! -r "$STATUS_FILE" ]]; then
    clear_seen
    exit 0
fi

# rebuild.sh writes key=value lines. Source them in (vars pre-declared so
# `set -u` doesn't bite if a key is missing).
state=""; hyprland_version=""; last_attempt=""; recovered_at=""; recovered_from=""
# shellcheck disable=SC1090
. "$STATUS_FILE"

case "$state" in
    failed)
        if is_scrolloverview_loaded; then
            # Overview still functional in-session despite the build
            # failure (typical case: user upgraded Hyprland but hasn't
            # restarted, so the in-memory compositor still matches the
            # previously-built .so). Stay silent — the systemd timer
            # keeps retrying in the background, and we'll only need to
            # surface this if/when the overview actually disappears
            # (next session restart with a still-broken build).
            exit 0
        fi
        if already_shown_off_for "$hyprland_version"; then
            # Already informed the user for this exact Hyprland version.
            # Re-running at exec-once across logout/login cycles is fine
            # — just don't spam.
            exit 0
        fi
        notify low \
            "Workspace overview is off for now" \
            "A recent system update means the workspace overview (top-left hot corner) needs to refresh before it can come back. This happens automatically in the background — usually within a day, sometimes a bit longer. You don't need to do anything; the overview will return on its own next time you log in."
        write_seen_off "$hyprland_version"
        ;;
    recovered)
        if ! is_scrolloverview_loaded; then
            # Build recovered but the running compositor hasn't picked
            # up the new .so yet (user hasn't restarted Hyprland). Defer
            # the "back" notification to the next session that does.
            exit 0
        fi
        if ! prior_off_was_shown; then
            # Plugin loads fine and the build recovered, but the user
            # was never told it was off (probably they kept their old
            # session through the failure window). No need for a
            # closure notification when there was no opening one.
            exit 0
        fi
        notify low \
            "Workspace overview is back" \
            "The workspace overview finished updating and is ready to go again."
        clear_seen
        ;;
    *)
        # Unknown state — don't expose internals.
        :
        ;;
esac
