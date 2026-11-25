#!/usr/bin/env bash
# app-variants.test.sh: the app source swap against the shipped list and a
# missing one.
# Run: bash sdata/lib/app-variants.test.sh   (exit 0 = all green)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=app-variants.sh
source "$DIR/app-variants.sh"

FAILS=0; CASES=0
chk() { CASES=$((CASES + 1)); if [[ "$2" != "$3" ]]; then echo "  FAIL [$1]: got '$2' want '$3'"; FAILS=$((FAILS + 1)); fi; }

chk "flatpak swaps a default app"   "$(app_variant_swap flatpak chromium)" "org.chromium.Chromium"
chk "native swaps a flatpak app"    "$(app_variant_swap native org.videolan.VLC)" "vlc"
chk "flatpak keeps a flatpak ref"   "$(app_variant_swap flatpak org.videolan.VLC)" "org.videolan.VLC"
chk "native keeps a native app"     "$(app_variant_swap native chromium)" "chromium"
chk "steam never swaps"             "$(app_variant_swap flatpak steam)" "steam"
chk "mainstream-mpv never swaps"    "$(app_variant_swap flatpak mainstream-mpv)" "mainstream-mpv"
chk "flatpak-only app stays"        "$(app_variant_swap native com.brave.Browser)" "com.brave.Browser"
chk "unknown source leaves it"      "$(app_variant_swap snap chromium)" "chromium"
chk "empty source leaves it"        "$(app_variant_swap "" chromium)" "chromium"
chk "apply dedupes and keeps order" \
    "$(printf '%s\n' chromium org.chromium.Chromium steam loupe | app_variants_apply flatpak | paste -sd' ')" \
    "org.chromium.Chromium steam org.gnome.Loupe"

# Every excluded app must stay out of both columns.
for app in steam mainstream-nautilus gnome-disk-utility gnome-software mainstream-mpv mainstream-obs mainstream-calendar; do
    CASES=$((CASES + 1))
    if grep -v '^#' "$APP_VARIANTS_LIST" | tr '|' '\n' | grep -qx "$app"; then
        echo "  FAIL [excluded]: $app is listed"; FAILS=$((FAILS + 1))
    fi
done
# Each line is exactly two fields, the second a dotted ref, the first not.
CASES=$((CASES + 1))
bad=$(grep -v -e '^#' -e '^$' "$APP_VARIANTS_LIST" | awk -F'|' 'NF != 2 || $1 ~ /\./ || $2 !~ /\./')
[[ -z "$bad" ]] || { echo "  FAIL [format]: $bad"; FAILS=$((FAILS + 1)); }

APP_VARIANTS_LIST=/nonexistent/app-variants.list
chk "missing list leaves it"        "$(app_variant_swap flatpak chromium)" "chromium"

echo "app-variants: $CASES cases, $FAILS failed"
[[ $FAILS -eq 0 ]]
