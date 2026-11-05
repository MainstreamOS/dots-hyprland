#!/usr/bin/env bash
# Mainstream OS - Dynamic Laptop Clamshell & Lid Switch Management
# Handles display migration when closing/opening laptop lid while docked or standalone.

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mainstream"
STATE_FILE="$STATE_DIR/clamshell-internal-monitor"

# Find internal panel connector name (eDP-*, LVDS-*, DSI-*)
get_internal_monitor() {
  local mon=""
  if command -v hyprctl >/dev/null 2>&1; then
    mon=$(hyprctl monitors all -j 2>/dev/null | jq -r '.[] | select(.name | test("^(eDP|LVDS|DSI)-")) | .name' 2>/dev/null | head -n 1 || true)
  fi
  if [ -z "$mon" ]; then
    for path in /sys/class/drm/card*-*/status; do
      [ -f "$path" ] || continue
      local connector
      connector=$(basename "$(dirname "$path")")
      connector="${connector#card*-}"
      if [[ "$connector" =~ ^(eDP|LVDS|DSI)- ]]; then
        mon="$connector"
        break
      fi
    done
  fi
  printf '%s\n' "$mon"
}

# Returns 0 if an external monitor is connected
has_external_monitor() {
  local internal="$1"

  # 1. Check Hyprland active monitors
  if command -v hyprctl >/dev/null 2>&1; then
    local ext_hypr
    ext_hypr=$(hyprctl monitors -j 2>/dev/null | jq -r --arg int "$internal" '[.[] | select(.name != $int and .name != "HEADLESS-1")] | length' 2>/dev/null || echo "0")
    if [ "$ext_hypr" -gt 0 ]; then
      return 0
    fi
  fi

  # 2. Check sysfs DRM connection status
  for status in /sys/class/drm/card*-*/status; do
    [ -f "$status" ] || continue
    local connector
    connector=$(basename "$(dirname "$status")")
    connector="${connector#card*-}"
    if [[ "$connector" =~ ^(eDP|LVDS|DSI)- ]]; then
      continue
    fi
    if [ "$(< "$status" 2>/dev/null)" = "connected" ]; then
      return 0
    fi
  done

  return 1
}

# Returns 0 if laptop lid is physically closed
is_lid_closed() {
  # Check ACPI lid button state
  for state in /proc/acpi/button/lid/*/state; do
    [ -r "$state" ] || continue
    if grep -qi "closed" "$state" 2>/dev/null; then
      return 0
    fi
  done

  # Fallback to systemd-logind LidClosed property
  if command -v busctl >/dev/null 2>&1; then
    local prop
    prop=$(busctl --timeout=2 get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager LidClosed 2>/dev/null || true)
    if [ "$prop" = "b true" ]; then
      return 0
    fi
  fi

  return 1
}

# Reads clamshell setting from config.json ("clamshell" | "suspend" | "ignore" or boolean)
get_clamshell_setting() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
  if [ -r "$cfg" ] && command -v jq >/dev/null 2>&1; then
    local val
    val=$(jq -r '.display.clamshellMode // true' "$cfg" 2>/dev/null || echo "true")
    if [ "$val" = "true" ] || [ "$val" = "clamshell" ]; then
      printf '%s\n' "clamshell"
      return 0
    elif [ "$val" = "suspend" ]; then
      printf '%s\n' "suspend"
      return 0
    else
      printf '%s\n' "ignore"
      return 0
    fi
  fi
  printf '%s\n' "clamshell"
}

get_sleep_on_lid_close() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
  if [ -r "$cfg" ] && command -v jq >/dev/null 2>&1; then
    local val
    val=$(jq -r '.display.sleepOnLidClose // true' "$cfg" 2>/dev/null || echo "true")
    if [ "$val" = "false" ]; then
      return 1
    fi
  fi
  return 0
}

save_internal_state() {
  local internal="$1"
  mkdir -p "$STATE_DIR"
  if command -v hyprctl >/dev/null 2>&1; then
    local info
    info=$(hyprctl monitors all -j 2>/dev/null | jq -r --arg int "$internal" '.[] | select(.name == $int) | "\(.width)x\(.height)@\(.refreshRate | floor) \(.x)x\(.y) \(.scale)"' 2>/dev/null || true)
    if [ -n "$info" ] && [ "$info" != "null" ]; then
      printf '%s\n' "$info" > "$STATE_FILE"
      return 0
    fi
  fi
}

handle_close() {
  local internal
  internal=$(get_internal_monitor)
  [ -n "$internal" ] || exit 0

  local mode
  mode=$(get_clamshell_setting)

  if has_external_monitor "$internal"; then
    case "$mode" in
      clamshell)
        save_internal_state "$internal"
        hyprctl keyword monitor "$internal, disable" >/dev/null 2>&1 || true
        ;;
      suspend)
        systemctl suspend >/dev/null 2>&1 || true
        ;;
      ignore)
        # Keep internal screen and session active without disabling output
        ;;
    esac
  else
    if get_sleep_on_lid_close; then
      systemctl suspend >/dev/null 2>&1 || true
    fi
  fi
}

handle_open() {
  local internal
  internal=$(get_internal_monitor)
  [ -n "$internal" ] || exit 0

  if [ -s "$STATE_FILE" ]; then
    read -r mode pos scale < "$STATE_FILE" || true
    if [ -n "$mode" ] && [ -n "$pos" ] && [ -n "$scale" ]; then
      hyprctl keyword monitor "$internal, $mode, $pos, $scale" >/dev/null 2>&1 || true
    else
      hyprctl keyword monitor "$internal, preferred, auto, auto" >/dev/null 2>&1 || true
    fi
    rm -f "$STATE_FILE"
  else
    hyprctl keyword monitor "$internal, preferred, auto, auto" >/dev/null 2>&1 || true
  fi
}

handle_check() {
  local internal
  internal=$(get_internal_monitor)
  [ -n "$internal" ] || exit 0

  local mode
  mode=$(get_clamshell_setting)

  if [ "$mode" = "clamshell" ] && is_lid_closed && has_external_monitor "$internal"; then
    handle_close
  elif ! is_lid_closed && [ -f "$STATE_FILE" ]; then
    handle_open
  fi
}

case "${1:-check}" in
  close)
    handle_close
    ;;
  open)
    handle_open
    ;;
  check)
    handle_check
    ;;
  *)
    echo "Usage: $0 {close|open|check}" >&2
    exit 1
    ;;
esac
