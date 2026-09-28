#!/usr/bin/env bash
# Gracefully shuts down all current windows using Hyprland's controls.
# This allows for the user to save work versus a pkill.
set -uo pipefail

# Capture the addresses of all windows that exist right now.
windows=$(hyprctl clients -j | jq -r '.[].address')

# Gracefully request that every captured window close.
while read -r address; do
    [ -n "$address" ] || continue

    hyprctl dispatch 'hl.dsp.window.close({ window = "address:'"$address"'" })'
done <<< "$windows"

# Wait until every captured window has disappeared.
while read -r address; do
    [ -n "$address" ] || continue

    while hyprctl clients -j |
        jq -e --arg address "$address" \
        'any(.[]; .address == $address)' >/dev/null
    do
        sleep 0.1
    done
done <<< "$windows"
