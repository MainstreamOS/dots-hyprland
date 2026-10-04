# This script is meant to be sourced.
# It's not for directly running.
# shellcheck shell=bash

# Settings a release changed the meaning of, brought up to date on a machine
# that already had them. config.json is never replaced by an update, and
# neither is anything in hypr/custom/, so a stock value a release changed or a
# setting it split in two stays as the old release left it unless something
# carries it across. Each step here only acts on a state an older release left
# behind, so running it again, or on a machine that never had that state,
# changes nothing.
#
#   config_migrations_run [--hypr-only] <path to config.json>
#
# --hypr-only does the steps in hypr/custom/ and leaves config.json alone.
#
# A missing config.json means no shell has run for this user yet, and the
# first one seeds everything here itself, so there is nothing to do. The
# function returns 0 whatever happens, so a caller under errexit carries on.

# Where the release being installed keeps its own copies of the shell scripts.
_CFGMIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" || _CFGMIG_ROOT=""

# Whatever sourced this may have no log_info of its own. Collected and said
# once everything is written: a caller whose output has gone away is stopped
# by the first line it prints, and that must not cut a step short.
_CFGMIG_NOTES=()
_cfgmig_note() {
  _CFGMIG_NOTES+=("$*")
}
_cfgmig_say() {
  if declare -F log_info >/dev/null 2>&1; then log_info "$1"; else echo "$1"; fi
}
_cfgmig_say_notes() {
  local note
  for note in "${_CFGMIG_NOTES[@]}"; do _cfgmig_say "$note"; done
}

# Renamed into place, since Hyprland reads these files on every reload and a
# reload can land at any moment.
_cfgmig_put() {
  local target="$1" value="$2" tmp
  tmp=$(mktemp "${target}.XXXXXX" 2>/dev/null) || return 1
  if printf '%s' "$value" >"$tmp" && mv -f "$tmp" "$target"; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null
  return 1
}

# The mode the shell is showing, as TitleBars.qml sees it: dark when the
# generated background is darker than half lightness. The color-scheme setting
# is what switchwall.sh last settled on, and stands in when the colors cannot
# be read; "default" says neither, so it gives no answer.
_cfgmig_shell_mode() {
  local colors="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/colors.json"
  local bg="" scheme="" r g b hi lo v
  if command -v jq >/dev/null 2>&1; then
    bg=$(jq -r '.background | strings' "$colors" 2>/dev/null) || bg=""
  fi
  bg="${bg#\#}"
  # Eight digits are Qt's #AARRGGBB.
  [[ ${#bg} -eq 8 ]] && bg="${bg:2}"
  if [[ "$bg" =~ ^[0-9A-Fa-f]{6}$ ]]; then
    r=$((16#${bg:0:2})) g=$((16#${bg:2:2})) b=$((16#${bg:4:2}))
    hi=$r lo=$r
    for v in "$g" "$b"; do
      if [[ $v -gt $hi ]]; then hi=$v; fi
      if [[ $v -lt $lo ]]; then lo=$v; fi
    done
    if [[ $((hi + lo)) -lt 255 ]]; then echo dark; else echo light; fi
    return 0
  fi
  command -v gsettings >/dev/null 2>&1 || return 1
  if command -v timeout >/dev/null 2>&1; then
    scheme=$(timeout 5 gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null) || scheme=""
  else
    scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null) || scheme=""
  fi
  scheme="${scheme//\'/}"
  case "$scheme" in
    prefer-dark) echo dark ;;
    prefer-light) echo light ;;
    *) return 1 ;;
  esac
}

# Title Bars keep a color and an opacity for each mode, and plugins.lua picks
# the set from custom/colormode, which only switchwall.sh writes. A machine
# that has never run the release with that split has no colormode, so
# Hyprland draws the dark set whatever the shell shows, while Settings shows
# and edits the light set in light mode. The mode goes in once here, and the
# end-of-update reload applies it.
#
# One color and opacity used to cover both modes. When the user picked a
# color, it goes into the light set as well, so their bar still looks the
# same in light mode. Without a picked color they get the new light bar: the
# old Settings page wrote the stock opacity beside every color change, so an
# opacity alone is not a choice worth carrying. The missing colormode is also
# what marks this as a machine the split has not reached, since every install
# of the new release writes one, and it stops this ever running twice.
_cfgmig_titlebars() {
  local custom="${HOME}/.config/hypr/custom" color="" opacity="" mode="" copied=""
  [[ -e "${custom}/colormode" || -L "${custom}/colormode" ]] && return 0
  mkdir -p "$custom" 2>/dev/null || return 0
  if [[ -f "${custom}/titlebars.color" ]]; then
    color=$(head -n1 -- "${custom}/titlebars.color" 2>/dev/null) || color=""
  fi
  # The same test the old plugins.lua put a color through.
  if [[ "${color#\#}" =~ ^[0-9A-Fa-f]{6}$ ]]; then
    if [[ ! -e "${custom}/titlebars.colorLight" ]]; then
      _cfgmig_put "${custom}/titlebars.colorLight" "$color" && copied=1
    fi
    if [[ ! -e "${custom}/titlebars.opacityLight" ]]; then
      if [[ -f "${custom}/titlebars.opacity" ]]; then
        opacity=$(head -n1 -- "${custom}/titlebars.opacity" 2>/dev/null) || opacity=""
      fi
      opacity="${opacity//[[:space:]]/}"
      # What the old plugins.lua drew for a missing or unreadable opacity.
      [[ "$opacity" =~ ^-?[0-9]*\.?[0-9]+$ ]] || opacity=0.5333
      _cfgmig_put "${custom}/titlebars.opacityLight" "$opacity" && copied=1
    fi
  fi
  [[ -n "$copied" ]] && _cfgmig_note "Kept your Title Bar color in light mode"
  mode=$(_cfgmig_shell_mode) || return 0
  _cfgmig_put "${custom}/colormode" "$mode" || true
  return 0
}

# The window rounding in the user's general.lua, as the release's own reader
# spells it, or null when it cannot tell.
_cfgmig_window_rounding() {
  local py="" f out
  local -a readers=()
  [[ -n "$_CFGMIG_ROOT" ]] && readers+=("${_CFGMIG_ROOT}/dots/.config/quickshell/ii/scripts/themes/decorations.py")
  readers+=("${HOME}/.config/quickshell/ii/scripts/themes/decorations.py")
  for f in "${readers[@]}"; do
    if [[ -f "$f" ]]; then py="$f"; break; fi
  done
  if [[ -z "$py" ]] || ! command -v python3 >/dev/null 2>&1; then echo null; return 0; fi
  if command -v timeout >/dev/null 2>&1; then
    out=$(timeout -k 5 20 python3 -B "$py" read "${HOME}/.config/hypr/hyprland/general.lua" 2>/dev/null) || out=""
  else
    out=$(python3 -B "$py" read "${HOME}/.config/hypr/hyprland/general.lua" 2>/dev/null) || out=""
  fi
  out=$(jq -c '.rounding | numbers' <<<"$out" 2>/dev/null) || out=""
  echo "${out:-null}"
}

# A config.json that names no appearance.roundCornersRestore was last written
# whole by a release before it existed: the shell writes every key it knows,
# and a theme apply fills that one in, so it dates the file.
#
# Magnify: the stock strength came down from 135 to 100 percent. -1 means
# "the stock one", so a user who never moved the slider would have the effect
# weaken under them. Before the effect had a key, Magnify was the only one,
# so a file without it was showing Magnify as well.
#
# Rounded Corners: the old switch squared the windows and the bar but left the
# screen corners alone. Now the switch reads off from the window rounding and
# squares the screen corners too, so a machine left off by the old switch is
# squared the way RoundedCorners.turnOff does it, with the screen corners
# remembered so turning the switch on brings them back. The window radius
# the old switch replaced was never kept, so turning it on takes the page's
# own, as it would have done then.
#
# DeepSeek: the stock custom model now ships with its own icon. extraModels is
# a stored list, so the old entry keeps the spark until it is changed here.
_CFGMIG_JQ='
def dated: (.appearance | type) == "object" and (.appearance | has("roundCornersRestore"));
def magnify_stock: (.dock == null or (.dock | type) == "object")
  and ((.dock.hoverEffect // "magnify") == "magnify")
  and ((.dock.hoverMagnify // -1) | type == "number" and . < 0);
def corners_left: $rounding == 0
  and (.bar | type) == "object" and .bar.cornerStyle == 2
  and (.appearance == null or (.appearance | type) == "object")
  and ((.appearance.fakeScreenRounding // 2) | type == "number" and . != 0);
def deepseek: type == "object" and .name == "Custom: DS R1 Dstl. LLaMA 70B"
  and .model == "deepseek/deepseek-r1-distill-llama-70b:free" and .icon == "spark-symbolic";
# Anything but an object is not a file the shell wrote, and is left as it is.
if type != "object" then {m: [], d: .} else
(if dated then [] else
   [(if magnify_stock then "magnify" else empty end),
    (if corners_left then "corners" else empty end)] end) as $old
| (if (.ai | type) == "object" and (.ai.extraModels | type) == "array"
      and any(.ai.extraModels[]; deepseek) then ["deepseek"] else [] end) as $icon
| ($old + $icon) as $steps
| def has_step($s): $steps | any(. == $s);
  {m: $steps, d: (.
    | if has_step("magnify") then .dock.hoverEffect = "magnify" | .dock.hoverMagnify = 135 else . end
    | if has_step("corners") then
        .appearance.roundCornersRestore = {barCornerStyle: -1,
          fakeScreenRounding: (.appearance.fakeScreenRounding // 2), windowRounding: -1}
        | .appearance.fakeScreenRounding = 0
      else . end
    | if has_step("deepseek") then
        .ai.extraModels |= map(if deepseek then .icon = "deepseek-symbolic" else . end)
      else . end)}
end'

# config.json is shared with the running shell, which writes it back whenever a
# setting changes. Written the way a theme apply writes it: under the apply
# lock, with the state file telling every shell process to hold its own writes
# and reread the file once this is done, so neither undoes the other.
_cfgmig_config_json() {
  local cfg="$1" real rounding plan steps runtime lock state="" lockfd="" tmp done_steps="" s
  command -v jq >/dev/null 2>&1 || return 0
  real=$(readlink -f -- "$cfg" 2>/dev/null) || real="$cfg"
  [[ -f "$real" ]] || return 0
  rounding=$(_cfgmig_window_rounding)
  plan=$(jq -c --argjson rounding "$rounding" "$_CFGMIG_JQ" "$real" 2>/dev/null) || return 0
  steps=$(jq -r '.m | join(" ")' <<<"$plan" 2>/dev/null) || return 0
  [[ -n "$steps" ]] || return 0

  runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if [[ -d "$runtime" && -w "$runtime" ]]; then
    lock="${runtime}/quickshell-theme-apply.lock"
    state="${runtime}/quickshell-theme-apply.state"
    if command -v flock >/dev/null 2>&1 && exec {lockfd}>"$lock"; then
      # A theme apply in progress finishes first. Past the wait this run
      # leaves the file alone, and the next update finds the same old state.
      flock -w 30 "$lockfd" || return 0
    fi
    # The shells stop holding their writes once this says idle, whether the
    # write below lands or not. Only this subshell is left by the trap, and
    # the path is fixed now, since the local is gone by the time it runs.
    # shellcheck disable=SC2064
    trap "_cfgmig_put $(printf '%q' "$state") idle || true" EXIT
    _cfgmig_put "$state" applying || true
  fi

  # Decided again from the file as it is now, since the shell may have written
  # it while the lock was awaited.
  plan=$(jq -c --argjson rounding "$rounding" "$_CFGMIG_JQ" "$real" 2>/dev/null) || return 0
  done_steps=$(jq -r '.m | join(" ")' <<<"$plan" 2>/dev/null) || return 0
  [[ -n "$done_steps" ]] || return 0
  tmp=$(mktemp "${real}.XXXXXX" 2>/dev/null) || return 0
  # Four spaces, as the shell writes it.
  if jq --indent 4 '.d' <<<"$plan" >"$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    chmod --reference="$real" "$tmp" 2>/dev/null || true
    if ! mv -f "$tmp" "$real"; then
      rm -f "$tmp" 2>/dev/null
      return 0
    fi
  else
    rm -f "$tmp" 2>/dev/null
    return 0
  fi
  if [[ -n "$state" ]]; then
    _cfgmig_put "$state" idle || true
    trap - EXIT
  fi
  [[ -n "$lockfd" ]] && exec {lockfd}>&-
  for s in $done_steps; do
    case "$s" in
      magnify) _cfgmig_note "Kept your Dock's Magnify strength" ;;
      corners) _cfgmig_note "Squared the screen corners, since Rounded Corners is off" ;;
    esac
  done
  return 0
}

config_migrations_run() {
  local hypr_only=0 cfg
  if [[ "${1:-}" == --hypr-only ]]; then hypr_only=1; shift; fi
  cfg="${1:-}"
  [[ -n "$cfg" && -e "$cfg" ]] || return 0
  if [[ "${DRY_RUN:-false}" == true ]]; then
    _cfgmig_say "[DRY-RUN] Would update any settings a release renamed or reshaped"
    return 0
  fi
  # Run as root it would leave root-owned files in the user's home.
  [[ "$(id -u)" -ne 0 ]] || return 0
  # In a subshell with errexit, nounset and any ERR trap left behind, so
  # nothing in here can stop the caller, and the lock and trap end with it.
  (
    set +euE +o pipefail
    trap - ERR
    _CFGMIG_NOTES=()
    _cfgmig_titlebars
    (( hypr_only )) || _cfgmig_config_json "$cfg"
    _cfgmig_say_notes
  ) || true
  return 0
}
