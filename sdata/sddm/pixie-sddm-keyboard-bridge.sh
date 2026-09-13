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
# keyword cannot set anything under it ("keyword can't work with non-legacy
# parsers"). eval rewrites input:kb_layout rather than rotating with
# switchxkblayout, since the greeter offers every layout XKB knows and the one
# picked is usually not configured yet.
#
# The files live under /run in a directory a tmpfiles entry creates at boot,
# owned by the sddm account: the greeter, running as that user, can write the
# request there, and the directory is readable by everyone, so the session that
# follows can pick up $PICK and the log survives the greeter's exit.
# =============================================================================
set -uo pipefail

RUN_DIR="${PIXIE_KB_DIR:-/run/mainstream-greeter}"
STATE="$RUN_DIR/state"
REQUEST="$RUN_DIR/request"
PICK="$RUN_DIR/pick"
LOG="$RUN_DIR/bridge.log"

log() {
    local line
    line="$(date '+%H:%M:%S') $*"
    printf '[pixie-kb-bridge] %s\n' "$line" >&2
    [[ -w "$RUN_DIR" ]] && printf '%s\n' "$line" >> "$LOG"
}

if [[ ! -d "$RUN_DIR" ]] && ! mkdir -p "$RUN_DIR" 2>/dev/null; then
    printf '[pixie-kb-bridge] %s does not exist and cannot be created; is the tmpfiles entry installed?\n' "$RUN_DIR" >&2
    exit 1
fi
if [[ ! -w "$RUN_DIR" ]]; then
    printf '[pixie-kb-bridge] %s is not writable by %s\n' "$RUN_DIR" "$(id -un)" >&2
    exit 1
fi
: > "$LOG"
: > "$REQUEST"
: > "$PICK"
command -v hyprctl >/dev/null 2>&1 || { log "hyprctl not found; nothing to bridge."; exit 0; }
log "started as $(id -un) for instance ${HYPRLAND_INSTANCE_SIGNATURE:-<unset>}, runtime dir ${XDG_RUNTIME_DIR:-<unset>}"

last_published=""

# Written as one whole file rather than appended to, so a reader that catches it
# mid-write sees either the old snapshot or the new one, never half of each.
publish_state() {
    local layouts="" variants="" index=0 tmp active_layout active_variant
    local -a layout_list variant_list

    # The keyboard Hyprland calls main is the one that typed last, and its
    # active index is the truth even if something rotated it behind our back.
    # Split on a character no XKB name contains: read collapses a run of
    # tabs, which would shift the fields whenever the variant is empty.
    if command -v jq >/dev/null 2>&1; then
        IFS='|' read -r layouts variants index < <(
            hyprctl -j devices 2>/dev/null \
                | jq -r '(.keyboards[] | select(.main == true)) // .keyboards[0] | "\(.layout // "")|\(.variant // "")|\(.active_layout_index // 0)"' 2>/dev/null
        )
    fi
    if [[ -z "$layouts" ]]; then
        layouts=$(hyprctl getoption input:kb_layout 2>/dev/null | sed -n 's/^str: *//p' | head -1)
        variants=$(hyprctl getoption input:kb_variant 2>/dev/null | sed -n 's/^str: *//p' | head -1)
        index=0
    fi
    # No answer at all means the compositor is not there to ask, which is not
    # the same as it typing in us; leave the last snapshot standing.
    [[ -n "$layouts" ]] || return 0
    [[ "$index" =~ ^[0-9]+$ ]] || index=0

    IFS=',' read -r -a layout_list <<< "$layouts"
    IFS=',' read -r -a variant_list <<< "$variants"
    active_layout="${layout_list[$index]:-${layout_list[0]:-us}}"
    active_variant="${variant_list[$index]:-}"

    tmp=$(mktemp "$RUN_DIR/.state.XXXXXX") || return 1
    {
        printf 'layouts = %s\n'       "$layouts"
        printf 'variants = %s\n'      "$variants"
        printf 'activeLayout = %s\n'  "$active_layout"
        printf 'activeVariant = %s\n' "$active_variant"
    } > "$tmp"
    chmod 644 "$tmp"
    mv -f "$tmp" "$STATE"

    if [[ "$active_layout|$active_variant|$layouts" != "$last_published" ]]; then
        log "in effect: $active_layout${active_variant:+ ($active_variant)}, list $layouts"
        last_published="$active_layout|$active_variant|$layouts"
    fi
}

# Reads a key out of the QSettings file the greeter writes. QSettings may emit
# a [General] section header and may quote values, so both are tolerated.
_request_value() {
    local key="$1"
    sed -n "s/^[ \t]*${key}[ \t]*=[ \t]*//p" "$REQUEST" 2>/dev/null \
        | tail -1 | tr -d '"' | tr -d '\r' | sed 's/[ \t]*$//'
}

apply_request() {
    local want_layout want_variant out
    want_layout=$(_request_value requestedLayout)
    want_variant=$(_request_value requestedVariant)
    if [[ -z "$want_layout" ]]; then
        log "request without a layout, ignored: $(tr '\n' ' ' < "$REQUEST")"
        : > "$REQUEST"
        return 0
    fi

    # A layout code is a short token from base.lst. Refuse anything else rather
    # than handing an arbitrary string to the compositor, and these are the only
    # characters that make the Lua string below safe to build.
    if [[ ! "$want_layout" =~ ^[a-zA-Z0-9_-]+$ || ! "$want_variant" =~ ^[a-zA-Z0-9_-]*$ ]]; then
        log "ignoring request with an unusable layout '$want_layout' or variant '$want_variant'"
        : > "$REQUEST"
        return 0
    fi

    log "request: layout '$want_layout' variant '${want_variant:-<none>}'"
    out=$(hyprctl eval "hl.config({ input = { kb_layout = \"$want_layout\", kb_variant = \"$want_variant\" } })" 2>&1)
    if [[ "$out" == ok* ]]; then
        log "applied"
        printf '%s|%s\n' "$want_layout" "$want_variant" > "$PICK.tmp" && mv -f "$PICK.tmp" "$PICK"
    else
        log "eval failed: $out"
    fi

    # Consume it, so the same pick is not reapplied on every tick.
    : > "$REQUEST"
    publish_state
}

trap 'rm -f "$STATE" "$REQUEST"; log "stopped"; exit 0' TERM INT HUP

# Hyprland does not take its exec children with it when the greeter ends, and
# an orphan here would keep publishing a dead instance's answer over the next
# greeter's. The instance socket is the sign of life.
SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket.sock"
compositor_alive() {
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -S "$SOCKET" ]]
}
if ! compositor_alive; then
    log "no live compositor at $SOCKET; nothing to bridge"
    exit 0
fi

publish_state

# A poll rather than an inotify watch: inotify-tools is not something the
# greeter image is guaranteed to carry, and half a second is well inside what
# reads as instant for someone clicking a menu.
while :; do
    compositor_alive || { log "compositor gone"; rm -f "$STATE" "$REQUEST"; exit 0; }
    [[ -s "$REQUEST" ]] && apply_request
    sleep 0.5
    # Cheap enough to republish every tick, and it catches a layout changed by
    # anything other than the picker.
    publish_state
done
