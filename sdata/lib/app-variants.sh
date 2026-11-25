# App source swap for ./setup's Custom profile: turns a selected app into its
# native package or Flatpak ref per sdata/dist-arch/mainstream-extras/app-variants.list.
# Sourced; safe under set -euo pipefail. The installer's packages step applies
# the same rule in Python.

: "${APP_VARIANTS_LIST:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dist-arch/mainstream-extras/app-variants.list}"

# app_variant_swap SOURCE NAME: prints the name to install. SOURCE is native or
# flatpak; any other value, or a missing list, leaves NAME as it is.
app_variant_swap() {
    local source="$1" name="$2" line native ref
    if [[ ( "$source" == native || "$source" == flatpak ) && -r "$APP_VARIANTS_LIST" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            line="${line//[[:space:]]/}"
            [[ "$line" == *'|'* ]] || continue
            native="${line%%|*}"
            ref="${line#*|}"
            ref="${ref%%|*}"
            [[ -n "$native" && -n "$ref" ]] || continue
            if [[ "$source" == flatpak && "$name" == "$native" ]]; then
                printf '%s\n' "$ref"; return 0
            fi
            if [[ "$source" == native && "$name" == "$ref" ]]; then
                printf '%s\n' "$native"; return 0
            fi
        done < "$APP_VARIANTS_LIST"
    fi
    printf '%s\n' "$name"
}

# app_variants_apply SOURCE: reads names one per line on stdin and prints the
# names to install, in order, each once.
app_variants_apply() {
    local source="$1" name swapped
    local -A seen=()
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        swapped="$(app_variant_swap "$source" "$name")"
        [[ -n "${seen[$swapped]:-}" ]] && continue
        seen[$swapped]=1
        printf '%s\n' "$swapped"
    done
}
