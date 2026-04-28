#!/usr/bin/env bash
# scripts/aur-publish.sh — push a mainstream-* package to its AUR git repo.
#
# Usage:
#   scripts/aur-publish.sh sdata/dist-arch/mainstream-basic
#   scripts/aur-publish.sh --all                  # publish every mainstream-* dir
#   scripts/aur-publish.sh --all --yes            # don't prompt before pushing
#
# What it does, per package directory:
#   1. Reads pkgname from the PKGBUILD (handles the quickshell-git case where
#      pkgname is a $_prefix-$_pkgname-git expansion).
#   2. Clones ssh://aur@aur.archlinux.org/<pkgname>.git into cache/aur/<pkgname>
#      (or pulls if it exists). A push to a non-existent AUR repo creates it.
#   3. Copies every git-tracked file from the source dir (PKGBUILD plus any
#      sibling source files like quickshell-check.hook), regenerates .SRCINFO
#      with makepkg --printsrcinfo, and stages those into the AUR working tree.
#   4. Shows the diff, asks before pushing (skip with --yes), and pushes master.

set -euo pipefail

REPO_ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
AUR_HOST="ssh://aur@aur.archlinux.org"
CACHE_DIR="$REPO_ROOT/cache/aur"

YES=0
ALL=0
TARGETS=()

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while (( $# )); do
    case "$1" in
        --all)  ALL=1 ;;
        --yes)  YES=1 ;;
        -h|--help) usage 0 ;;
        --) shift; while (( $# )); do TARGETS+=("$1"); shift; done; break ;;
        -*) echo "unknown flag: $1" >&2; usage 1 ;;
        *)  TARGETS+=("$1") ;;
    esac
    shift
done

if (( ALL )); then
    if (( ${#TARGETS[@]} )); then
        echo "--all and explicit targets are mutually exclusive" >&2; exit 1
    fi
    while IFS= read -r d; do TARGETS+=("$d"); done \
        < <(find "$REPO_ROOT/sdata/dist-arch" -maxdepth 1 -type d -name 'mainstream-*' | sort)
fi

if (( ${#TARGETS[@]} == 0 )); then
    echo "no targets given" >&2; usage 1
fi

command -v makepkg >/dev/null || { echo "makepkg not found (install pacman)" >&2; exit 1; }

# Extract the resolved pkgname from a PKGBUILD by sourcing it in a subshell.
# This handles dynamic forms like pkgname="$_prefix-$_pkgname-git".
resolve_pkgname() {
    local pkgbuild="$1"
    ( set +u; source "$pkgbuild"; printf '%s\n' "$pkgname" )
}

publish_one() {
    local src_dir="$1"
    src_dir="${src_dir%/}"
    local pkgbuild="$src_dir/PKGBUILD"
    [[ -f "$pkgbuild" ]] || { echo "no PKGBUILD in $src_dir" >&2; return 1; }

    local pkgname
    pkgname=$(resolve_pkgname "$pkgbuild")
    [[ -n "$pkgname" ]] || { echo "could not resolve pkgname for $src_dir" >&2; return 1; }

    echo
    echo "============================================================"
    echo "  $pkgname  (from ${src_dir#"$REPO_ROOT/"})"
    echo "============================================================"

    local work="$CACHE_DIR/$pkgname"
    mkdir -p "$CACHE_DIR"

    # Fresh clone or update. AUR creates the repo on first push, so a clone of
    # a not-yet-existing pkg fails — fall back to init in that case.
    if [[ -d "$work/.git" ]]; then
        ( cd "$work" && git fetch origin master 2>/dev/null && git reset --hard origin/master 2>/dev/null ) || true
    else
        rm -rf "$work"
        if git clone "$AUR_HOST/$pkgname.git" "$work" 2>/dev/null; then
            :
        else
            echo "  (AUR repo doesn't exist yet — initialising local tree, will be created on push)"
            mkdir -p "$work"
            ( cd "$work" && git init -q -b master && git remote add origin "$AUR_HOST/$pkgname.git" )
        fi
    fi

    # Wipe any non-.git content so removed files in the source dir actually
    # disappear from the AUR repo.
    find "$work" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +

    # Copy every git-tracked file from the source dir, except the local
    # .gitignore (it's local-build-cache only, not relevant on AUR).
    while IFS= read -r relpath; do
        [[ "$relpath" == ".gitignore" ]] && continue
        local src="$src_dir/$relpath"
        local dst="$work/$relpath"
        mkdir -p "$(dirname "$dst")"
        cp -p "$src" "$dst"
    done < <(cd "$src_dir" && git ls-files)

    # Generate .SRCINFO from the staged PKGBUILD.
    ( cd "$work" && makepkg --printsrcinfo > .SRCINFO )

    cd "$work"
    git add -A

    if git diff --cached --quiet; then
        echo "  no changes — skipping push"
        return 0
    fi

    echo
    echo "Staged changes:"
    git --no-pager diff --cached --stat
    echo

    if (( ! YES )); then
        read -rp "Push to $AUR_HOST/$pkgname.git ? [y/N] " ans
        case "$ans" in
            y|Y) ;;
            *) echo "  skipped"; return 0 ;;
        esac
    fi

    local pkgver pkgrel
    pkgver=$(awk -F= '/^pkgver/{print $2; exit}' PKGBUILD | tr -d ' "'\''')
    pkgrel=$(awk -F= '/^pkgrel/{print $2; exit}' PKGBUILD | tr -d ' "'\''')
    git -c user.useConfigOnly=true commit -q -m "$pkgname $pkgver-$pkgrel"
    git push origin HEAD:master
    echo "  pushed."
}

failures=0
for t in "${TARGETS[@]}"; do
    if ! publish_one "$t"; then
        failures=$((failures + 1))
        echo "  !! failed: $t" >&2
    fi
done

if (( failures > 0 )); then
    echo "$failures failed" >&2
    exit 1
fi
