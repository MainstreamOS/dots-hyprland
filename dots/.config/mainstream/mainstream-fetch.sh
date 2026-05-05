#!/usr/bin/env bash
# mainstream · animated fastfetch launcher
# place this script wherever you like, then call it from ~/.zshrc
#
# usage: ./mainstream-fetch.sh
# or add to ~/.zshrc:  alias fastfetch="$HOME/.config/mainstream/mainstream-fetch.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMES_DIR="$SCRIPT_DIR/frames"

# ── how many frames to cycle before settling into fastfetch ──
CYCLES=3          # full loops through all frames
FRAME_DELAY=0.08  # seconds between frames

frames=("$FRAMES_DIR"/frame*.txt)
num_frames=${#frames[@]}

cleanup() {
  tput cnorm 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ── animate ──
tput civis          # hide cursor
for (( c=0; c<CYCLES; c++ )); do
  for frame in "${frames[@]}"; do
    tput cup 0 0    # move cursor to top-left without clearing (avoids flicker)
    cat "$frame"
    sleep "$FRAME_DELAY"
  done
done

# ── final frame held while fastfetch prints ──
clear
command fastfetch --logo "${frames[$((num_frames - 1))]}" --logo-type file-raw "$@"
