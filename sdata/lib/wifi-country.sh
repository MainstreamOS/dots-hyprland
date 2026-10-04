# Wi-Fi regulatory domain guessed from the time zone, for the image install,
# ./setup and updatems-system. Sourced; safe under set -euo pipefail.

: "${WIFI_COUNTRY_CONF:=/etc/conf.d/wireless-regdom}"
: "${WIFI_COUNTRY_LOCALTIME:=/etc/localtime}"
: "${WIFI_COUNTRY_ZONEINFO:=/usr/share/zoneinfo}"
: "${WIFI_COUNTRY_REGDB:=/usr/lib/firmware/regulatory.db}"
: "${WIFI_COUNTRY_STAMP:=/var/lib/mainstream/wifi-country}"
: "${WIFI_COUNTRY_IMAGE_MARKS:=/var/log/mainstream-install /usr/local/bin/calamares-autostart}"
WIFI_COUNTRY_LINE='^[[:space:]]*(export[[:space:]]+)?WIRELESS_REGDOM='

# Calamares shows this zone when GeoIP cannot place the machine, so on an image
# install it says nothing about where the machine is.
WIFI_COUNTRY_INSTALLER_ZONE=America/New_York

wifi_country_zone() {
    local target zone
    target="$(readlink -- "$WIFI_COUNTRY_LOCALTIME" 2>/dev/null)" || return 0
    [[ "$target" == *zoneinfo/* ]] || return 0
    zone="${target##*zoneinfo/}"
    zone="${zone#posix/}"
    zone="${zone#right/}"
    [[ "$zone" =~ ^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*$ ]] || return 0
    [[ -f "$WIFI_COUNTRY_ZONEINFO/$zone" ]] || return 0
    printf '%s\n' "$zone"
}

wifi_country_from_timezone() {
    local zone="${1:-}" files=()
    [[ -n "$zone" ]] || zone="$(wifi_country_zone)"
    [[ -n "$zone" && -r "$WIFI_COUNTRY_ZONEINFO/zone.tab" ]] || return 0
    files=("$WIFI_COUNTRY_ZONEINFO/zone.tab")
    [[ -r "$WIFI_COUNTRY_ZONEINFO/zone1970.tab" ]] && files+=("$WIFI_COUNTRY_ZONEINFO/zone1970.tab")
    [[ -r "$WIFI_COUNTRY_ZONEINFO/tzdata.zi" ]] && files+=("$WIFI_COUNTRY_ZONEINFO/tzdata.zi")
    # A link such as US/Eastern counts only in Area/Location form, and only where
    # its target covers one country or the name sits in a country's directory.
    awk -F'\t' -v z="$zone" '
        FILENAME ~ /zone\.tab$/ && !/^#/     { cc[$3] = $1; next }
        FILENAME ~ /zone1970\.tab$/ && !/^#/ { n[$3] = split($1, x, ","); next }
        FILENAME ~ /tzdata\.zi$/ {
            split($0, w, " ")
            if (w[1] == "L" && w[3] == z) t = w[2]
        }
        END {
            if (z in cc) print cc[z]
            else if (z ~ /\// && t in cc && (n[t] == 1 || z ~ /^(US|Canada)\//)) print cc[t]
        }' "${files[@]}" 2>/dev/null | grep -E '^[A-Z]{2}$' || true
}

# True when regulatory.db has rules for the country; the kernel ignores others.
# Its rows: "RGDB", a version, then two letters and a pointer up to a zero one.
wifi_country_has_rules() {
    local want
    [[ "${1:-}" =~ ^[A-Z]{2}$ ]] || return 1
    want="$(printf '%02x %02x' "'${1:0:1}" "'${1:1:1}")"
    od -An -v -tx1 -w4 -N4096 -- "$WIFI_COUNTRY_REGDB" 2>/dev/null | awk -v want="$want" '
        NR == 1 { ok = ($1 $2 $3 $4 == "52474442") }
        NR <= 2 || end { next }
        ($3 $4 == "0000") { end = 1; next }
        ($1 " " $2 == want) { found = 1 }
        END { exit !(ok && found) }'
}

# True when cfg80211 takes its country from a module option, which a line in
# the conf file would override each time the module loads.
wifi_country_module_set() {
    local cur=""
    cur="$(cat /sys/module/cfg80211/parameters/ieee80211_regdom 2>/dev/null)" || true
    [[ -n "$cur" && "$cur" != 00 ]] && return 0
    grep -qsE '(^|[[:space:]])cfg80211\.ieee80211_regdom=' /proc/cmdline && return 0
    grep -qsE '^[[:space:]]*options[[:space:]]+cfg80211[[:space:]](.*[[:space:]])?ieee80211_regdom=' \
        /dev/null /etc/modprobe.d/*.conf /run/modprobe.d/*.conf /usr/lib/modprobe.d/*.conf
}

wifi_country_is_set() {
    grep -Eq "$WIFI_COUNTRY_LINE" "$WIFI_COUNTRY_CONF" 2>/dev/null
}

_wifi_country_lines() {
    grep -E "$WIFI_COUNTRY_LINE" "$WIFI_COUNTRY_CONF" 2>/dev/null || true
}

# With no country, the WIRELESS_REGDOM line is removed instead.
wifi_country_write() {
    local cc="${1:-}" conf="$WIFI_COUNTRY_CONF" s="${WIFI_COUNTRY_SUDO:-}" line="" text tmp
    [[ -z "$cc" || "$cc" =~ ^[A-Z]{2}$ ]] && [[ -f "$conf" && ! -L "$conf" ]] || return 1
    [[ -z "$cc" ]] || line="WIRELESS_REGDOM=\"$cc\""
    text="$(awk -v re="$WIFI_COUNTRY_LINE" -v line="$line" '
        $0 ~ re { if (!done && line != "") print line; done = 1; next }
        { print }
        END { if (!done && line != "") print line }' "$conf")" || return 1
    tmp="$($s mktemp "${conf%/*}/.wireless-regdom.XXXXXX")" || return 1
    if printf '%s\n' "$text" | $s tee "$tmp" >/dev/null \
       && $s chmod --reference="$conf" "$tmp" \
       && $s chown --reference="$conf" "$tmp" \
       && $s mv -f "$tmp" "$conf"; then
        return 0
    fi
    $s rm -f "$tmp"
    return 1
}

# Prints the country seeded from the time zone, or 00 when it takes back its own guess.
# A guess ("seeded XX" in the stamp) follows zone changes; a choice ("chosen") is never touched.
wifi_country_seed() {
    local stamp="" ours="" revisit=0 zone="" cc=""
    # Never created here: pacman will not install wireless-regdb over it.
    [[ -f "$WIFI_COUNTRY_CONF" && ! -L "$WIFI_COUNTRY_CONF" ]] || return 0
    if [[ -e "$WIFI_COUNTRY_STAMP" ]]; then
        stamp="$(cat -- "$WIFI_COUNTRY_STAMP" 2>/dev/null)" || true
        [[ "$stamp" =~ ^seeded(\ ([A-Z]{2}))?$ ]] || return 0
        ours="${BASH_REMATCH[2]}"
        revisit=1
        if [[ "$(_wifi_country_lines)" != "${ours:+WIRELESS_REGDOM=\"$ours\"}" ]]; then
            _wifi_country_stamp chosen
            return 0
        fi
    elif wifi_country_is_set; then
        _wifi_country_stamp chosen
        return 0
    fi
    if wifi_country_module_set; then
        if [[ -n "$ours" ]]; then
            wifi_country_write "" || return 1
            _wifi_country_stamp seeded
        fi
        return 0
    fi
    zone="$(wifi_country_zone)"
    if (( ! revisit )) && [[ "$zone" == "$WIFI_COUNTRY_INSTALLER_ZONE" ]] \
       && _wifi_country_from_image "${1:-}"; then
        return 0
    fi
    [[ -z "$zone" ]] || cc="$(wifi_country_from_timezone "$zone")"
    [[ -z "$cc" ]] || wifi_country_has_rules "$cc" || cc=""
    [[ "$cc" != "$ours" ]] || return 0
    wifi_country_write "$cc" || return 1
    _wifi_country_stamp "seeded${cc:+ $cc}"
    printf '%s\n' "${cc:-00}"
}

_wifi_country_from_image() {
    local mark
    [[ "${1:-}" == --from-image ]] && return 0
    for mark in $WIFI_COUNTRY_IMAGE_MARKS; do
        [[ -e "$mark" ]] && return 0
    done
    return 1
}

_wifi_country_stamp() {
    local s="${WIFI_COUNTRY_SUDO:-}"
    { $s mkdir -p "${WIFI_COUNTRY_STAMP%/*}" \
        && printf '%s\n' "$1" | $s tee "$WIFI_COUNTRY_STAMP" >/dev/null; } 2>/dev/null || true
}

# With cfg80211 not loaded there is nothing to tell yet; its udev rule reads the
# conf file when it loads.
wifi_country_apply() {
    [[ -d /sys/module/cfg80211 ]] || return 0
    command -v iw >/dev/null 2>&1 || return 1
    ${WIFI_COUNTRY_SUDO:-} iw reg set "$1"
}
