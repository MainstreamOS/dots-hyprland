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
info "Installing SDDM..."
pacman -S --needed --noconfirm sddm
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

    # Apply as active SDDM theme
    mkdir -p /etc/sddm.conf.d
    echo -e "[Theme]\nCurrent=pixie" > /etc/sddm.conf.d/theme.conf

    info "Pixie SDDM theme installed and applied"
else
    warn "Failed to clone pixie-sddm theme. Skipping theme installation."
    warn "You can install it later from: https://github.com/MainstreamOS/pixie-sddm"
fi

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
