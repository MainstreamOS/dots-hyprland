#!/usr/bin/env bash
# Plays a sound when a system update ends, for anyone who stepped away from a
# long one: "complete" when it succeeded and a warning when it did not. The
# setting and the sound theme are read now rather than when the update began,
# so switching the sound off part way through is respected.
#
#   finished-sound.sh <exit code>
#
# A run stopped by hand stays quiet: whoever pressed Stop is already watching.
rc="${1:-1}"
case "$rc" in 130|143) exit 0 ;; esac

config="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
read -r enabled theme < <(python3 - "$config" <<'PY' 2>/dev/null
import json, re, sys
try:
    sounds = json.load(open(sys.argv[1])).get("sounds", {})
except Exception:
    sounds = {}
theme = str(sounds.get("theme", "freedesktop"))
if not re.fullmatch(r"[A-Za-z0-9._-]+", theme) or theme.startswith("."):
    theme = "freedesktop"
print("1" if sounds.get("update", False) else "0", theme)
PY
)
[[ "${enabled:-0}" == 1 ]] || exit 0

name=$([[ "$rc" == 0 ]] && echo complete || echo dialog-warning)
file=""
for t in "${theme:-freedesktop}" freedesktop; do
    for ext in oga ogg; do
        f="/usr/share/sounds/$t/stereo/$name.$ext"
        [[ -f "$f" ]] && { file="$f"; break 2; }
    done
done
[[ -n "$file" ]] || exit 0

# The same player the shell's other sounds use, with PipeWire's own as a
# fallback on a system without ffmpeg.
if command -v ffplay >/dev/null 2>&1; then
    timeout 15 ffplay -nodisp -autoexit -loglevel quiet "$file" >/dev/null 2>&1
elif command -v pw-play >/dev/null 2>&1; then
    timeout 15 pw-play "$file" >/dev/null 2>&1
fi
exit 0
