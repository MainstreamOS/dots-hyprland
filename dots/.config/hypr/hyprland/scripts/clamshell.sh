#!/usr/bin/env bash
# Mainstream OS - Dynamic Laptop Clamshell & Lid Switch Management
# Handles display migration when closing/opening laptop lid while docked or standalone.

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mainstream"
STATE_FILE="$STATE_DIR/clamshell-internal-monitor"
UNIT="mainstream-lid-inhibit.service"

is_inhibited() {
  systemctl --user is-active --quiet "$UNIT" 2>/dev/null
}

inhibit_lid() {
  if ! is_inhibited; then
    systemd-run --user --quiet --collect --unit="$UNIT" \
      --description="Mainstream Clamshell Lid Switch Inhibitor" \
      --property=PartOf=graphical-session.target \
      systemd-inhibit --what=handle-lid-switch --mode=block \
      --who="Mainstream OS" --why="Laptop docked or sleep on lid close disabled" sleep infinity 9>&- &
  fi
}

uninhibit_lid() {
  if is_inhibited; then
    systemctl --user stop "$UNIT" 2>/dev/null || true
  fi
}

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
  local internal="${1:-}"
  [ -n "$internal" ] || internal=$(get_internal_monitor)

  # 1. Check Hyprland active monitors
  if command -v hyprctl >/dev/null 2>&1; then
    local ext_hypr
    ext_hypr=$(hyprctl monitors -j 2>/dev/null | jq -r --arg int "$internal" '[.[] | select(.name != $int and .name != "HEADLESS-1" and .disabled != true)] | length' 2>/dev/null || echo "0")
    if [ "$ext_hypr" -gt 0 ]; then
      return 0
    fi
  fi

  # 2. Check sysfs DRM connection status (including USB-C and Unknown dock connectors)
  local status connector state
  for status in /sys/class/drm/card*-*/status; do
    [ -f "$status" ] || continue
    connector=$(basename "$(dirname "$status")")
    connector="${connector#card*-}"
    if [[ "$connector" =~ ^(eDP|LVDS|DSI)- ]]; then
      continue
    fi
    if { IFS= read -r state < "$status"; } 2>/dev/null && [[ "$state" == connected ]]; then
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
    # jq's // would replace a false too, so only a missing value takes the default.
    val=$(jq -r '.display.clamshellMode | if . == null then true else . end' "$cfg" 2>/dev/null || echo "true")
    if [ "$val" = "true" ] || [ "$val" = "clamshell" ]; then
      printf '%s\n' "clamshell"
      return 0
    elif [ "$val" = "ignore" ]; then
      printf '%s\n' "ignore"
      return 0
    else
      printf '%s\n' "suspend"
      return 0
    fi
  fi
  printf '%s\n' "clamshell"
}

get_sleep_on_lid_close() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
  if [ -r "$cfg" ] && command -v jq >/dev/null 2>&1; then
    local val
    val=$(jq -r '.display.sleepOnLidClose | if . == null then true else . end' "$cfg" 2>/dev/null || echo "true")
    if [ "$val" = "false" ]; then
      return 1
    fi
  fi
  return 0
}

reconcile_inhibitor() {
  local internal
  internal=$(get_internal_monitor)
  # Without a built-in panel there is no lid to hold.
  if [ -z "$internal" ]; then
    uninhibit_lid
  elif has_external_monitor "$internal" || ! get_sleep_on_lid_close; then
    inhibit_lid
  else
    uninhibit_lid
  fi
}

# Hyprland's Lua config has no `hyprctl keyword`, so monitors change through hl.monitor.
# It changes only the fields it is given, so turning a panel back on has to say so.
set_monitor() {
  hyprctl eval "hl.monitor({ $1 })" >/dev/null 2>&1 || true
}

is_monitor_enabled() {
  hyprctl monitors -j 2>/dev/null | jq -e --arg name "$1" 'any(.[]; .name == $name)' >/dev/null 2>&1
}

# Enabled outputs that duplicate $1. hyprctl names the source by its id, not its name.
get_mirrors_of() {
  hyprctl monitors all -j 2>/dev/null | jq -r --arg name "$1" '(.[] | select(.name == $name) | .id | tostring) as $id | .[] | select(.disabled != true and (.mirrorOf == $id or .mirrorOf == $name)) | .name' 2>/dev/null || true
}

is_mirror() {
  hyprctl monitors all -j 2>/dev/null | jq -e --arg name "$1" 'any(.[]; .name == $name and .disabled != true and .mirrorOf != "none")' >/dev/null 2>&1
}

# Hyprland applies a monitor rule a moment after the call returns and merges changes that land
# together, so a step that must happen on its own waits until hyprctl reports it. $2 is the
# "disabled" value to wait for.
wait_monitor_disabled() {
  for _ in $(seq 60); do
    [ "$(hyprctl monitors all -j 2>/dev/null | jq -r --arg name "$1" '.[] | select(.name == $name) | .disabled' 2>/dev/null)" = "$2" ] && return 0
    sleep 0.05
  done
  return 1
}

# In Hyprland 0.57 an output that connected as a duplicate has no wl_output, and ending the
# duplication does not give it one, so clients cannot draw on it. Off and on does. The pause
# lets clients bind the new output before the next change takes another one away.
detach_mirror() {
  set_monitor "output = \"$1\", mirror = \"\", disabled = true"
  wait_monitor_disabled "$1" true || true
  set_monitor "output = \"$1\", disabled = false"
  wait_monitor_disabled "$1" false || true
  sleep 0.3
}

# The numbered workspace $1 shows, when it has windows on it.
workspace_in_view_on() {
  local id
  id=$(hyprctl monitors all -j 2>/dev/null | jq -r --arg name "$1" '.[] | select(.name == $name) | .activeWorkspace.id // empty' 2>/dev/null || true)
  [[ "$id" =~ ^[1-9][0-9]*$ ]] || return 0
  hyprctl workspaces -j 2>/dev/null | jq -r --argjson id "$id" '.[] | select(.id == $id and .windows > 0) | .id' 2>/dev/null || true
}

# A workspace that moved to another screen stays out of view there. Workspace $1 is shown on
# the screen that received it, unless that screen has windows of its own in view.
bring_workspace_into_view() {
  local workspaces monitors
  [ -n "${1:-}" ] || return 0
  workspaces=$(hyprctl workspaces -j 2>/dev/null) && monitors=$(hyprctl monitors -j 2>/dev/null) || return 0
  jq -n -e --argjson id "$1" --argjson workspaces "$workspaces" --argjson monitors "$monitors" '
    ($workspaces[] | select(.id == $id) | .monitor) as $screen
    | ($monitors[] | select(.name == $screen) | .activeWorkspace.id) as $shown
    | $shown != $id and ([$workspaces[] | select(.id == $shown) | .windows] | add // 0) == 0' >/dev/null 2>&1 || return 0
  hyprctl dispatch "hl.dsp.focus({ workspace = $1 })" >/dev/null 2>&1 || true
}

# The keyboard stays with the window that had it, even on a workspace no screen shows any
# more, so typing would go to a window nobody sees; and a screen that hands its workspace
# back is left with no window focused. Focus moves to the last used window that is in view.
focus_a_window_in_view() {
  local monitors workspace target screen
  monitors=$(hyprctl monitors -j 2>/dev/null) || return 0
  workspace=$(hyprctl activewindow -j 2>/dev/null | jq -r '.workspace.name // empty' 2>/dev/null || true)
  if [ -n "$workspace" ]; then
    jq -e --arg ws "$workspace" 'any(.[]; .disabled != true and (.mirrorOf // "none") == "none"
      and (.activeWorkspace.name == $ws or .specialWorkspace.name == $ws))' <<<"$monitors" >/dev/null 2>&1 && return 0
  fi
  target=$(hyprctl clients -j 2>/dev/null | jq -r --argjson monitors "$monitors" '
    [$monitors[] | select(.disabled != true and (.mirrorOf // "none") == "none") | .activeWorkspace.id] as $shown
    | [.[] | select(.mapped and (.hidden | not) and (.workspace.id as $id | $shown | index($id)))]
    | sort_by(.focusHistoryID) | .[0].address // empty' 2>/dev/null || true)
  if [ -n "$target" ]; then
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$target\" })" >/dev/null 2>&1 || true
  elif [ -n "$workspace" ]; then
    screen=$(jq -r 'map(select(.disabled != true and (.mirrorOf // "none") == "none"))
      | (map(select(.focused)) + .)[0].name // empty' <<<"$monitors" 2>/dev/null || true)
    [ -z "$screen" ] || hyprctl dispatch "hl.dsp.focus({ monitor = \"$screen\" })" >/dev/null 2>&1 || true
  fi
}

save_internal_state() {
  local internal="$1"
  mkdir -p "$STATE_DIR"
  if command -v hyprctl >/dev/null 2>&1; then
    local info
    info=$(hyprctl monitors -j 2>/dev/null | jq -r --arg int "$internal" '.[] | select(.name == $int) | "\(.width)x\(.height)@\(.refreshRate) \(.x)x\(.y) \(.scale) \(.transform)"' 2>/dev/null || true)
    if [ -n "$info" ] && [ "$info" != "null" ]; then
      printf '%s\n' "$info${2:+ ${2% }}" > "$STATE_FILE"
      return 0
    fi
  fi
}

# logind may already be suspending for the same lid close, and this can resume after waking,
# so it only sleeps while the lid is still shut.
sleep_now() {
  loginctl lock-session >/dev/null 2>&1 || true
  is_lid_closed && systemctl suspend >/dev/null 2>&1 || true
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
        inhibit_lid
        # Saved only while the panel is on, so a second close cannot overwrite it.
        if is_monitor_enabled "$internal"; then
          local mirrors ext in_view
          mirrors=$(get_mirrors_of "$internal" | tr '\n' ' ')
          in_view=$(workspace_in_view_on "$internal")
          save_internal_state "$internal" "$mirrors"
          # Duplicates take over as screens of their own while the panel is still on.
          for ext in $mirrors; do
            detach_mirror "$ext"
          done
          set_monitor "output = \"$internal\", disabled = true"
          wait_monitor_disabled "$internal" true || true
          bring_workspace_into_view "$in_view"
          focus_a_window_in_view
        fi
        ;;
      suspend)
        uninhibit_lid
        sleep_now
        ;;
      ignore)
        inhibit_lid
        ;;
    esac
  else
    if get_sleep_on_lid_close; then
      uninhibit_lid
      sleep_now
    else
      inhibit_lid
    fi
  fi
}

handle_open() {
  local internal
  internal=$(get_internal_monitor)
  [ -n "$internal" ] || exit 0

  reconcile_inhibitor

  if [ -s "$STATE_FILE" ]; then
    local mode="" pos="" scale="" transform="" mirrors="" ext in_view=""
    read -r mode pos scale transform mirrors < "$STATE_FILE" || true
    [ -z "$mirrors" ] || in_view=$(workspace_in_view_on "${mirrors%% *}")
    if [ -n "$mode" ] && [ -n "$pos" ] && [ -n "$scale" ]; then
      # A rotated panel, as some small laptops have, comes back the right way up.
      set_monitor "output = \"$internal\", disabled = false, mode = \"$mode\", position = \"$pos\", scale = \"$scale\", transform = ${transform:-0}"
    else
      set_monitor "output = \"$internal\", disabled = false, mode = \"preferred\", position = \"auto\", scale = \"auto\""
    fi
    # The outputs that duplicated the panel before the lid closed do so again once it is back.
    if [ -n "$mirrors" ]; then
      wait_monitor_disabled "$internal" false || true
      sleep 0.3
      for ext in $mirrors; do
        set_monitor "output = \"$ext\", mirror = \"$internal\""
      done
      # Their workspaces go to the panel, which shows what was on them.
      for _ in $(seq 60); do
        is_mirror "${mirrors%% *}" && break
        sleep 0.05
      done
      bring_workspace_into_view "$in_view"
    else
      # The panel takes its workspaces back a moment after it is on.
      wait_monitor_disabled "$internal" false || true
      sleep 0.3
    fi
    focus_a_window_in_view
    rm -f "$STATE_FILE"
  elif ! is_monitor_enabled "$internal"; then
    set_monitor "output = \"$internal\", disabled = false, mode = \"preferred\", position = \"auto\", scale = \"auto\""
  fi
}

handle_check() {
  local internal
  internal=$(get_internal_monitor)
  [ -n "$internal" ] || exit 0

  reconcile_inhibitor

  local mode
  mode=$(get_clamshell_setting)

  if [ "$mode" = "clamshell" ] && is_lid_closed && has_external_monitor "$internal"; then
    handle_close
  elif ! is_lid_closed && [ -f "$STATE_FILE" ]; then
    handle_open
  fi
}

# A monitor came or went, which has no lid event. Undocked with the lid shut, this is a lid close.
handle_monitors_changed() {
  local internal
  internal=$(get_internal_monitor)
  [ -n "$internal" ] || exit 0

  reconcile_inhibitor
  if is_lid_closed; then
    if has_external_monitor "$internal"; then
      [ "$(get_clamshell_setting)" = "clamshell" ] && handle_close
    else
      handle_close
    fi
  fi
}

# One run at a time: turning outputs off and on fires the monitor events that start this script again.
mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/clamshell.lock"
flock -w 30 9 || exit 0

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
  reconcile)
    reconcile_inhibitor
    ;;
  monitors)
    handle_monitors_changed
    ;;
  detach)
    # For the display settings, before they stop an output duplicating another.
    shift
    for output in "$@"; do
      ! is_mirror "$output" || detach_mirror "$output"
    done
    ;;
  off)
    # For the display settings, before a reload that turns off an output others stay set to
    # duplicate: the reload would attach them to it for a moment and leave no screen at all.
    shift
    for output in "$@"; do
      is_monitor_enabled "$output" || continue
      set_monitor "output = \"$output\", disabled = true"
      wait_monitor_disabled "$output" true || true
    done
    ;;
  on)
    # For the display settings, before a reload that turns $1 on together with its duplicates.
    # They let go of it first, so they stay screens until clients have bound the one coming on.
    shift
    if [ -n "${1:-}" ] && ! is_monitor_enabled "$1"; then
      for output in "${@:2}"; do
        set_monitor "output = \"$output\", mirror = \"\""
      done
      set_monitor "output = \"$1\", disabled = false"
      wait_monitor_disabled "$1" false || true
      sleep 0.3
    fi
    ;;
  *)
    echo "Usage: $0 {close|open|check|reconcile|monitors|detach <output>...|off <output>...|on <output> [<duplicate>...]}" >&2
    exit 1
    ;;
esac
