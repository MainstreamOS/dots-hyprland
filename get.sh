#!/usr/bin/env bash
# Mainstream OS dotfiles bootstrap.
#
# One-line install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/MainstreamOS/dots-hyprland/mainstream/get.sh)
#
# Override defaults via env (export before running):
#   MS_REPO_URL, MS_REPO_BRANCH, MS_CLONE_DIR
#
# Anything passed after the script is forwarded to ./setup install, e.g.:
#   bash <(curl -fsSL ...) -- --verbose

set -euo pipefail

REPO_URL="${MS_REPO_URL:-https://github.com/MainstreamOS/dots-hyprland.git}"
REPO_BRANCH="${MS_REPO_BRANCH:-mainstream}"
CLONE_DIR="${MS_CLONE_DIR:-$HOME/.cache/dots-hyprland}"

# Anything after a `--` is forwarded to `./setup install`.
SETUP_ARGS=()
if [[ "${1:-}" == "--" ]]; then shift; SETUP_ARGS=("$@"); fi

# --- pretty output ----------------------------------------------------------
_c_blue=$'\e[38;5;80m'; _c_green=$'\e[38;5;79m'; _c_red=$'\e[38;5;203m'; _c_rst=$'\e[0m'
say()  { printf '%s==>%s %s\n' "$_c_blue"  "$_c_rst" "$*"; }
ok()   { printf '%s✓%s   %s\n' "$_c_green" "$_c_rst" "$*"; }
die()  { printf '%s✗ %s%s\n'  "$_c_red"   "$*"      "$_c_rst" >&2; exit 1; }

# --- preflight --------------------------------------------------------------
[[ $EUID -ne 0 ]] || die "Don't run as root — Mainstream installs into your user account."

if ! command -v pacman >/dev/null 2>&1; then
    die "pacman not found. Mainstream OS targets Arch Linux / Arch-based distros."
fi

if ! command -v git >/dev/null 2>&1; then
    say "git not found, installing via pacman..."
    sudo pacman -Sy --needed --noconfirm git
fi

if ! command -v sudo >/dev/null 2>&1; then
    die "sudo is required for the installer."
fi

# --- fetch the dotfiles -----------------------------------------------------
say "Mainstream OS dotfiles bootstrap"
printf "    repo:    %s\n"   "$REPO_URL"
printf "    branch:  %s\n"   "$REPO_BRANCH"
printf "    target:  %s\n\n" "$CLONE_DIR"

if [[ -d "$CLONE_DIR/.git" ]]; then
    say "Existing clone at $CLONE_DIR — fetching latest $REPO_BRANCH..."
    git -C "$CLONE_DIR" fetch origin "$REPO_BRANCH"
    # If the user has local changes, fail loud rather than blow them away.
    if ! git -C "$CLONE_DIR" diff --quiet || ! git -C "$CLONE_DIR" diff --cached --quiet; then
        die "Local changes in $CLONE_DIR. Commit/stash them or set MS_CLONE_DIR to a fresh path."
    fi
    git -C "$CLONE_DIR" checkout "$REPO_BRANCH"
    git -C "$CLONE_DIR" reset --hard "origin/$REPO_BRANCH"
else
    say "Cloning $REPO_URL ($REPO_BRANCH) → $CLONE_DIR..."
    mkdir -p "$(dirname "$CLONE_DIR")"
    git clone --branch "$REPO_BRANCH" "$REPO_URL" "$CLONE_DIR"
fi
ok "Sources ready."

# --- run the installer ------------------------------------------------------
cd "$CLONE_DIR"
say "Launching ./setup install ${SETUP_ARGS[*]:-}"
exec ./setup install "${SETUP_ARGS[@]}"
