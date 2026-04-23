#!/usr/bin/env bash
# setup-limine-snapper.sh
# Post-install script for Arch Linux with btrfs
# Sets up limine bootloader + snapper snapshots selectable from boot menu
# Requirements: Fresh Arch install on btrfs with subvolume layout (@, @home, etc.)

set -euo pipefail

# --- Options ---
AUTO_YES=false
if [[ "${1:-}" == "--yes" ]]; then
  AUTO_YES=true
fi

# --- Configuration ---
SNAPPER_SPACE_LIMIT="0.2"       # 20% of drive
SNAPPER_NUMBER_LIMIT="5"        # Max 5 snapshots
ESP="/boot"                     # EFI System Partition mount point

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
[[ -d /sys/firmware/efi ]] || error "System must be booted in UEFI mode"

# Verify btrfs root
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)
[[ "$ROOT_FSTYPE" == "btrfs" ]] || error "Root filesystem must be btrfs (found: $ROOT_FSTYPE)"

# Get root device and subvolume
ROOT_DEV=$(findmnt -n -o SOURCE /)
ROOT_PART=$(findmnt -n -o SOURCE -T / | sed 's/\[.*\]//')
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
ROOT_SUBVOL=$(findmnt -n -o OPTIONS / | grep -oP 'subvol=\K[^,]+')

info "Root device: $ROOT_PART"
info "Root UUID: $ROOT_UUID"
info "Root subvolume: $ROOT_SUBVOL"
info "ESP mount: $ESP"

echo ""
echo -e "${YELLOW}This will:${NC}"
echo "  1. Install limine as the UEFI bootloader"
echo "  2. Remove any existing bootloader (GRUB/systemd-boot) once limine is verified"
echo "  3. Install and configure snapper (20% space, max 5 snapshots)"
echo "  4. Install hooks to auto-generate limine boot entries from snapshots"
echo ""
if [[ "$AUTO_YES" != true ]]; then
  read -rp "Continue? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
fi

# --- Step 1: Install and configure limine FIRST (before removing old bootloader) ---
info "Installing limine..."
pacman -S --needed --noconfirm limine

# Verify limine EFI binary exists
LIMINE_EFI="/usr/share/limine/BOOTX64.EFI"
if [[ ! -f "$LIMINE_EFI" ]]; then
    error "Limine EFI binary not found at $LIMINE_EFI. The limine package may have changed its file layout."
fi

# Detect boot mode: UKI (Unified Kernel Image) or traditional kernel + initramfs
USE_UKI=false
UKI_PATH=""
UKI_FB_PATH=""
KERNEL=""
INITRAMFS=""
INITRAMFS_FB=""

# Check for UKIs first — mkinitcpio on this system may produce .efi bundles
# instead of separate vmlinuz + initramfs files.
# Use direct -f tests instead of ls|head to avoid SIGPIPE/pipefail false negatives.
UKI_PATH=""
UKI_FB_PATH=""
if [[ -f "$ESP/EFI/Linux/arch-linux.efi" ]]; then
    UKI_PATH="$ESP/EFI/Linux/arch-linux.efi"
elif [[ -d "$ESP/EFI/Linux" ]]; then
    while IFS= read -r -d '' _f; do
        [[ "$_f" != *fallback* ]] && { UKI_PATH="$_f"; break; }
    done < <(find "$ESP/EFI/Linux" -maxdepth 1 -name "*.efi" -print0 2>/dev/null)
fi
if [[ -d "$ESP/EFI/Linux" ]]; then
    while IFS= read -r -d '' _f; do
        UKI_FB_PATH="$_f"; break
    done < <(find "$ESP/EFI/Linux" -maxdepth 1 -name "*fallback*.efi" -print0 2>/dev/null)
fi

if [[ -n "$UKI_PATH" ]] && [[ -f "$UKI_PATH" ]]; then
    USE_UKI=true
    info "Unified Kernel Image detected at $UKI_PATH — using EFI boot protocol."
else
    # Traditional: separate kernel + initramfs
    KERNEL=""
    INITRAMFS=""
    INITRAMFS_FB=""
    if [[ -f "$ESP/vmlinuz-linux" ]]; then
        KERNEL="$ESP/vmlinuz-linux"
    else
        KERNEL=$(find "$ESP" -maxdepth 1 -name "vmlinuz-linux*" -print -quit 2>/dev/null || true)
    fi
    INITRAMFS=$(find "$ESP" -maxdepth 1 -name "initramfs-linux*.img" ! -name "*fallback*" -print -quit 2>/dev/null || true)
    INITRAMFS_FB=$(find "$ESP" -maxdepth 1 -name "initramfs-linux*-fallback.img" -print -quit 2>/dev/null || true)

    if [[ -z "$KERNEL" ]]; then
        # Kernel might be at /boot inside root, not on ESP
        if [[ "$ESP" == "/boot" ]] && [[ -f "/boot/vmlinuz-linux" ]]; then
            KERNEL="/boot/vmlinuz-linux"
            INITRAMFS="/boot/initramfs-linux.img"
            INITRAMFS_FB="/boot/initramfs-linux-fallback.img"
        else
            error "Cannot find kernel at $ESP/vmlinuz-linux*. Aborting before any bootloader changes."
        fi
    fi

    [[ -f "$KERNEL" ]] || error "Kernel not found at $KERNEL. Aborting before any bootloader changes."

    # If initramfs is missing, mkinitcpio likely has not run yet — generate it now
    if [[ ! -f "$INITRAMFS" ]]; then
        warn "Initramfs not found at ${INITRAMFS:-<empty>}. Running mkinitcpio -P to generate it..."
        if ! mkinitcpio -P; then
            error "mkinitcpio -P failed. Cannot continue without an initramfs."
        fi
        # Re-detect after generation — use direct -f tests, not ls|head,
        # to avoid SIGPIPE/pipefail false negatives.
        if [[ -f "$ESP/EFI/Linux/arch-linux.efi" ]]; then
            UKI_PATH="$ESP/EFI/Linux/arch-linux.efi"
        elif [[ -d "$ESP/EFI/Linux" ]]; then
            while IFS= read -r -d '' _f; do
                [[ "$_f" != *fallback* ]] && { UKI_PATH="$_f"; break; }
            done < <(find "$ESP/EFI/Linux" -maxdepth 1 -name "*.efi" -print0 2>/dev/null)
        fi
        if [[ -d "$ESP/EFI/Linux" ]]; then
            while IFS= read -r -d '' _f; do
                UKI_FB_PATH="$_f"; break
            done < <(find "$ESP/EFI/Linux" -maxdepth 1 -name "*fallback*.efi" -print0 2>/dev/null)
        fi
        if [[ -n "$UKI_PATH" ]] && [[ -f "$UKI_PATH" ]]; then
            USE_UKI=true
            info "mkinitcpio produced a Unified Kernel Image at $UKI_PATH — switching to EFI boot protocol."
        else
            INITRAMFS=$(find "$ESP" -maxdepth 1 -name "initramfs-linux*.img" ! -name "*fallback*" -print -quit 2>/dev/null || true)
            INITRAMFS_FB=$(find "$ESP" -maxdepth 1 -name "initramfs-linux*-fallback.img" -print -quit 2>/dev/null || true)
            [[ -f "$INITRAMFS" ]] || error "Initramfs still not found after mkinitcpio. Aborting."
            info "Initramfs generated successfully."
        fi
    fi
fi

# Determine kernel cmdline - silent boot (no text on boot/reboot/shutdown)
# Only used in traditional mode; UKI embeds its own cmdline
CMDLINE="root=UUID=$ROOT_UUID rootflags=subvol=$ROOT_SUBVOL rw quiet loglevel=0 systemd.show_status=false rd.systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0"

if [[ -f /etc/kernel/cmdline ]]; then
    EXTRA_ARGS=$(cat /etc/kernel/cmdline | sed "s|root=[^ ]*||g; s|rootflags=[^ ]*||g; s|rw||g; s|quiet||g; s|loglevel=[^ ]*||g; s|systemd\.show_status=[^ ]*||g; s|rd\.systemd\.show_status=[^ ]*||g; s|rd\.udev\.log_level=[^ ]*||g; s|vt\.global_cursor_default=[^ ]*||g" | xargs)
    [[ -n "$EXTRA_ARGS" ]] && CMDLINE="$CMDLINE $EXTRA_ARGS"
fi

# Write limine.conf
info "Writing limine.conf..."
LIMINE_CONF_CONTENT="timeout: 5

# Mainstream brand theme (night palette, continuity with plymouth splash)
term_background: 0b0d12
term_foreground: c9ccd4
term_background_bright: 2a2b32
term_foreground_bright: ffffff
interface_branding: Mainstream Bootloader
interface_branding_color: 7
term_palette: 20222a;d98888;a3d099;d9c485;008dc3;c799e6;009ca5;c9ccd4
term_palette_bright: 5b5e66;ea9b9b;b7dfac;e5d29f;2aabdf;d6b2f0;1fbac3;ffffff
backdrop: 0b0d12"

if $USE_UKI; then
    # UKI mode: cmdline and initramfs are embedded in the .efi bundle
    UKI_REL="${UKI_PATH#$ESP/}"
    LIMINE_CONF_CONTENT+="

/Arch Linux
    protocol: efi
    path: boot():///$UKI_REL"

    if [[ -n "$UKI_FB_PATH" ]] && [[ -f "$UKI_FB_PATH" ]]; then
        UKI_FB_REL="${UKI_FB_PATH#$ESP/}"
        LIMINE_CONF_CONTENT+="

/Arch Linux (Fallback)
    protocol: efi
    path: boot():///$UKI_FB_REL"
    fi
else
    # Traditional mode: separate kernel + initramfs
    KERNEL_BASENAME=$(basename "$KERNEL")
    INITRAMFS_BASENAME=$(basename "$INITRAMFS")
    INITRAMFS_FB_BASENAME=""
    if [[ -n "$INITRAMFS_FB" ]] && [[ -f "$INITRAMFS_FB" ]]; then
        INITRAMFS_FB_BASENAME=$(basename "$INITRAMFS_FB")
    fi

    LIMINE_CONF_CONTENT+="

/Arch Linux
    protocol: linux
    kernel_path: boot():///$KERNEL_BASENAME
    kernel_cmdline: $CMDLINE
    module_path: boot():///$INITRAMFS_BASENAME"

    if [[ -n "$INITRAMFS_FB_BASENAME" ]]; then
        LIMINE_CONF_CONTENT+="

/Arch Linux (Fallback)
    protocol: linux
    kernel_path: boot():///$KERNEL_BASENAME
    kernel_cmdline: $CMDLINE
    module_path: boot():///$INITRAMFS_FB_BASENAME"
    fi
fi

LIMINE_CONF_CONTENT+="

# --- Snapper Snapshots (auto-generated below) ---
# SNAPPER_ENTRIES_START
# SNAPPER_ENTRIES_END"

echo "$LIMINE_CONF_CONTENT" > "$ESP/limine.conf"

# Verify config was written
[[ -f "$ESP/limine.conf" ]] || error "Failed to write limine.conf"

# Install limine EFI binary
install -Dm644 "$LIMINE_EFI" "$ESP/EFI/BOOT/BOOTX64.EFI"
install -Dm644 "$LIMINE_EFI" "$ESP/EFI/limine/BOOTX64.EFI"

# Verify EFI binary was installed
[[ -f "$ESP/EFI/BOOT/BOOTX64.EFI" ]] || error "Failed to install limine EFI binary"

info "Limine installed and configured"

# --- Step 2: Now safe to remove old bootloaders ---
info "Removing old bootloaders..."

if pacman -Qi grub &>/dev/null; then
    pacman -Rns --noconfirm grub 2>/dev/null || true
    rm -rf "$ESP/grub" 2>/dev/null || true
    rm -f "$ESP/EFI/BOOT/grubx64.efi" 2>/dev/null || true
    info "Removed GRUB"
fi

if bootctl is-installed &>/dev/null 2>&1; then
    bootctl remove 2>/dev/null || true
    info "Removed systemd-boot"
fi

# --- Step 3: Install and configure snapper ---
info "Installing snapper..."
pacman -S --needed --noconfirm snapper snap-pac

# If /.snapshots is already a subvolume mounted, unmount and remove for snapper to manage
if findmnt /.snapshots &>/dev/null; then
    umount /.snapshots 2>/dev/null || true
fi

if btrfs subvolume show /.snapshots &>/dev/null 2>&1; then
    btrfs subvolume delete /.snapshots 2>/dev/null || true
fi
rmdir /.snapshots 2>/dev/null || true

# Create snapper config for root
if snapper -c root list &>/dev/null 2>&1; then
    warn "Snapper config 'root' already exists, reconfiguring..."
else
    snapper -c root create-config /
fi

# snapper creates its own .snapshots subvolume, but we may want to manage it ourselves
# For snapshot booting, we need /.snapshots accessible

# Configure snapper limits
info "Configuring snapper (20% space limit, max 5 snapshots)..."
snapper -c root set-config "SPACE_LIMIT=$SNAPPER_SPACE_LIMIT"
snapper -c root set-config "NUMBER_LIMIT=$SNAPPER_NUMBER_LIMIT"
snapper -c root set-config "NUMBER_LIMIT_IMPORTANT=$SNAPPER_NUMBER_LIMIT"

# Timeline snapshots - enable with conservative settings
snapper -c root set-config "TIMELINE_CREATE=yes"
snapper -c root set-config "TIMELINE_CLEANUP=yes"
snapper -c root set-config "TIMELINE_MIN_AGE=1800"
snapper -c root set-config "TIMELINE_LIMIT_HOURLY=2"
snapper -c root set-config "TIMELINE_LIMIT_DAILY=3"
snapper -c root set-config "TIMELINE_LIMIT_WEEKLY=0"
snapper -c root set-config "TIMELINE_LIMIT_MONTHLY=0"
snapper -c root set-config "TIMELINE_LIMIT_YEARLY=0"

# Enable snapper timers
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

info "Snapper configured"

# --- Step 4: Install limine-snapper sync and mkinitcpio hook ---
info "Installing limine-snapper-sync and limine-mkinitcpio-hook..."
if command -v yay &>/dev/null; then
    sudo -u "${SUDO_USER:-$USER}" yay -S --needed --noconfirm limine-snapper-sync limine-mkinitcpio-hook
elif command -v paru &>/dev/null; then
    sudo -u "${SUDO_USER:-$USER}" paru -S --needed --noconfirm limine-snapper-sync limine-mkinitcpio-hook
else
    warn "No AUR helper (yay/paru) found. Please install limine-snapper-sync and limine-mkinitcpio-hook manually."
fi
systemctl enable --now limine-snapper-sync.service

# --- Step 5: Create initial snapshot ---
info "Creating initial snapshot..."
snapper -c root create --description "Fresh install" --type single

info "Setup complete!"
echo ""
echo -e "${GREEN}Summary:${NC}"
echo "  Bootloader: limine (UEFI)"
echo "  Snapshots:  snapper (root config)"
echo "  Space limit: 20% of drive"
echo "  Max snapshots: 5"
echo "  Config: $ESP/limine.conf"
echo ""
echo "  Snapshot boot entries are managed automatically by limine-snapper-sync."
echo "  snap-pac triggers snapshots on package installs/removals."
echo ""
echo "  Run 'snapper -c root list' to view snapshots"
echo "  Run 'snapper -c root create -d \"description\"' to create a manual snapshot"
