#!/usr/bin/env bash
# release-gate.sh: run before a release is tagged. Compares the version of
# every package under sdata/dist-arch with what the published [mainstream]
# repo serves, and fails naming each one the repo lacks or serves older, and
# the shell when the repo's build has lost its Qt pin.
#
# An update reaches packages only through pacman -Syu from that repo, so a
# PKGBUILD bump that is tagged before the repo is rebuilt ships the dotfiles
# that expect it to machines that never get it. Read-only: it downloads the
# repo database into a temporary directory and changes nothing else.
#
# Usage: release-gate.sh [--repo-url URL]...
#   --repo-url  a repo to check instead of the one the installer adds; may be
#               given more than once (the SourceForge mirror, a file:// copy)
#
# Exit: 0 when every package is served at its PKGBUILD version or newer,
#       1 when any is missing, older or unpinned, 2 when a database or a
#       PKGBUILD could not be read.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_ARCH="${RELEASE_GATE_DIST_ARCH:-$HERE/../dist-arch}"
REPO=mainstream

urls=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-url) [[ $# -ge 2 ]] || { echo "--repo-url needs a URL" >&2; exit 2; }; urls+=("$2"); shift 2 ;;
        -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

# The repo the installer adds is the one clients update from; its URL is read
# from there rather than kept here as a second copy that could drift.
if [[ ${#urls[@]} -eq 0 ]]; then
    url="$(sed -nE 's/^MAINSTREAM_REPO_URL=//p' "$DIST_ARCH/install-deps.sh" | head -n1)"
    url="${url%\"}"; url="${url#\"}"
    [[ -n "$url" ]] || { echo "Could not read MAINSTREAM_REPO_URL from $DIST_ARCH/install-deps.sh" >&2; exit 2; }
    urls=("$url")
fi

command -v vercmp >/dev/null 2>&1 || { echo "vercmp (from pacman) is needed to compare versions" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# name full-version, one line per package a PKGBUILD produces. Sourced in a
# subshell the way makepkg reads it, so a pkgver computed at the top of the
# file comes out as makepkg would see it.
pkgbuild_versions() {
    local pb
    for pb in "$DIST_ARCH"/*/PKGBUILD; do
        [[ -e "$pb" ]] || continue
        (
            set +u
            # An unreadable one fails the gate instead of dropping out of it.
            # shellcheck source=/dev/null
            cd "$(dirname "$pb")" && source ./PKGBUILD >/dev/null 2>&1 \
                && [[ -n "$pkgver" && -n "$pkgrel" && -n "${pkgname[*]}" ]] \
                || { printf '%s\n' "$pb" >> "$work/unreadable"; exit 0; }
            v="$pkgver-$pkgrel"
            [[ -n "${epoch:-}" && "$epoch" != 0 ]] && v="$epoch:$v"
            for n in "${pkgname[@]}"; do printf '%s %s\n' "$n" "$v"; done
        )
    done
}

mapfile -t wanted < <(pkgbuild_versions | sort)
if [[ -s "$work/unreadable" ]]; then
    sed 's/^/Could not read the version from /' "$work/unreadable" >&2
    exit 2
fi
if [[ ${#wanted[@]} -eq 0 ]]; then
    echo "No PKGBUILDs found under $DIST_ARCH" >&2
    exit 2
fi

status=0
for url in "${urls[@]}"; do
    db="$work/$REPO.db"
    dbdir="$work/db"
    rm -rf "$db" "$dbdir"; mkdir -p "$dbdir"
    echo "── $url"
    if ! curl -fsSL --retry 3 --retry-delay 3 -o "$db" "${url%/}/$REPO.db"; then
        echo "   could not download $REPO.db"
        status=2
        continue
    fi
    if ! bsdtar -xf "$db" -C "$dbdir" 2>/dev/null && ! tar -xf "$db" -C "$dbdir" 2>/dev/null; then
        echo "   could not read $REPO.db"
        status=2
        continue
    fi
    declare -A served=()
    qs_pinned=""
    for desc in "$dbdir"/*/desc; do
        [[ -f "$desc" ]] || continue
        name="$(awk '/^%NAME%$/{getline; print; exit}' "$desc")"
        ver="$(awk '/^%VERSION%$/{getline; print; exit}' "$desc")"
        [[ -n "$name" && -n "$ver" ]] && served[$name]="$ver"
        # The shell's upper bound on qt6-base is what holds an Arch Qt update
        # back until a matching shell is out, and it has gone missing once
        # before under an unchanged version, which the comparison below
        # cannot see.
        if [[ "$name" == mainstream-quickshell-git ]]; then
            if awk '/^%DEPENDS%$/{f=1; next} /^$/{f=0} f' "$desc" | grep -q '^qt6-base<'; then
                qs_pinned=yes
            else
                qs_pinned=no
            fi
        fi
    done
    for line in "${wanted[@]}"; do
        name="${line%% *}"; want="${line#* }"
        have="${served[$name]:-}"
        if [[ -z "$have" ]]; then
            printf '   MISSING  %-40s PKGBUILD %s, not in the repo\n' "$name" "$want"
            [[ $status -eq 2 ]] || status=1
        elif (( $(vercmp "$have" "$want") < 0 )); then
            printf '   OLDER    %-40s PKGBUILD %s, repo serves %s\n' "$name" "$want" "$have"
            [[ $status -eq 2 ]] || status=1
        elif [[ "$name" == mainstream-quickshell-git && "$qs_pinned" == no ]]; then
            printf '   UNPINNED %-40s repo serves %s with no qt6-base upper bound\n' "$name" "$have"
            [[ $status -eq 2 ]] || status=1
        else
            printf '   ok       %-40s %s\n' "$name" "$have"
        fi
    done
    unset served
done

case $status in
    0) echo "Every package is published at its PKGBUILD version. Safe to tag." ;;
    1) echo "Not safe to tag: publish the packages above to [$REPO] first (rebuild the repo from this branch), then run this again." ;;
    *) echo "Could not check every repo; see above." ;;
esac
exit "$status"
