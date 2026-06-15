#!/usr/bin/env bash
# Build + install mpris-hyprland as a pacman package.
#
# Called from sdata/subcmd-install/2.setups.sh on STANDALONE (non-ISO)
# installs — Mainstream OS ISO installs already get it prebuilt from the
# [mainstream] repo, and 2.setups.sh skips this when it's already present.
#
# Builds the PKGBUILD with `makepkg -si`, which installs:
#   - the Rust native host          -> /usr/bin/mpris-hyprland-host
#   - the system native-messaging manifest (covers Firefox + forks incl. Zen)
#   - the WebExtension .xpi          -> /usr/share/mpris-hyprland/
#   - browser policies that auto-install the extension unsigned (Zen/forks)
#
# makepkg -s pulls the build deps (rust/cargo/zip/git) itself, so no toolchain
# needs to be pre-installed — which is why the old cargo-preflight version was
# disabled.

set -euo pipefail

REPO_URL="${MPRIS_HYPRLAND_REPO_URL:-https://github.com/MainstreamOS/mpris-hyprland}"
REPO_BRANCH="${MPRIS_HYPRLAND_REPO_BRANCH:-master}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="${REPO_ROOT:-$DOTS_ROOT}/cache/mpris-hyprland"

if [[ -t 1 ]]; then
    C_C="\e[36m"; C_Y="\e[33m"; C_R="\e[31m"; C_G="\e[32m"; C_RST="\e[0m"
else
    C_C=""; C_Y=""; C_R=""; C_G=""; C_RST=""
fi
note()  { printf "${C_C}[mpris-hyprland]${C_RST} %s\n" "$*"; }
warn()  { printf "${C_Y}[mpris-hyprland] WARN:${C_RST} %s\n" "$*" >&2; }
fatal() { printf "${C_R}[mpris-hyprland] ERROR:${C_RST} %s\n" "$*" >&2; exit 1; }

# ---------- preflight ------------------------------------------------------

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    fatal "this must NOT run as root — makepkg refuses root and uses sudo only for the install step"
fi
command -v git     >/dev/null 2>&1 || fatal "git not found — install with: sudo pacman -S git"
command -v makepkg >/dev/null 2>&1 || fatal "makepkg not found — install with: sudo pacman -S base-devel"

# ---------- clone or fast-forward (to get the PKGBUILD) --------------------

mkdir -p "$(dirname "$CACHE_DIR")"
if [[ ! -d "$CACHE_DIR/.git" ]]; then
    note "cloning $REPO_URL → $CACHE_DIR"
    git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$CACHE_DIR" \
        || fatal "git clone failed — check that $REPO_URL is reachable"
else
    note "updating cached repo at $CACHE_DIR"
    ( cd "$CACHE_DIR" && git fetch --depth 1 origin "$REPO_BRANCH" && git reset --hard FETCH_HEAD ) \
        || warn "git fetch failed — using existing cached copy"
fi

[[ -f "$CACHE_DIR/PKGBUILD" ]] || fatal "no PKGBUILD in $CACHE_DIR"

# ---------- build + install via makepkg ------------------------------------

note "building + installing the package (makepkg -si pulls rust/cargo/zip/git)"
( cd "$CACHE_DIR" && makepkg -si --needed --noconfirm ) \
    || fatal "makepkg failed — see output above"

printf "${C_G}[mpris-hyprland]${C_RST} installed.\n"
note "the WebExtension auto-installs on the next browser launch via the shipped"
note "policy (Zen and other unbranded forks). Restart the browser, then check"
note "about:addons / about:policies#active."
note "Vanilla Mozilla Firefox enforces signing — there, load it manually from"
note "about:debugging or use an AMO-signed build (see the package README)."
