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

mkdir -p /var/lib/sddm/.config/hypr
cat > /var/lib/sddm/.config/hypr/hyprland.conf <<'HYPREOF'
monitor=,preferred,auto,1

misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
    force_default_wallpaper = 0
}

animations {
    enabled = false
}

windowrule = match:class ^(sddm-greeter-qt6)$, fullscreen on
HYPREOF
chown -R sddm:sddm /var/lib/sddm
chmod 700 /var/lib/sddm/.config
chmod 700 /var/lib/sddm/.config/hypr
chmod 600 /var/lib/sddm/.config/hypr/hyprland.conf
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
