#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

term_alpha=100 #Set this to < 100 make all your terminals transparent
# sleep 0 # idk i wanted some delay or colors dont get applied properly
if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi

# Race guard: serialize concurrent runs so two parallel invocations
# don't cp + sed the kitty-theme.conf template over each other's
# partial work. -w 30 queues callers up to 30 s; lock auto-releases
# on script exit (see the `wait` calls below that keep fd 9 alive).
#
# The recolour runs whether or not the lock was taken: nothing downstream
# checks this script's status, so it is the only chance the terminals and Qt
# apps get. The `exec` is guarded because bash carries on past a failed
# redirection, which would leave flock working on a descriptor never opened.
if command -v flock >/dev/null 2>&1 && { exec 9>"$STATE_DIR/applycolor.lock"; } 2>/dev/null; then
    flock -w 30 9 2>/dev/null || echo "applycolor.sh: lock wait timed out — applying anyway" >&2
fi

cd "$CONFIG_DIR" || exit

colornames=''
colorstrings=''
colorlist=()
colorvalues=()

colornames=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f1)
colorstrings=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f2 | cut -d ' ' -f2 | cut -d ";" -f1)
IFS=$'\n'
colorlist=($colornames)     # Array of color names
colorvalues=($colorstrings) # Array of color values

apply_kitty() {  
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/kitty-theme.conf" ]; then
    echo "Template file not found for Kitty theme. Skipping that."
    return
  fi
  # Copy template
  mkdir -p "$STATE_DIR"/user/generated/terminal
  cp "$SCRIPT_DIR/terminal/kitty-theme.conf" "$STATE_DIR"/user/generated/terminal/kitty-theme.conf
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/terminal/kitty-theme.conf
  done

  # Reload. pgrep/pidof read every /proc/*/cmdline and hang while any task
  # sits wedged in the kernel holding its mm lock; /proc/*/comm reads don't.
  local p comm kitty_pids=""
  for p in /proc/[0-9]*; do
    read -r comm < "$p/comm" 2>/dev/null || continue
    [[ "$comm" == "kitty" ]] && kitty_pids="$kitty_pids ${p#/proc/}"
  done
  [[ -n "$kitty_pids" ]] && kill -SIGUSR1 $kitty_pids
  return 0
}

apply_ghostty() {
  # Ghostty has no template/sed flow like kitty; a small python script reads
  # the generated material_colors.scss and writes a Ghostty theme file.
  if [ ! -f "$SCRIPT_DIR/generate_ghostty_theme.py" ]; then
    echo "Generator not found for Ghostty theme. Skipping that."
    return
  fi
  mkdir -p "$STATE_DIR"/user/generated/terminal
  python3 "$SCRIPT_DIR/generate_ghostty_theme.py" \
    --scss "$STATE_DIR/user/generated/material_colors.scss" \
    --out "$STATE_DIR/user/generated/terminal/ghostty-theme.conf"

  # Reload running ghostty instances. Ghostty has no reload signal like kitty's
  # SIGUSR1; users bind reload_config (default ctrl+shift+,) to pick up changes.
}

apply_anyterm() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  # Copy template
  mkdir -p "$STATE_DIR"/user/generated/terminal
  cp "$SCRIPT_DIR/terminal/sequences.txt" "$STATE_DIR"/user/generated/terminal/sequences.txt
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/terminal/sequences.txt
  done

  sed -i "s/\$alpha/$term_alpha/g" "$STATE_DIR/user/generated/terminal/sequences.txt"

  for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
      {
      cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
      } & disown || true
    fi
  done
}

apply_kvantum() {
  # Kvantum paints Qt widgets from a static SVG and its own [GeneralColors];
  # neither follows the palette, so both are re-derived from it.
  if [ ! -f "$SCRIPT_DIR/generate_kvantum_theme.py" ]; then
    echo "Generator not found for Kvantum theme. Skipping that."
    return
  fi
  python3 "$SCRIPT_DIR/generate_kvantum_theme.py" \
    --scss "$STATE_DIR/user/generated/material_colors.scss"
}

apply_term() {
  apply_anyterm &
  apply_kitty &
  apply_ghostty &
  # Keep apply_term alive until its children finish, otherwise the
  # outer flock releases before apply_kitty's cp+sed runs.
  wait
}

# Check if terminal theming is enabled in config
CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
if [ -f "$CONFIG_FILE" ]; then
  enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$CONFIG_FILE")
  if [ "$enable_terminal" = "true" ]; then
    apply_term &
  fi
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term &
fi

if [ -f "$CONFIG_FILE" ]; then
  enable_qt_apps=$(jq -r '.appearance.wallpaperTheming.enableQtApps' "$CONFIG_FILE")
  if [ "$enable_qt_apps" != "false" ]; then
    apply_kvantum &
  fi
else
  apply_kvantum &
fi

# apply_qt & # Qt theming is already handled by kde-material-colors

# Hold fd 9 (and the flock) open until every backgrounded apply_* job
# finishes; otherwise the lock releases mid-work.
wait
