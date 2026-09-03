#!/usr/bin/env bash
# Applies an input source picked in Settings. Everything it writes is the
# user's own configuration; root appears only when the engine package has
# to be installed, through one pkexec prompt.
set -u
engine="${1:-}"

pkg=""
case "$engine" in
    none) ;;
    mozc)   pkg=fcitx5-mozc ;;
    pinyin) pkg=fcitx5-chinese-addons ;;
    hangul) pkg=fcitx5-hangul ;;
    unikey) pkg=fcitx5-unikey ;;
    *) echo "unknown input source: $engine" >&2; exit 2 ;;
esac

layout=$(hyprctl -j getoption input:kb_layout 2>/dev/null | grep -oP '"str":\s*"\K[^",]+' | cut -d, -f1)
[[ -z "$layout" ]] && layout=us

profile="$HOME/.config/fcitx5/profile"
mkdir -p "$HOME/.config/fcitx5"

if [[ "$engine" == none ]]; then
    cat > "$profile" <<EOF
[Groups/0]
Name=Default
Default Layout=$layout
DefaultIM=keyboard-$layout

[Groups/0/Items/0]
Name=keyboard-$layout
Layout=

[GroupOrder]
0=Default
EOF
    pkill -x fcitx5 2>/dev/null
    echo "plain keyboard"
    exit 0
fi

if ! pacman -Q "$pkg" &>/dev/null; then
    pkexec pacman -S --needed --noconfirm fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt "$pkg" || exit 1
fi

# The input method is only reachable once these two files carry it, so a
# machine that never got them seeded is given them here rather than quietly
# skipped: the profile below would otherwise be written, the script would
# report success, and no application would take input.
env_lua="$HOME/.config/hypr/custom/env.lua"
mkdir -p "$(dirname "$env_lua")" || exit 1
if [[ ! -f "$env_lua" ]]; then
    printf -- '-- Put extra environment variables here\n-- https://wiki.hypr.land/Configuring/Environment-variables/\n\n' > "$env_lua" || exit 1
fi
if ! grep -q 'im=fcitx' "$env_lua"; then
    cat >> "$env_lua" <<'EOF'
hl.env({ name = "XMODIFIERS", value = "@im=fcitx" })
hl.env({ name = "QT_IM_MODULE", value = "fcitx" })
hl.env({ name = "QT_IM_MODULES", value = "wayland;fcitx" })
hl.env({ name = "SDL_IM_MODULE", value = "fcitx" })
hl.env({ name = "GLFW_IM_MODULE", value = "ibus" })
EOF
fi
execs_lua="$HOME/.config/hypr/custom/execs.lua"
if [[ ! -f "$execs_lua" ]]; then
    printf -- '-- Custom auto-start commands\n-- https://wiki.hypr.land/Configuring/Keywords/#executing\n\n' > "$execs_lua" || exit 1
fi
if ! grep -q 'fcitx5' "$execs_lua"; then
    echo 'hl.on("hyprland.start", function() hl.exec_cmd("fcitx5 -d") end)' >> "$execs_lua"
fi
for gtkv in gtk-3.0 gtk-4.0; do
    ini="$HOME/.config/$gtkv/settings.ini"
    if [[ -f "$ini" ]]; then
        grep -q '^gtk-im-module=' "$ini" || sed -i '/^\[Settings\]/a gtk-im-module=fcitx' "$ini"
    else
        mkdir -p "$HOME/.config/$gtkv"
        printf '[Settings]\ngtk-im-module=fcitx\n' > "$ini"
    fi
done

cat > "$profile" <<EOF
[Groups/0]
Name=Default
Default Layout=$layout
DefaultIM=$engine

[Groups/0/Items/0]
Name=keyboard-$layout
Layout=

[Groups/0/Items/1]
Name=$engine
Layout=

[GroupOrder]
0=Default
EOF

pkill -x fcitx5 2>/dev/null
sleep 0.3
fcitx5 -d &>/dev/null &
echo "$engine"
