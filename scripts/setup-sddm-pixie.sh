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
# (see sdata/sddm/10-wayland.conf).
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
# The drop-in lives in the repo so updatems-system and the image install the
# same file. It names the theme too, so the Wayland session is configured even
# if the theme clone failed.
info "Configuring the SDDM Wayland greeter..."
SDDM_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sdata/sddm"
install -Dm644 "$SDDM_SRC/10-wayland.conf" /etc/sddm.conf.d/10-wayland.conf

# Lua, not .conf: 0.56.1 shows a deprecation notice on any .conf config, and the
# greeter is the first thing anyone sees. The format goes away in 0.57.
# updatems-system installs the same file, so it lives in the repo rather than in
# a heredoc here — two copies of a login-screen config is one too many.

mkdir -p /var/lib/sddm/.config/hypr
GREETER_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sdata/sddm/hyprland.lua"
if [[ -f "$GREETER_SRC" ]]; then
    install -m600 "$GREETER_SRC" /var/lib/sddm/.config/hypr/hyprland.lua
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
# The greeter's layout picker cannot run hyprctl from QML; this script does the
# switching for it and is started from the greeter config installed above.
BRIDGE_SRC="$(dirname "$GREETER_SRC")/pixie-sddm-keyboard-bridge.sh"
if [[ -f "$BRIDGE_SRC" ]]; then
    install -m755 "$BRIDGE_SRC" /usr/local/bin/pixie-sddm-keyboard-bridge.sh
    # The bridge and the greeter meet in a directory under /run that root
    # creates at boot; created now as well so the next login does not wait
    # for a reboot.
    install -m644 "$(dirname "$GREETER_SRC")/mainstream-greeter.conf" /usr/lib/tmpfiles.d/mainstream-greeter.conf
    systemd-tmpfiles --create mainstream-greeter.conf || warn "Greeter runtime directory not created; it will exist after a reboot"
else
    warn "Keyboard bridge missing at $BRIDGE_SRC; the login screen's layout picker will draw but do nothing"
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
