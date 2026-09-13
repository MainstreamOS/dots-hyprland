#!/usr/bin/env bash
# =============================================================================
# pixie-sddm-keyboard-bridge
#
# The greeter's QML runs in a sandbox with no way to spawn a process, so it
# cannot call hyprctl itself. It can only read files and write plain key=value
# through QSettings. This script is the other half of that arrangement: it runs
# inside the same Hyprland instance the greeter is drawn on, started from that
# Hyprland's own config.
#
# It does two things, forever:
#
#   - publishes the keyboard layout Hyprland is currently typing in to $STATE,
#     which the greeter polls;
#   - watches $REQUEST for a layout the user picked, and applies it.
#
# Applying goes through hyprctl eval, because the config is Lua and hyprctl
# keyword cannot set anything under it. eval rewrites input:kb_layout rather
# than rotating with switchxkblayout, since the greeter offers every layout XKB
# knows and the one picked is usually not configured yet.
#
# The files live under /run in a directory a tmpfiles entry creates at boot,
# owned by the sddm account: the greeter, running as that user, can write the
# request there, and the directory is readable by everyone, so the session that
# follows can pick up $PICK.
# =============================================================================
set -uo pipefail

RUN_DIR="${PIXIE_KB_DIR:-/run/mainstream-greeter}"
STATE="$RUN_DIR/state"
REQUEST="$RUN_DIR/request"
PICK="$RUN_DIR/pick"

if [[ ! -d "$RUN_DIR" ]] && ! mkdir -p "$RUN_DIR" 2>/dev/null; then
    printf '[pixie-kb-bridge] %s does not exist and cannot be created; is the tmpfiles entry installed?\n' "$RUN_DIR" >&2
    exit 1
fi
if [[ ! -w "$RUN_DIR" ]]; then
    printf '[pixie-kb-bridge] %s is not writable by %s\n' "$RUN_DIR" "$(id -un)" >&2
    exit 1
fi
: > "$REQUEST"
: > "$PICK"
command -v hyprctl >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Hyprland does not take its exec children with it when the greeter ends, and
# an orphan here would keep publishing a dead instance's answer over the next
# greeter's. The instance socket is the sign of life.
SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket.sock"
compositor_alive() {
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -S "$SOCKET" ]]
}
compositor_alive || exit 0

# Written as one whole file rather than appended to, so a reader that catches it
# mid-write sees either the old snapshot or the new one, never half of each.
publish_state() {
    local layouts="" variants="" index=0 tmp active_layout active_variant
    local -a layout_list variant_list

    # The keyboard Hyprland calls main is the one that typed last, and its
    # active index is the truth even if something rotated it behind our back.
    # Split on a character no XKB name contains: read collapses a run of tabs,
    # which would shift the fields whenever the variant is empty. No answer at
    # all means the compositor is not there to ask, which is not the same as
    # it typing in us; the last snapshot stands.
    IFS='|' read -r layouts variants index < <(
        hyprctl -j devices 2>/dev/null \
            | jq -r '[.keyboards[] | select(.name | startswith("hl-virtual") | not)] | ((map(select(.main == true)) + .) | .[0]) | "\(.layout // "")|\(.variant // "")|\(.active_layout_index // 0)"' 2>/dev/null
    )
    [[ -n "$layouts" ]] || return 0
    [[ "$index" =~ ^[0-9]+$ ]] || index=0

    IFS=',' read -r -a layout_list <<< "$layouts"
    IFS=',' read -r -a variant_list <<< "$variants"
    active_layout="${layout_list[$index]:-${layout_list[0]:-us}}"
    active_variant="${variant_list[$index]:-}"

    tmp=$(mktemp "$RUN_DIR/.state.XXXXXX") || return 1
    printf 'activeLayout = %s\nactiveVariant = %s\n' "$active_layout" "$active_variant" > "$tmp"
    chmod 644 "$tmp"
    mv -f "$tmp" "$STATE"
}

# Reads a key out of the QSettings file the greeter writes. QSettings may emit
# a [General] section header and may quote values, so both are tolerated.
_request_value() {
    local key="$1"
    sed -n "s/^[ \t]*${key}[ \t]*=[ \t]*//p" "$REQUEST" 2>/dev/null \
        | tail -1 | tr -d '"' | tr -d '\r' | sed 's/[ \t]*$//'
}

# Consumes the request whatever happens to it, so a pick is not reapplied on
# every tick and a bad one is not retried forever.
apply_request() {
    local want_layout want_variant out
    want_layout=$(_request_value requestedLayout)
    want_variant=$(_request_value requestedVariant)
    # A layout code is a short token from base.lst. Anything else is refused
    # rather than handed to the compositor, and these are the only characters
    # that make the Lua string below safe to build.
    if [[ -n "$want_layout" && "$want_layout" =~ ^[a-zA-Z0-9_-]+$ && "$want_variant" =~ ^[a-zA-Z0-9_-]*$ ]]; then
        out=$(hyprctl eval "hl.config({ input = { kb_layout = \"$want_layout\", kb_variant = \"$want_variant\" } })" 2>&1)
        if [[ "$out" == ok* ]]; then
            printf '%s|%s\n' "$want_layout" "$want_variant" > "$PICK.tmp" && mv -f "$PICK.tmp" "$PICK"
        fi
    fi
    : > "$REQUEST"
}

trap 'rm -f "$STATE" "$REQUEST"; exit 0' TERM INT HUP

# A poll rather than an inotify watch: inotify-tools is not something the
# greeter image is guaranteed to carry, and half a second is well inside what
# reads as instant for someone clicking a menu. Publishing every tick also
# catches a layout changed by anything other than the picker.
while :; do
    compositor_alive || { rm -f "$STATE" "$REQUEST"; exit 0; }
    [[ -s "$REQUEST" ]] && apply_request
    publish_state
    sleep 0.5
done
