#!/usr/bin/env bash
# Marks this system's OS entry in limine.conf with its machine ID, which is how
# limine-entry-tool finds its own entry whatever it is called. An entry another
# installer wrote, as CachyOS's does, lacks the mark, so renaming TARGET_OS_NAME
# would start a second entry beside it on the same files, and the next rebuild
# would leave the old entry's checksums stale. Run as root, before the rename.
set -uo pipefail
export LC_ALL=C
ESP=${MAINSTREAM_ESP-}
[[ -n $ESP ]] || ESP=$(source /usr/lib/limine/limine-common-functions >/dev/null 2>&1 \
    && load_config >/dev/null 2>&1 && printf '%s' "$ESP_PATH")
CONF=$ESP/limine.conf
MACHINE_ID=${MAINSTREAM_MACHINE_ID:-$(cat /etc/machine-id 2>/dev/null)}
MACHINE_ID=${MACHINE_ID,,}
LOCK=${MAINSTREAM_BOOT_LOCK:-/run/lock/boot-partition.lock}
[[ -n $ESP && -f $CONF && $MACHINE_ID =~ ^[0-9a-f]{32}$ ]] || exit 0

# The header line of the one top-level entry that boots this system's own files,
# while no entry carries the mark. Nothing when there is no such entry or more than one.
unmarked_entry() {
    awk -v id="$MACHINE_ID" '
        index(tolower($0), "machine-id=" id) { marked = 1 }
        /^[ \t]*\/[^\/]/ { top = NR }
        top && tolower($0) ~ /^[ \t]*(path|kernel_path|module_path|image_path)[ \t]*:[ \t]*\$?boot\(\):\// {
            p = tolower($0); sub(/^[^:]*:[ \t]*\$?boot\(\):\/+/, "", p)
            if ((index(p, id "/") == 1 && p !~ /\/limine_history\//) || index(p, "efi/linux/" id "_") == 1) own[top] = 1
        }
        END {
            if (marked) exit
            for (t in own) { n++; line = t }
            if (n == 1) print line
        }' "$CONF"
}

mkdir -p "${LOCK%/*}"
exec 9>"$LOCK"
flock -w 60 9 || { echo "The boot partition stayed busy; this system's boot menu entry was not marked."; exit 0; }
line=$(unmarked_entry)
[[ -n $line ]] || exit 0
# The same reset and enroll limine-entry-tool runs around its own saves.
if ! command -v limine-reset-enroll >/dev/null 2>&1 || limine-reset-enroll >/dev/null 2>&1; then
    tmp=$CONF.mainstream-new
    if awk -v at="$line" -v mark="    comment: machine-id=$MACHINE_ID" '{ print } NR == at { print mark }' "$CONF" >"$tmp" \
        && sync -f "$tmp" && mv -f "$tmp" "$CONF"; then
        sync -f "$CONF"
        echo "Marked this system's boot menu entry with its machine ID, so renaming it keeps a single entry."
    else
        rm -f "$tmp"
        echo "warning: could not mark this system's entry in $CONF; the EFI partition may be full."
    fi
fi
if command -v limine-enroll-config >/dev/null 2>&1; then
    limine-enroll-config >/dev/null 2>&1 \
        || echo "warning: limine-enroll-config failed; run it again before restarting."
fi
exit 0
