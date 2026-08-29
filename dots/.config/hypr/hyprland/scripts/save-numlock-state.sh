#!/usr/bin/env bash
set -euo pipefail

# The non-consuming Hyprland binding fires alongside the real Num Lock key,
# so give the compositor a moment to publish the resulting LED state.
sleep 0.1

state_dir="${HOME}/.local/state/mainstream"
state_file="${state_dir}/numlock"
state_value=0
found_led=0

for led_file in /sys/class/leds/*::numlock/brightness; do
    [[ -r "$led_file" ]] || continue
    found_led=1
    read -r led_value < "$led_file"
    if [[ "$led_value" == "1" ]]; then
        state_value=1
    fi
done

(( found_led == 1 )) || exit 0

install -d -m 0755 "$state_dir"
state_tmp=$(mktemp "${state_dir}/.numlock.XXXXXX")
trap 'rm -f "$state_tmp"' EXIT
printf '%s\n' "$state_value" > "$state_tmp"
chmod 0644 "$state_tmp"
mv -f "$state_tmp" "$state_file"
trap - EXIT
