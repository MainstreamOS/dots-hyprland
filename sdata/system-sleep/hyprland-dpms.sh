#!/bin/bash
# Hyprland DPMS restore on wake
# Safe for all hardware — pure userspace, no detection needed

case "$1" in
  pre)
    for uid_path in /run/user/*/hypr; do
      [ -d "$uid_path" ] || continue
      uid=$(echo "$uid_path" | grep -oP '(?<=/run/user/)\d+')
      for instance in "$uid_path"/*/; do
        [ -d "$instance" ] || continue
        sig=$(basename "$instance")
        # Under the Lua config `hyprctl dispatch X` runs `return hl.dispatch(X)`,
        # so X has to be a Lua dispatcher; the plain `dpms off` form is refused.
        HYPRLAND_INSTANCE_SIGNATURE="$sig" \
          XDG_RUNTIME_DIR="/run/user/$uid" \
          hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' 2>/dev/null
      done
    done
    ;;
  post)
    # NVIDIA reinitializes slower than AMD — give it extra time
    if lsmod | grep -q "^nvidia "; then
        sleep 3
    else
        sleep 2
    fi

    for uid_path in /run/user/*/hypr; do
      [ -d "$uid_path" ] || continue
      uid=$(echo "$uid_path" | grep -oP '(?<=/run/user/)\d+')
      for instance in "$uid_path"/*/; do
        [ -d "$instance" ] || continue
        sig=$(basename "$instance")
        HYPRLAND_INSTANCE_SIGNATURE="$sig" \
          XDG_RUNTIME_DIR="/run/user/$uid" \
          hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' 2>/dev/null
      done
    done
    ;;
esac
