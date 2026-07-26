#!/usr/bin/env bash
# Mainstream OS dotfiles bootstrap.
#
# One-line install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/MainstreamOS/dots-hyprland/mainstream/install.sh)
#
# Installs the newest numbered release — the same one the ISO ships and
# Settings -> Update tracks. Pass --edge to install the mainstream branch as it
# stands instead, ahead of any release:
#   bash <(curl -fsSL ...) --edge
#
# Override defaults via env (export before running):
#   MS_REPO_URL, MS_REPO_BRANCH, MS_CLONE_DIR
#
# Anything passed after a `--` is forwarded to ./setup install, e.g.:
#   bash <(curl -fsSL ...) -- --verbose
#   bash <(curl -fsSL ...) --edge -- --console

set -euo pipefail

REPO_URL="${MS_REPO_URL:-https://github.com/MainstreamOS/dots-hyprland.git}"
REPO_BRANCH="${MS_REPO_BRANCH:-mainstream}"
CLONE_DIR="${MS_CLONE_DIR:-$HOME/.cache/dots-hyprland}"

# The same 1-2 digit major cap updatems uses, so the installer and the updater
# can never disagree about which tag is newest, and the retired date tags
# (2026.05.11) can't sort above a real release.
TAG_REGEX='^[0-9]{1,2}\.[0-9]+\.[0-9]+$'
TAG_GLOB='[0-9]*.[0-9]*.[0-9]*'
MARKER="$CLONE_DIR/.updatems-applied-tag"

EDGE=0
SETUP_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --edge) EDGE=1; shift ;;
        --)     shift; SETUP_ARGS=("$@"); break ;;
        *)      printf 'Unknown option: %s\n' "$1" >&2
                printf 'Flags for the installer itself go after a "--" separator.\n' >&2
                exit 1 ;;
    esac
done

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
if [[ $EDGE -eq 1 ]]; then CHANNEL="edge ($REPO_BRANCH branch)"; else CHANNEL="release"; fi

say "Mainstream OS dotfiles bootstrap"
printf "    repo:    %s\n"   "$REPO_URL"
printf "    channel: %s\n"   "$CHANNEL"
printf "    target:  %s\n\n" "$CLONE_DIR"

if [[ -d "$CLONE_DIR/.git" ]]; then
    say "Existing clone at $CLONE_DIR — fetching latest $REPO_BRANCH..."
    git -C "$CLONE_DIR" fetch --tags --force origin "$REPO_BRANCH"
    # If the user has local changes, fail loud rather than blow them away.
    if ! git -C "$CLONE_DIR" diff --quiet || ! git -C "$CLONE_DIR" diff --cached --quiet; then
        die "Local changes in $CLONE_DIR. Commit/stash them or set MS_CLONE_DIR to a fresh path."
    fi
else
    say "Cloning $REPO_URL ($REPO_BRANCH) → $CLONE_DIR..."
    mkdir -p "$(dirname "$CLONE_DIR")"
    git clone --branch "$REPO_BRANCH" "$REPO_URL" "$CLONE_DIR"
fi

# Both channels land on a branch rather than a detached HEAD: setup's branch
# detection tries to bounce a detached HEAD back to main/master, and neither
# exists in this clone.
if [[ $EDGE -eq 1 ]]; then
    git -C "$CLONE_DIR" checkout "$REPO_BRANCH"
    git -C "$CLONE_DIR" reset --hard "origin/$REPO_BRANCH"
    # Named for the release it descends from, so the desktop still has a
    # version to show and updatems doesn't treat the install as unversioned.
    MARKER_TAG=$(git -C "$CLONE_DIR" describe --tags --abbrev=0 --match "$TAG_GLOB" 2>/dev/null || true)
    say "Branch tip: $(git -C "$CLONE_DIR" rev-parse --short HEAD) (after ${MARKER_TAG:-no release tag})"
else
    MARKER_TAG=$(git -C "$CLONE_DIR" tag --list --format='%(refname:strip=2)' \
        | grep -E "$TAG_REGEX" | sort -V | tail -n1 || true)
    [[ -n "$MARKER_TAG" ]] \
        || die "No release tag found in $REPO_URL. Pass --edge to install the $REPO_BRANCH branch instead."
    say "Newest release: $MARKER_TAG"
    git -C "$CLONE_DIR" checkout -B "$REPO_BRANCH" "refs/tags/$MARKER_TAG"
fi
ok "Sources ready."

# --- run the installer ------------------------------------------------------
cd "$CLONE_DIR"
say "Launching ./setup install ${SETUP_ARGS[*]:-}"
RC=0
./setup install "${SETUP_ARGS[@]}" || RC=$?
[[ $RC -eq 0 ]] || die "./setup install exited with rc=$RC"

# Both the desktop's release indicator and updatems read this marker to learn
# which release is installed. Without it they see an unversioned install: the
# indicator stays silent, and the next updatems run resets the clone to the
# newest tag rather than recognising it is already there.
if [[ -n "$MARKER_TAG" ]]; then
    printf '%s\n' "$MARKER_TAG" > "$MARKER"
    ok "Installed. Marked as $MARKER_TAG."
fi
