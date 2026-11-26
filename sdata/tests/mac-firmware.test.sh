#!/usr/bin/env bash
# mac-firmware.test.sh: mainstream-mac-firmware reads the firmware from an
# on-disk macOS volume before it downloads Apple's recovery image. 7-Zip, the
# disks and the network are stand-ins; the firmware conversion runs for real.
# Writes only under a temporary directory.
# Run: bash sdata/tests/mac-firmware.test.sh   (exit 0 = all green)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/sdata/mac/mainstream-mac-firmware"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

FAILS=0; CASES=0
chk() { CASES=$((CASES + 1)); if [[ "$2" != "$3" ]]; then echo "  FAIL [$1]: got '$2' want '$3'"; FAILS=$((FAILS + 1)); fi; }
exists() { [[ -e "$1" ]] && echo yes || echo no; }

# A macOS firmware tree as 7-Zip would pull it off the System volume.
mkdir -p "$T/fixture/wifi/C-4364__s-B2"
printf 'TRX' > "$T/fixture/wifi/C-4364__s-B2/kauai.trx"
printf 'CLM' > "$T/fixture/wifi/C-4364__s-B2/kauai.clmb"
printf 'TXC' > "$T/fixture/wifi/C-4364__s-B2/kauai.txcb"
printf 'boardtype=0x0814\nmacaddr=00:90:4c:0d:f4:3e\n' > "$T/fixture/wifi/C-4364__s-B2/P-kauai_M-HRPN_V-u__m-7.5.txt"
# One that cannot be converted: the nvram parser refuses a line without "=".
cp -r "$T/fixture" "$T/broken"
printf 'not nvram\n' > "$T/broken/wifi/C-4364__s-B2/P-kauai_M-HRPN_V-u__m-7.5.txt"

# Partitions: what each holds decides what the fake 7-Zip shows.
mkdir -p "$T/dev"
echo macos > "$T/dev/macos"; echo empty > "$T/dev/empty"; echo broken > "$T/dev/broken"
echo macos > "$T/dev/macos-by-type"
echo macos > "$T/dev/usb-macos"
echo macos > "$T/dev/loop-macos"

mkdir -p "$T/bin"
cat > "$T/bin/7z" <<SH
#!/bin/sh
echo "\$*" >> "$T/7z.log"
cmd="\$1"; out=""; dev=""
for a in "\$@"; do
    case "\$a" in -o*) out="\${a#-o}" ;; $T/dev/*) dev="\$a" ;; esac
done
kind="\$(cat "\$dev" 2>/dev/null)"
case "\$cmd:\$kind" in
    l:macos|l:broken)
        printf 'Path = %s\n\nPath = Volume1/usr/standalone/firmware\n\nPath = Volume1/usr/share/firmware\n\nPath = Volume1/usr/share/firmware/wifi\n' "\$dev" ;;
    l:*) printf 'Path = %s\n' "\$dev" ;;
    x:macos)  mkdir -p "\$out/Volume1/usr/share" && cp -r "$T/fixture" "\$out/Volume1/usr/share/firmware" ;;
    x:broken) mkdir -p "\$out/Volume1/usr/share" && cp -r "$T/broken" "\$out/Volume1/usr/share/firmware" ;;
esac
exit 0
SH
cat > "$T/bin/lsblk" <<SH
#!/bin/sh
case "\$*" in
    *TRAN*) printf '%s\n' 'NAME="nvme0n1" TYPE="disk" RM="0" TRAN="nvme"' \
        'NAME="sdb" TYPE="disk" RM="1" TRAN="usb"' 'NAME="loop0" TYPE="loop" RM="0" TRAN=""' ;;
    *PKNAME*) printf '%s\n' \
        'PATH="/dev/nvme0n1p1" FSTYPE="vfat" PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" PKNAME="nvme0n1"' \
        'PATH="$T/dev/empty" FSTYPE="apfs" PARTTYPE="" PKNAME="nvme0n1"' \
        'PATH="/dev/nvme0n1p3" FSTYPE="" PARTTYPE="" PKNAME="nvme0n1"' \
        'PATH="$T/dev/macos-by-type" FSTYPE="" PARTTYPE="7C3457EF-0000-11AA-AA11-00306543ECAC" PKNAME="nvme0n1"' \
        'PATH="$T/dev/usb-macos" FSTYPE="apfs" PARTTYPE="" PKNAME="sdb"' \
        'PATH="$T/dev/loop-macos" FSTYPE="apfs" PARTTYPE="" PKNAME="loop0"' ;;
esac
SH
# No network, so a run that does not find the firmware on the disk stops at the download.
printf '#!/bin/sh\nexit 1\n' > "$T/bin/ip"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/systemctl"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/logger"
chmod +x "$T/bin/"*

# A fresh machine: $1 names it; the rest of the arguments go to the script.
OUT=""; RC=0
run() {
    local name="$1"; shift
    R="$T/$name"
    mkdir -p "$R/fw"
    OUT="$(PATH="$T/bin:$PATH" PYTHONDONTWRITEBYTECODE=1 \
        MAC_FIRMWARE_LIB="$REPO/sdata/mac" MAC_FIRMWARE_MAC_LIB="$T/no-mac-lib" \
        MAC_FIRMWARE_DIR="$R/fw" MAC_FIRMWARE_WORKDIR="$R/work" MAC_FIRMWARE_CACHE="$R/cache" \
        bash "$SCRIPT" "$@" 2>&1)"
    RC=$?
}
installed() { [[ -e "$R/fw/brcm/brcmfmac4364b2-pcie.apple,kauai.bin" && -e "$R/fw/brcm/.mainstream-mac-firmware" ]] && echo yes || echo no; }

# 1. macOS on the disk: its firmware goes in, with no network and no download.
MAC_FIRMWARE_APFS_DEVICES="$T/dev/empty $T/dev/macos" run volume
chk volume-rc "$RC" 0
chk volume-installed "$(installed)" yes
chk volume-said "$(grep -c 'Reading the firmware from the macOS volume on' <<<"$OUT")" 1
chk volume-no-download "$(grep -c 'No network yet' <<<"$OUT")" 0
chk volume-read-only-firmware "$(grep -c -- '-tAPFS -r -- .* firmware$' "$T/7z.log")" 2
chk volume-extract-path "$(grep -c -- "-tAPFS -o.* -r -- $T/dev/macos Volume1/usr/share/firmware$" "$T/7z.log")" 1
chk volume-cache-cleared "$(exists "$R/cache")" no

# 2. No macOS anywhere: the download is next, and the disk is not searched again.
: > "$T/7z.log"
MAC_FIRMWARE_APFS_DEVICES="$T/dev/empty" run no-volume
chk no-volume-rc "$RC" 0
chk no-volume-offline "$(grep -c 'No network yet' <<<"$OUT")" 1
chk no-volume-nothing "$(installed)" no
chk no-volume-marked "$(exists "$R/cache/no-macos-volume")" yes
: > "$T/7z.log"
MAC_FIRMWARE_APFS_DEVICES="$T/dev/macos" run no-volume --quiet
chk no-volume-not-again "$(wc -l < "$T/7z.log" | tr -d ' ')" 0

# 3. The partitions come from lsblk, by filesystem or by partition type.
: > "$T/7z.log"
unset MAC_FIRMWARE_APFS_DEVICES
run lsblk
chk lsblk-installed "$(installed)" yes
chk lsblk-by-fstype "$(grep -c "$T/dev/empty" "$T/7z.log")" 1
chk lsblk-by-parttype "$(grep -c "$T/dev/macos-by-type" "$T/7z.log")" 2
chk lsblk-not-other "$(grep -c '/dev/nvme0n1p' "$T/7z.log")" 0
# A USB stick or a loop image is never read, even with macOS on it.
chk lsblk-not-usb "$(grep -c "$T/dev/usb-macos" "$T/7z.log")" 0
chk lsblk-not-loop "$(grep -c "$T/dev/loop-macos" "$T/7z.log")" 0

# 4. Firmware on the disk that cannot be prepared: the run fails, and the next
#    one downloads instead of reading it again.
: > "$T/7z.log"
MAC_FIRMWARE_APFS_DEVICES="$T/dev/broken" run broken
chk broken-rc "$RC" 1
chk broken-marked "$(exists "$R/cache/no-macos-volume")" yes
: > "$T/7z.log"
MAC_FIRMWARE_APFS_DEVICES="$T/dev/broken" run broken
chk broken-downloads-next "$(grep -c 'No network yet' <<<"$OUT") $(wc -l < "$T/7z.log" | tr -d ' ')" "1 0"

# 5. --from-volume reads that partition only, even past the marker, and never downloads.
: > "$T/7z.log"
MAC_FIRMWARE_APFS_DEVICES="$T/dev/macos" run named --from-volume "$T/dev/empty"
chk named-empty-rc "$RC" 1
chk named-empty-said "$(grep -c "No macOS firmware found on $T/dev/empty" <<<"$OUT")" 1
chk named-empty-only "$(grep -c "$T/dev/macos" "$T/7z.log")" 0
mkdir -p "$T/named/cache"; : > "$T/named/cache/no-macos-volume"
run named --from-volume "$T/dev/macos"
chk named-rc "$RC" 0
chk named-installed "$(installed)" yes

if [[ $FAILS -eq 0 ]]; then echo "mac_firmware: all $CASES cases PASS"; exit 0
else echo "mac_firmware: $FAILS assertion(s) FAILED across $CASES cases"; exit 1; fi
