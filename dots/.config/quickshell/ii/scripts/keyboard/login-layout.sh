#!/usr/bin/env bash
# The layout picked on the login screen becomes this session's first layout.
# The greeter's bridge records the pick under /run; this runs once at session
# start, puts that layout at the head of the enabled list, and stores the list
# the same way Settings → Keyboard does (its managed block, then localed), so
# Settings shows it and the next login screen starts in it. Nothing happens when
# no pick was made or it already leads the list.
set -uo pipefail

PICK="${MAINSTREAM_GREETER_PICK:-/run/mainstream-greeter/pick}"
LOG_DIR="$HOME/.local/state/mainstream"
LOG="$LOG_DIR/login-layout.log"
WRITER="$HOME/.config/quickshell/ii/scripts/keyboard/write-layouts.py"
CONF="$HOME/.config/hypr/custom/general.lua"

mkdir -p "$LOG_DIR"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

[[ -s "$PICK" ]] || exit 0
IFS='|' read -r pick_layout pick_variant < "$PICK"
pick_variant="${pick_variant:-}"
if [[ ! "$pick_layout" =~ ^[a-zA-Z0-9_-]+$ || ! "$pick_variant" =~ ^[a-zA-Z0-9_-]*$ ]]; then
    log "ignoring an unusable pick: $(tr '\n' ' ' < "$PICK")"
    exit 0
fi

# This runs from the compositor's start hook, which can fire before its
# keyboards are registered, so the empty answer gets a few seconds of patience.
layouts="" variants=""
for _ in $(seq 1 15); do
    IFS='|' read -r layouts variants < <(
        hyprctl -j devices 2>/dev/null \
            | jq -r '(.keyboards[] | select(.main == true)) // .keyboards[0] | "\(.layout // "")|\(.variant // "")"' 2>/dev/null
    )
    [[ -n "$layouts" ]] && break
    sleep 0.2
done
[[ -n "$layouts" ]] || { log "could not read the current layouts from Hyprland"; exit 1; }

IFS=',' read -r -a current_layouts <<< "$layouts"
IFS=',' read -r -a current_variants <<< "$variants"
if [[ "${current_layouts[0]:-}" == "$pick_layout" && "${current_variants[0]:-}" == "$pick_variant" ]]; then
    log "pick $pick_layout${pick_variant:+ ($pick_variant)} already leads the list"
    exit 0
fi

new_layouts=("$pick_layout")
new_variants=("$pick_variant")
for i in "${!current_layouts[@]}"; do
    layout="${current_layouts[$i]}"
    variant="${current_variants[$i]:-}"
    [[ -n "$layout" ]] || continue
    [[ "$layout" == "$pick_layout" && "$variant" == "$pick_variant" ]] && continue
    new_layouts+=("$layout")
    new_variants+=("$variant")
done
layout_list=$(IFS=','; printf '%s' "${new_layouts[*]}")
variant_list=$(IFS=','; printf '%s' "${new_variants[*]}")

if [[ -n "${LOGIN_LAYOUT_DRY_RUN:-}" ]]; then
    printf '%s / %s\n' "$layout_list" "$variant_list"
    exit 0
fi

if ! python3 "$WRITER" "$CONF" "$layout_list" "$variant_list"; then
    log "could not store $layout_list / $variant_list"
    exit 1
fi
hyprctl eval "hl.config({ input = { kb_layout = \"$layout_list\", kb_variant = \"$variant_list\" } })" >/dev/null 2>&1
hyprctl reload >/dev/null 2>&1
log "applied $layout_list / $variant_list from the login screen pick"
