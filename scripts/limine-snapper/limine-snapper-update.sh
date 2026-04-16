#!/usr/bin/env bash
# limine-snapper-update.sh
# Generates limine boot entries from snapper snapshots
# Installed to /usr/local/bin/limine-snapper-update

set -euo pipefail

ESP="/boot"
LIMINE_CONF="$ESP/limine.conf"
SNAPPER_CONFIG="root"
SNAPSHOT_DIR="/.snapshots"

[[ $EUID -eq 0 ]] || { echo "Error: must be run as root"; exit 1; }
[[ -f "$LIMINE_CONF" ]] || { echo "Error: $LIMINE_CONF not found"; exit 1; }

# Get root partition info
ROOT_PART=$(findmnt -n -o SOURCE -T / | sed 's/\[.*\]//')
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
ROOT_SUBVOL=$(findmnt -n -o OPTIONS / | grep -oP 'subvol=\K[^,]+')

# Get kernel cmdline base (without root/rootflags)
BASE_CMDLINE=$(grep -m1 'kernel_cmdline:' "$LIMINE_CONF" | sed 's/.*kernel_cmdline: //' | sed "s|root=[^ ]*||g; s|rootflags=[^ ]*||g" | xargs)

# Get kernel/initramfs names from existing config
KERNEL_PATH=$(grep -m1 'kernel_path:' "$LIMINE_CONF" | sed 's/.*kernel_path: //')
INITRAMFS_PATH=$(grep -m1 'module_path:' "$LIMINE_CONF" | sed 's/.*module_path: //')

# Build snapshot entries
ENTRIES=""

if snapper -c "$SNAPPER_CONFIG" list --columns number,date,description 2>/dev/null | tail -n +4 | head -n -0 > /dev/null 2>&1; then
    while IFS='|' read -r num date desc; do
        num=$(echo "$num" | xargs)
        date=$(echo "$date" | xargs)
        desc=$(echo "$desc" | xargs)

        # Skip snapshot 0 (current system)
        [[ "$num" == "0" ]] && continue
        [[ -z "$num" ]] && continue

        # Verify snapshot subvolume exists
        SNAP_SUBVOL="${SNAPSHOT_DIR}/${num}/snapshot"
        [[ -d "$SNAP_SUBVOL" ]] || continue

        # Determine the btrfs subvolume path for this snapshot
        # Snapper snapshots are at @snapshots/N/snapshot relative to btrfs root
        SNAP_BTRFS_PATH="@snapshots/${num}/snapshot"

        SNAP_CMDLINE="root=UUID=$ROOT_UUID rootflags=subvol=$SNAP_BTRFS_PATH,ro $BASE_CMDLINE"

        ENTRIES+="
/Snapshot $num: $desc ($date)
    protocol: linux
    kernel_path: boot():///${KERNEL_PATH##*:///}
    kernel_cmdline: $SNAP_CMDLINE
    module_path: boot():///${INITRAMFS_PATH##*:///}
"
    done < <(snapper -c "$SNAPPER_CONFIG" list --columns number,date,description 2>/dev/null | tail -n +4)
fi

# Replace entries between markers in limine.conf
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

awk -v entries="$ENTRIES" '
    /^# SNAPPER_ENTRIES_START/ {
        print
        print entries
        skip = 1
        next
    }
    /^# SNAPPER_ENTRIES_END/ {
        skip = 0
    }
    !skip { print }
' "$LIMINE_CONF" > "$TMPFILE"

cp "$TMPFILE" "$LIMINE_CONF"

# Count entries
SNAP_COUNT=$(snapper -c "$SNAPPER_CONFIG" list 2>/dev/null | tail -n +4 | grep -cv '^$') || SNAP_COUNT=0
echo "limine-snapper: Updated $LIMINE_CONF with $((SNAP_COUNT > 0 ? SNAP_COUNT - 1 : 0)) snapshot entries"
