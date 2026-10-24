"""Paste Unicode text into the window that opened the picker."""

import argparse
import json
import re
import subprocess
import time


TERMINALS = {
    "alacritty", "foot", "footclient", "ghostty", "com.mitchellh.ghostty",
    "kitty", "wezterm", "org.wezfurlong.wezterm", "wezterm-gui",
    "org.gnome.terminal", "gnome-terminal-server", "org.gnome.console", "kgx",
    "konsole", "org.kde.konsole", "tilix", "xfce4-terminal", "xterm", "uxterm",
}


def hyprctl(*args):
    return subprocess.check_output(["hyprctl", *args], text=True, timeout=2)


def insert_text(text, address):
    # wl-copy returns once it owns the selection. Unicode keysyms from wtype
    # are not accepted consistently by browsers and Electron text editors.
    subprocess.run(["wl-copy", "--type", "text/plain;charset=utf-8"], input=text,
                   text=True, timeout=2, check=True)
    if not re.fullmatch(r"0x[0-9a-fA-F]+", address):
        return False
    windows = json.loads(hyprctl("-j", "clients"))
    window = next((w for w in windows if w.get("address") == address), None)
    if window is None:
        return False

    classes = {window.get(key, "").lower() for key in ("class", "initialClass")}
    tags = {tag.rstrip("*") for tag in window.get("tags", [])}
    mods = "CTRL SHIFT" if classes & TERMINALS or "terminal" in tags else "CTRL"
    selector = "address:" + address
    hyprctl("dispatch", f'hl.dsp.focus({{ window = "{selector}" }})')
    deadline = time.monotonic() + 0.75
    while time.monotonic() < deadline:
        if json.loads(hyprctl("-j", "activewindow")).get("address") == address:
            # Target the original window explicitly; never fall back to typing
            # into whichever app happens to gain focus during the close fade.
            hyprctl("dispatch", f'hl.dsp.send_shortcut({{ mods = "{mods}", key = "v", window = "{selector}" }})')
            return True
        time.sleep(0.02)
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--window", required=True)
    parser.add_argument("text")
    args = parser.parse_args()
    try:
        inserted = insert_text(args.text, args.window)
    except (OSError, ValueError, subprocess.SubprocessError):
        inserted = False
    if not inserted:
        # The emoji remains available on the clipboard if its window closed.
        raise SystemExit("Could not insert text into the original input window.")


if __name__ == "__main__":
    main()
