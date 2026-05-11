#!/usr/bin/env bash
# Clone, build, and install firefox-mpris-hyprland for the invoking user.
#
# Called from sdata/subcmd-install/2.setups.sh as one of the "setup_*"
# steps. Idempotent — if the repo is already cloned into ./cache/, it
# fast-forwards instead of re-cloning, and install.sh is itself idempotent.

set -euo pipefail

REPO_URL="${FIREFOX_MPRIS_REPO_URL:-https://github.com/MainstreamOS/firefox-mpris-hyprland}"
REPO_BRANCH="${FIREFOX_MPRIS_REPO_BRANCH:-master}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="${REPO_ROOT:-$DOTS_ROOT}/cache/firefox-mpris-hyprland"

# Color helpers — only used when run interactively. Match dots-hyprland style.
if [[ -t 1 ]]; then
    C_C="\e[36m"; C_Y="\e[33m"; C_R="\e[31m"; C_G="\e[32m"; C_RST="\e[0m"
else
    C_C=""; C_Y=""; C_R=""; C_G=""; C_RST=""
fi

note()  { printf "${C_C}[firefox-mpris]${C_RST} %s\n" "$*"; }
warn()  { printf "${C_Y}[firefox-mpris] WARN:${C_RST} %s\n" "$*" >&2; }
fatal() { printf "${C_R}[firefox-mpris] ERROR:${C_RST} %s\n" "$*" >&2; exit 1; }

# ---------- preflight ------------------------------------------------------

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    fatal "this script must NOT be run as root — the native-messaging manifest goes under \$HOME"
fi

command -v git   >/dev/null 2>&1 || fatal "git not found — install with: sudo pacman -S git"
command -v cargo >/dev/null 2>&1 || fatal "cargo (rust) not found — install with: sudo pacman -S rust"
command -v zip   >/dev/null 2>&1 || fatal "zip not found — install with: sudo pacman -S zip (upstream install.sh bundles the extension as a .xpi via zip)"

# ---------- clone or fast-forward -----------------------------------------

mkdir -p "$(dirname "$CACHE_DIR")"

if [[ ! -d "$CACHE_DIR/.git" ]]; then
    note "cloning $REPO_URL → $CACHE_DIR"
    git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$CACHE_DIR" \
        || fatal "git clone failed — check that $REPO_URL is reachable"
else
    note "updating cached repo at $CACHE_DIR"
    if ! ( cd "$CACHE_DIR" \
        && git fetch --depth 1 origin "$REPO_BRANCH" \
        && git reset --hard "FETCH_HEAD" ); then
        warn "git fetch failed — using existing cached copy"
    fi
fi

# ---------- run upstream installer ----------------------------------------

note "running upstream install.sh (auto-detects Firefox / Zen / LibreWolf / Floorp / Waterfox)"
( cd "$CACHE_DIR" && bash install.sh )

note "host installed → ~/.local/bin/firefox-mpris-host"
note "manifests installed for: $(
    for d in .mozilla .librewolf .zen .floorp .waterfox; do
        [[ -f "$HOME/$d/native-messaging-hosts/io.github.mainstreamos.firefox_mpris_hyprland.json" ]] && printf "%s " "${d#.}"
    done
)"
printf "${C_G}[firefox-mpris]${C_RST} ${C_C}Final manual step:${C_RST} in each browser, open ${C_C}about:debugging#/runtime/this-firefox${C_RST},\n"
printf "                 click ${C_C}Load Temporary Add-on…${C_RST}, and select:\n"
printf "                 ${C_C}${CACHE_DIR}/extension/manifest.json${C_RST}\n"
