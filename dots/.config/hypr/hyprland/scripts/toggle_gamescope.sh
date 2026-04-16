#!/bin/bash

# -------------------------------------------------------
# toggle_gamescope.sh
# Log file: ~/.gamescope_toggle.log
#
# Required sudoers entries (NOPASSWD):
#   %wheel ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop sddm
#   %wheel ALL=(ALL) NOPASSWD: /usr/bin/systemctl start sddm
#   %wheel ALL=(ALL) NOPASSWD: /usr/bin/seatd
#   %wheel ALL=(ALL) NOPASSWD: /usr/bin/chvt
#   %wheel ALL=(ALL) NOPASSWD: /usr/bin/setcap
#   %wheel ALL=(ALL) NOPASSWD: /usr/bin/python3
#   %wheel ALL=(ALL) NOPASSWD: /usr/bin/kill
# -------------------------------------------------------

LOG="$HOME/.gamescope_toggle.log"
exec >> "$LOG" 2>&1
echo "--- $(date) ---"

# -------------------------------------------------------
# If gamescope is already running, kill everything
# -------------------------------------------------------
if pgrep -f "gamescope -W" > /dev/null; then
    echo "Gamescope running, killing..."
    pkill -f "gamescope -W"
    pkill -f "gamescopereaper"
    pkill -f "steam"
    echo "Done."
    exit 0
fi

# -------------------------------------------------------
# Grab everything we need BEFORE escaping the session
# -------------------------------------------------------
if [ -z "$GAMESCOPE_ESCAPED" ]; then
    echo "Gathering monitor and TTY info..."

    MONITOR=$(hyprctl monitors -j | jq '.[] | select(.focused == true)')
    WIDTH=$(echo "$MONITOR"     | jq '.width')
    HEIGHT=$(echo "$MONITOR"    | jq '.height')
    REFRESH=$(echo "$MONITOR"   | jq '.refreshRate | ceil')

    CONNECTOR=$(echo "$MONITOR" | jq -r '.name')
    CURRENT_TTY=$(fgconsole)

    # Check ~/.config/hypr/monitors.conf for vrr,1 on the active connector
    MONITORS_CONF="$HOME/.config/hypr/monitors.conf"
    VRR_CAPABLE=0
    if [ -f "$MONITORS_CONF" ]; then
        if grep -E "^monitor=${CONNECTOR}," "$MONITORS_CONF" | grep -q "vrr,1"; then
            VRR_CAPABLE=1
        fi
    fi

    # Detect SDDM TTY while we still have session access
    SDDM_PID=$(systemctl show -p MainPID sddm --value 2>/dev/null)
    SDDM_TTY=1
    if [ -n "$SDDM_PID" ] && [ "$SDDM_PID" != "0" ]; then
        _TTY=$(ps -o tty= -p "$SDDM_PID" 2>/dev/null | grep -o '[0-9]*')
        [ -n "$_TTY" ] && SDDM_TTY=$_TTY
    fi
    echo "SDDM is on tty${SDDM_TTY}"

    echo "Monitor: ${WIDTH}x${HEIGHT} @ ${REFRESH}Hz on tty${CURRENT_TTY} (VRR: ${VRR_CAPABLE})"

    printf "WIDTH=%s\nHEIGHT=%s\nREFRESH=%s\nCURRENT_TTY=%s\nVRR_CAPABLE=%s\nSDDM_TTY=%s\n" \
        "$WIDTH" "$HEIGHT" "$REFRESH" "$CURRENT_TTY" "$VRR_CAPABLE" "$SDDM_TTY" > /tmp/gamescope_params

    echo "Escaping into system scope..."
    exec sudo systemd-run --scope --unit="gamescope-toggle-$$" \
        -E HOME="$HOME" \
        -E USER="$USER" \
        -E XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        -E PATH="$PATH" \
        -E GAMESCOPE_ESCAPED=1 \
        --uid="$(id -u)" --gid="$(id -g)" \
        "$0" "$@"
fi

echo "Running in system scope."
trap '' HUP

# -------------------------------------------------------
# Read params saved before the scope escape
# -------------------------------------------------------
source /tmp/gamescope_params
rm -f /tmp/gamescope_params

TTY_DEV="/dev/tty${CURRENT_TTY}"
echo "Monitor: ${WIDTH}x${HEIGHT} @ ${REFRESH}Hz (VRR capable: ${VRR_CAPABLE})"
echo "TTY: tty${CURRENT_TTY} (${TTY_DEV})"
echo "SDDM will return to tty${SDDM_TTY}"

# -------------------------------------------------------
# Write input proxy
# -------------------------------------------------------
cat > /tmp/gamescope_proxy.py << 'PYEOF'
import evdev
from evdev import UInput, ecodes
import os, sys, time, select

LOG = open(os.path.expanduser("~/.gamescope_toggle.log"), "a")

def log(msg):
    LOG.write(msg + "\n")
    LOG.flush()

def find_physical_keyboards():
    keyboards = []
    skip = {'keyd', 'ydotool', 'gamescope', 'uinput', 'virtual', 'avrcp',
            'pc speaker', 'power button', 'sleep button', 'hdmi', 'hda',
            'intel hid', 'consumer control', 'system control'}
    for path in evdev.list_devices():
        try:
            d = evdev.InputDevice(path)
            name_lower = d.name.lower()
            caps = d.capabilities()
            if ecodes.EV_KEY in caps and ecodes.KEY_G in caps[ecodes.EV_KEY]:
                if not any(s in name_lower for s in skip):
                    keyboards.append(d)
                    log(f"Input proxy: will grab {d.name} ({path})")
        except Exception:
            pass
    return keyboards

def main():
    keyboards = []
    for _ in range(20):
        keyboards = find_physical_keyboards()
        if keyboards:
            break
        time.sleep(0.5)

    if not keyboards:
        log("Input proxy: no physical keyboards found!")
        sys.exit(1)

    all_keys = set()
    for kb in keyboards:
        caps = kb.capabilities()
        if ecodes.EV_KEY in caps:
            all_keys.update(caps[ecodes.EV_KEY])

    ui = UInput({ecodes.EV_KEY: list(all_keys)}, name='gamescope-proxy-keyboard')

    grabbed = []
    for kb in keyboards:
        try:
            kb.grab()
            grabbed.append(kb)
            log(f"Input proxy: grabbed {kb.name}")
        except OSError as e:
            log(f"Input proxy: could not grab {kb.name}: {e}")

    if not grabbed:
        log("Input proxy: failed to grab any keyboards!")
        ui.close()
        sys.exit(1)

    log(f"Input proxy: {len(grabbed)} keyboard(s) grabbed, proxy active.")

    meta_held = False
    fds = {kb.fd: kb for kb in grabbed}

    try:
        while True:
            r, _, _ = select.select(fds.keys(), [], [])
            for fd in r:
                try:
                    for event in fds[fd].read():
                        if event.type != ecodes.EV_KEY:
                            ui.write_event(event)
                            ui.syn()
                            continue

                        if event.code in (ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA):
                            meta_held = (event.value != 0)

                        if (meta_held and
                            event.code == ecodes.KEY_G and
                            event.value == 1):
                            log("Input proxy: Super+G detected — killing gamescope.")
                            os.system("pkill -f 'gamescope -W'")
                            os.system("pkill -f gamescopereaper")
                            os.system("pkill -f steam")
                            sys.exit(0)

                        ui.write_event(event)
                        ui.syn()
                except OSError:
                    pass
    finally:
        for kb in grabbed:
            try:
                kb.ungrab()
            except Exception:
                pass
        ui.close()
        log("Input proxy: exited.")

main()
PYEOF

# -------------------------------------------------------
# Ensure gamescope has CAP_SYS_NICE for realtime scheduling.
# This is a one-time setup — skipped if already set.
# Only appropriate for single-user home systems, which is
# the intended use case for this script.
# -------------------------------------------------------
GAMESCOPE_BIN=$(command -v gamescope)
if [ -n "$GAMESCOPE_BIN" ]; then
    if ! getcap "$GAMESCOPE_BIN" 2>/dev/null | grep -q "cap_sys_nice"; then
        echo "Setting CAP_SYS_NICE on gamescope for realtime scheduling..."
        if sudo -n setcap cap_sys_nice+ep "$GAMESCOPE_BIN" 2>/dev/null; then
            echo "CAP_SYS_NICE set successfully."
        else
            echo "Could not set CAP_SYS_NICE (sudo permission missing?) — performance may be affected."
        fi
    else
        echo "CAP_SYS_NICE already set on gamescope."
    fi
fi

# -------------------------------------------------------
# Stop SDDM
# -------------------------------------------------------
echo "Stopping SDDM..."
sudo -n systemctl stop sddm
echo "SDDM stop exit code: $?"

# -------------------------------------------------------
# Kill Hyprland
# -------------------------------------------------------
echo "Killing Hyprland..."
pkill -x Hyprland
for i in $(seq 1 20); do
    pgrep -x Hyprland > /dev/null || break
    sleep 0.5
done
if pgrep -x Hyprland > /dev/null; then
    echo "Hyprland still alive after 10s, sending SIGKILL..."
    pkill -9 -x Hyprland
    sleep 1
fi
echo "Hyprland killed."

# Wait for DRM device to be fully released before proceeding
echo "Waiting for DRM device to be released..."
for i in $(seq 1 20); do
    if ! fuser /dev/dri/card1 > /dev/null 2>&1; then
        echo "DRM device free after ${i} checks."
        break
    fi
    sleep 0.5
done

# -------------------------------------------------------
# Switch to TTY
# -------------------------------------------------------
echo "Switching to ${TTY_DEV}..."
sudo -n chvt "$CURRENT_TTY"
echo "chvt exit code: $?"

# -------------------------------------------------------
# Start seatd
# -------------------------------------------------------
echo "Starting seatd..."
sudo -n seatd -u "$USER" &
SEATD_PID=$!
sleep 1
echo "seatd started (PID $SEATD_PID)"

# -------------------------------------------------------
# Start input proxy BEFORE gamescope
# -------------------------------------------------------
echo "Starting input proxy..."
sudo -n python3 /tmp/gamescope_proxy.py &
PROXY_PID=$!
echo "Input proxy started (PID $PROXY_PID)"
sleep 1

# -------------------------------------------------------
# Build gamescope command.
# --adaptive-sync must be before -- steam.
# STEAM_GAMESCOPE_VRR_SUPPORTED=1 must be before gamescope.
# -------------------------------------------------------
if [ "$VRR_CAPABLE" = "1" ]; then
    echo "VRR supported — enabling adaptive sync."
    GAMESCOPE_CMD="STEAM_GAMESCOPE_VRR_SUPPORTED=1 gamescope -W $WIDTH -H $HEIGHT -r $REFRESH --adaptive-sync -e --backend drm -- steam -gamepadui --force-grab-cursor"
else
    echo "VRR not supported — skipping adaptive sync."
    GAMESCOPE_CMD="gamescope -W $WIDTH -H $HEIGHT -r $REFRESH -e --backend drm -- steam -gamepadui --force-grab-cursor"
fi

# -------------------------------------------------------
# Launch gamescope (blocks until exit)
# -------------------------------------------------------
echo "Launching: $GAMESCOPE_CMD"
unset WAYLAND_DISPLAY
unset DISPLAY
eval "$GAMESCOPE_CMD"
echo "Gamescope exited with code: $?"

# -------------------------------------------------------
# Clean up and restart SDDM
# -------------------------------------------------------
sudo -n kill "$PROXY_PID" 2>/dev/null
sudo -n kill "$SEATD_PID" 2>/dev/null
rm -f /tmp/gamescope_proxy.py
echo "Restarting SDDM..."
sudo -n systemctl start sddm
echo "SDDM start exit code: $?"
echo "Switching back to SDDM on tty${SDDM_TTY}..."
sudo -n chvt "$SDDM_TTY"
