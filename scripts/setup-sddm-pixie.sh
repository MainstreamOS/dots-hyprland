#!/usr/bin/env bash
# setup-sddm-pixie.sh
# Installs SDDM and the pixie-sddm theme

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# `./setup install` normally runs in visual mode, where a failing helper is
# retried but its shell line is not shown in the install log.  Keep the normal
# command error on stderr and add the exact source location as well, so this
# script never degenerates into a bare "rc=1" again.
report_error() {
    local rc=$?
    printf '%b[ERROR]%b setup-sddm-pixie.sh failed at line %s: %s (exit %d)\n' \
        "$RED" "$NC" "${BASH_LINENO[0]:-$LINENO}" "$BASH_COMMAND" "$rc" >&2
    exit "$rc"
}
trap report_error ERR

# --- Checks ---
[[ $EUID -eq 0 ]] || error "This script must be run as root"

# --- Step 1: Install SDDM ---
# layer-shell-qt is required by the Qt6 SDDM greeter when it runs under Wayland
# (GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell, set below).
info "Installing SDDM..."
pacman -S --needed --noconfirm sddm layer-shell-qt
systemctl enable sddm
info "SDDM installed and enabled"

# --- Step 2: Install pixie-sddm theme ---
info "Installing pixie-sddm theme..."

PIXIE_TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$PIXIE_TMPDIR"; }
trap cleanup EXIT

if git clone https://github.com/MainstreamOS/pixie-sddm.git "$PIXIE_TMPDIR" 2>/dev/null; then
    PIXIE_THEME_DIR="/usr/share/sddm/themes/pixie"
    rm -rf "$PIXIE_THEME_DIR" 2>/dev/null || true
    mkdir -p "$PIXIE_THEME_DIR"
    cp -r "$PIXIE_TMPDIR"/{assets,components,Main.qml,metadata.desktop,theme.conf,LICENSE} "$PIXIE_THEME_DIR/"
    chmod -R 755 "$PIXIE_THEME_DIR"

    info "Pixie SDDM theme installed"
else
    warn "Failed to clone pixie-sddm theme. Skipping theme installation."
    warn "You can install it later from: https://github.com/MainstreamOS/pixie-sddm"
fi

# --- Step 2b: SDDM Wayland greeter (run the greeter under Hyprland/Wayland) ---
# sddm-greeter-qt6 uses layer-shell via QT_WAYLAND_SHELL_INTEGRATION; start-hyprland
# ships with the hyprland package. The theme is set here (not in the pixie block
# above) so the Wayland session is configured even if the theme clone failed.
info "Configuring the SDDM Wayland greeter..."
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/10-wayland.conf <<'SDDMEOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=start-hyprland

[Theme]
Current=pixie
SDDMEOF

# Lua, not .conf: 0.56.1 shows a deprecation notice on any .conf config, and the
# greeter is the first thing anyone sees. The format goes away in 0.57.
# updatems-system installs the same file, so it lives in the repo rather than in
# a heredoc here — two copies of a login-screen config is one too many.

# The repo copy of the greeter config carries no keyboard layout: the machine
# does. The installer appends the recorded layout to this file at first boot,
# and a pristine refresh would silently send a non-US greeter back to QWERTY,
# locking the password box to letters the keyboard does not have.
reseed_greeter_layout() {
    local target="$1" x11="/etc/X11/xorg.conf.d/00-keyboard.conf" layout="" variant=""
    if [[ -f "$x11" ]]; then
        # No match is normal on machines whose localed file has not been
        # populated yet. With `set -e -o pipefail`, make that an empty value
        # rather than an unexplained installer failure.
        layout=$(grep -oP 'Option\s+"XkbLayout"\s+"\K[^"]+' "$x11" 2>/dev/null | head -1 || true)
        variant=$(grep -oP 'Option\s+"XkbVariant"\s+"\K[^"]*' "$x11" 2>/dev/null | head -1 || true)
    fi
    if [[ -z "$layout" && -f /etc/vconsole.conf ]]; then
        layout=$(grep -oP '^KEYMAP=\K.*' /etc/vconsole.conf 2>/dev/null | tr -d '"' | head -1 || true)
        layout="${layout%%-*}"
    fi
    [[ -n "$layout" ]] || return 0
    [[ "$layout" =~ ^[a-z]{2,8}(,[a-z]{2,8})*$ ]] || return 0
    [[ "$variant" =~ ^[a-z0-9_]*(,[a-z0-9_]*)*$ ]] || variant=""
    {
        printf '\nhl.config({\n    input = {\n        kb_layout = "%s",\n' "$layout"
        [[ -n "$variant" ]] && printf '        kb_variant = "%s",\n' "$variant"
        printf '    },\n})\n'
    } >> "$target"
}

mkdir -p /var/lib/sddm/.config/hypr
GREETER_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sdata/sddm/hyprland.lua"
if [[ -f "$GREETER_SRC" ]]; then
    install -m600 "$GREETER_SRC" /var/lib/sddm/.config/hypr/hyprland.lua
    reseed_greeter_layout /var/lib/sddm/.config/hypr/hyprland.lua
    # Moved aside rather than removed: lua is found before conf, so the new file
    # already wins, and keeping the old one means a greeter that will not start
    # can be put back by renaming one file.
    if [[ -f /var/lib/sddm/.config/hypr/hyprland.conf ]]; then
        mv /var/lib/sddm/.config/hypr/hyprland.conf \
            /var/lib/sddm/.config/hypr/hyprland.conf.old
    fi
else
    warn "Greeter config missing at $GREETER_SRC — leaving the existing one alone"
fi
chown -R sddm:sddm /var/lib/sddm
chmod 700 /var/lib/sddm/.config
chmod 700 /var/lib/sddm/.config/hypr
info "SDDM Wayland greeter configured"

# --- Step 3: Configure silent boot/reboot/shutdown ---
info "Configuring silent boot (no verbose text)..."

# Suppress systemd startup/shutdown messages
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/silent-boot.conf <<'SILENT_EOF'
[Manager]
ShowStatus=no
SILENT_EOF

# Suppress getty login prompt messages on TTY
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/silent.conf <<'GETTY_EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --skip-login --nonewline --noissue --noclear --login-options "-f root" %I $TERM
GETTY_EOF

# Suppress fsck messages during boot
if [[ ! -f /etc/sysctl.d/20-quiet-printk.conf ]]; then
    echo "kernel.printk = 3 3 3 3" > /etc/sysctl.d/20-quiet-printk.conf
fi

info "Silent boot configured"
