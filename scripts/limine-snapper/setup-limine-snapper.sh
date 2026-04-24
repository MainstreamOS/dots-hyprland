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

upsert_shell_setting() {
    local file="$1"
    local key="$2"
    local value="$3"
    local tmpfile
    local line
    local found=false

    tmpfile=$(mktemp)
    if [[ -f "$file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*= ]]; then
                printf '%s=%s\n' "$key" "$value" >> "$tmpfile"
                found=true
            else
                printf '%s\n' "$line" >> "$tmpfile"
            fi
        done < "$file"
    fi
    if ! $found; then
        [[ -s "$tmpfile" ]] && printf '\n' >> "$tmpfile"
        printf '%s=%s\n' "$key" "$value" >> "$tmpfile"
    fi
    install -D -m 644 "$tmpfile" "$file"
    rm -f "$tmpfile"
}

upsert_kernel_cmdline_args() {
    local cmdline_file="/etc/kernel/cmdline"
    local -a new_args=("$@")
    local -a existing=()
    local -a keys=()
    local -a kept=()
    local tmpfile
    local token key skip existing_line

    if [[ -f "$cmdline_file" ]]; then
        existing_line=$(tr '\n' ' ' < "$cmdline_file")
        read -r -a existing <<< "$existing_line"
    elif [[ -r /proc/cmdline ]]; then
        read -r -a existing <<< "$(cat /proc/cmdline)"
    fi

    for token in "${new_args[@]}"; do
        keys+=("${token%%=*}")
    done

    for token in "${existing[@]}"; do
        [[ -z "$token" ]] && continue
        [[ "$token" == BOOT_IMAGE=* ]] && continue
        [[ "$token" == initrd=* ]] && continue
        key="${token%%=*}"
        skip=false
        for existing_key in "${keys[@]}"; do
            if [[ "$key" == "$existing_key" ]]; then
                skip=true
                break
            fi
        done
        $skip || kept+=("$token")
    done

    kept+=("${new_args[@]}")
    tmpfile=$(mktemp)
    printf '%s\n' "${kept[*]}" > "$tmpfile"
    install -D -m 644 "$tmpfile" "$cmdline_file"
    rm -f "$tmpfile"
}

relabel_limine_nvram_entry() {
    # Rename the NVRAM boot entry that `limine-install` registers (hardcoded
    # label "Limine") to a custom label. Scoped to entries whose device path
    # references this ESP's PARTUUID AND our limine_x64.efi loader, so we
    # never touch entries pointing to other disks / partitions.
    #
    # Persistent across upgrades: `limine-install` checks for an existing
    # entry by PARTUUID + loader path, not label, so future runs will leave
    # the renamed entry alone.
    local new_label="$1"
    local esp_path="$2"
    local loader_path="/EFI/limine/limine_x64.efi"

    command -v efibootmgr >/dev/null 2>&1 || { warn "efibootmgr not found — skipping NVRAM relabel."; return 0; }

    local source part_uuid disk part
    source=$(findmnt -n -o SOURCE "$esp_path" 2>/dev/null) || { warn "findmnt failed for $esp_path — skipping NVRAM relabel."; return 0; }
    part_uuid=$(findmnt -n -o PARTUUID "$esp_path" 2>/dev/null) || { warn "PARTUUID lookup failed for $esp_path — skipping NVRAM relabel."; return 0; }
    [[ -n "$part_uuid" ]] || { warn "Empty PARTUUID for $esp_path — skipping NVRAM relabel."; return 0; }

    if [[ "$source" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
        disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$source" =~ ^(/dev/mmcblk[0-9]+)p([0-9]+)$ ]]; then
        disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    elif [[ "$source" =~ ^(/dev/[a-z]+)([0-9]+)$ ]]; then
        disk="${BASH_REMATCH[1]}"; part="${BASH_REMATCH[2]}"
    else
        warn "Could not parse disk/partition from $source — skipping NVRAM relabel."
        return 0
    fi

    local efibootmgr_output
    efibootmgr_output=$(efibootmgr -v 2>/dev/null) || { warn "efibootmgr read failed — skipping NVRAM relabel."; return 0; }

    # If an entry with the target label already points at our PARTUUID, we're done.
    if grep -E "^Boot[0-9A-Fa-f]{4}\*? ${new_label}[[:space:]]" <<< "$efibootmgr_output" | grep -Fqi "$part_uuid"; then
        return 0
    fi

    # Delete any existing entries on this partition that point at our limine loader.
    local line bootnum
    while IFS= read -r line; do
        [[ "$line" =~ ^Boot([0-9A-Fa-f]{4})\* ]] || continue
        bootnum="${BASH_REMATCH[1]}"
        if grep -Fqi "$part_uuid" <<< "$line" && grep -Fqi "limine_x64.efi" <<< "$line"; then
            efibootmgr -b "$bootnum" -B >/dev/null 2>&1 || true
        fi
    done <<< "$efibootmgr_output"

    if efibootmgr --create \
        --disk "$disk" \
        --part "$part" \
        --label "$new_label" \
        --loader "$loader_path" \
        --unicode >/dev/null 2>&1; then
        info "Renamed NVRAM entry to '$new_label' (PARTUUID=$part_uuid)."
    else
        warn "Failed to create '$new_label' NVRAM entry — leaving default 'Limine' label in place."
    fi
}

print_limine_header() {
    cat <<'EOF'
timeout: 5

# Mainstream brand theme (night palette, continuity with plymouth splash)
term_background: 191A1F
term_foreground: c9ccd4
term_background_bright: 2a2b32
term_foreground_bright: ffffff
interface_branding: Mainstream Bootloader
interface_branding_color: 7
term_palette: 20222a;d98888;a3d099;d9c485;008dc3;c799e6;009ca5;c9ccd4
term_palette_bright: 5b5e66;ea9b9b;b7dfac;e5d29f;2aabdf;d6b2f0;1fbac3;ffffff
backdrop: 191A1F
EOF
}

write_limine_header() {
    print_limine_header > "$ESP/limine.conf"
}

ensure_limine_header() {
    local limine_conf="$ESP/limine.conf"
    local tmpfile

    [[ -f "$limine_conf" ]] || return 0
    grep -q '^interface_branding: Mainstream Bootloader$' "$limine_conf" && return 0

    tmpfile=$(mktemp)
    print_limine_header > "$tmpfile"
    printf '\n' >> "$tmpfile"
    cat "$limine_conf" >> "$tmpfile"
    install -m 644 "$tmpfile" "$limine_conf"
    rm -f "$tmpfile"
}

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
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_PART")
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

# Configure the generator-owned Limine setup before we touch any old bootloader.
info "Installing limine entry automation packages..."
if ! command -v limine-mkinitcpio >/dev/null 2>&1 || ! command -v limine-snapper-sync >/dev/null 2>&1; then
    if command -v yay &>/dev/null; then
        sudo -u "${SUDO_USER:-$USER}" yay -S --needed --noconfirm limine-snapper-sync limine-mkinitcpio-hook
    elif command -v paru &>/dev/null; then
        sudo -u "${SUDO_USER:-$USER}" paru -S --needed --noconfirm limine-snapper-sync limine-mkinitcpio-hook
    else
        error "limine-mkinitcpio-hook and limine-snapper-sync are required for the managed Limine setup, but no AUR helper (yay/paru) is available."
    fi
fi
command -v limine-update >/dev/null 2>&1 || error "limine-update not found after installing limine-mkinitcpio-hook."
command -v limine-mkinitcpio >/dev/null 2>&1 || error "limine-mkinitcpio not found after installing limine-mkinitcpio-hook."
command -v limine-snapper-sync >/dev/null 2>&1 || error "limine-snapper-sync not found after installation."

info "Seeding Limine header and generator config..."
write_limine_header
upsert_shell_setting "/etc/default/limine" "TARGET_OS_NAME" '"Mainstream OS\\"'
# Suppress auto-generated top-level entries for systemd-boot, rEFInd, and the
# default EFI loader ($ESP/EFI/BOOT/BOOTX64.EFI is Limine itself here, so the
# "EFI fallback" entry would just chainload Limine back into itself).
upsert_shell_setting "/etc/default/limine" "FIND_BOOTLOADERS" "no"

ROOT_TOKEN="root=UUID=$ROOT_UUID"
if [[ -n "$ROOT_PARTUUID" ]]; then
    ROOT_TOKEN="root=PARTUUID=$ROOT_PARTUUID"
fi
upsert_kernel_cmdline_args \
    "$ROOT_TOKEN" \
    "rootflags=subvol=$ROOT_SUBVOL" \
    "rw" \
    "rootfstype=btrfs" \
    "quiet" \
    "loglevel=0" \
    "systemd.show_status=false" \
    "rd.systemd.show_status=false" \
    "rd.udev.log_level=0" \
    "vt.global_cursor_default=0"

info "Generating Limine boot entries from /etc/default/limine and /etc/kernel/cmdline..."
limine-update
ensure_limine_header
[[ -f "$ESP/limine.conf" ]] || error "Failed to generate $ESP/limine.conf"
grep -q "machine-id=$(tr -d '\n' < /etc/machine-id)" "$ESP/limine.conf" || error "limine-update did not generate a machine-id-targeted OS entry."

relabel_limine_nvram_entry "Mainstream OS" "$ESP"

info "Limine installed and boot entries generated"

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

# --- Step 4: Enable snapshot sync now that Limine is generator-managed ---
systemctl enable --now limine-snapper-sync.service

# --- Step 5: Create initial snapshot ---
info "Creating initial snapshot..."
snapper -c root create --description "Fresh install" --type single
limine-snapper-sync || warn "limine-snapper-sync failed after creating the initial snapshot. You can rerun it manually once the system is up."

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
