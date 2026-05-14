# This script is meant to be sourced.
# It's not for directly running.

install-yay(){
  x sudo pacman -S --needed --noconfirm base-devel
  x git clone https://aur.archlinux.org/yay-bin.git /tmp/buildyay
  x cd /tmp/buildyay
  x makepkg -o
  x makepkg -se --noconfirm
  x makepkg -i --noconfirm
  x cd ${REPO_ROOT}
  rm -rf /tmp/buildyay
}

remove_deprecated_dependencies(){
  printf "${STY_CYAN}[$0]: Removing deprecated dependencies:${STY_RST}\n"
  local list=()
  list+=(illogical-impulse-{microtex,pymyc-aur,oneui4-icons-git})
  list+=(hyprland-qtutils)
  list+=({quickshell,hyprutils,hyprpicker,hyprlang,hypridle,hyprland-qt-support,hyprland-qtutils,hyprlock,xdg-desktop-portal-hyprland,hyprcursor,hyprwayland-scanner,hyprland}-git)
  list+=(matugen-bin)
  for i in ${list[@]};do try sudo pacman --noconfirm -Rdd $i;done
}
# NOTE: `implicitize_old_dependencies()` was for the old days when we just switch from dependencies.conf to local PKGBUILDs.
# However, let's just keep it as references for other distros writing their `sdata/dist-<OS_GROUP_ID>/install-deps.sh`, if they need it.
implicitize_old_dependencies(){
# Convert old dependencies to non explicit dependencies so that they can be orphaned if not in meta packages
  remove_bashcomments_emptylines ./sdata/dist-arch/previous_dependencies.conf ./cache/old_deps_stripped.conf
  readarray -t old_deps_list < ./cache/old_deps_stripped.conf
  pacman -Qeq > ./cache/pacman_explicit_packages
  readarray -t explicitly_installed < ./cache/pacman_explicit_packages

  echo "Attempting to set previously explicitly installed deps as implicit..."
  for i in "${explicitly_installed[@]}"; do for j in "${old_deps_list[@]}"; do
    [ "$i" = "$j" ] && yay -D --asdeps "$i"
  done; done

  return 0
}

#####################################################################################
# Packages that must never be installed, regardless of what PKGBUILDs request.
# These are blocked at three layers:
#   1. The depends[] loop checks this list and skips any matching entry explicitly.
#   2. Every yay call passes --ignore with this list so pacman won't pull them
#      in as transitive dependencies during AUR resolution.
#   3. pacman.conf IgnorePkg is temporarily set around makepkg so that
#      makepkg's own internal pacman -S calls also respect the block.
#
# Notable omissions (intentional):
#   - kdialog          : small standalone utility, no Plasma chain risk
#   - plasma-browser-integration : handled separately below (hard skip)
KDE_PLASMA_BLOCKLIST=(
  kio-extras
  dolphin
  konsole
  kate
  plasma-workspace
  kdeconnect
  kde-cli-tools
)

# Build a comma-separated string for --ignore flags
KDE_IGNORE_ARG=$(IFS=,; echo "${KDE_PLASMA_BLOCKLIST[*]}")

# Helper: returns 0 (true) if the given package name is on the blocklist
_is_kde_blocked() {
  local pkg="$1"
  for b in "${KDE_PLASMA_BLOCKLIST[@]}"; do
    [[ "$pkg" == "$b" ]] && return 0
  done
  return 1
}

# Temporarily adds IgnorePkg entries to /etc/pacman.conf so that makepkg's
# own internal pacman calls also respect the KDE block, then restores the
# original file afterward. This is the only way to cover makepkg -s/-i.
_pacman_conf_block_kde() {
  if ! grep -q "^IgnorePkg" /etc/pacman.conf; then
    sudo sed -i "s/^#IgnorePkg.*/IgnorePkg = ${KDE_IGNORE_ARG//,/ }/" /etc/pacman.conf
    # If the line was completely absent (not just commented), append it
    grep -q "^IgnorePkg" /etc/pacman.conf || \
      sudo sed -i "/^\[options\]/a IgnorePkg = ${KDE_IGNORE_ARG//,/ }" /etc/pacman.conf
  else
    # Merge into the existing IgnorePkg line
    local existing
    existing=$(grep "^IgnorePkg" /etc/pacman.conf | sed 's/^IgnorePkg *= *//')
    local merged="${existing} ${KDE_IGNORE_ARG//,/ }"
    sudo sed -i "s/^IgnorePkg.*/IgnorePkg = ${merged}/" /etc/pacman.conf
  fi
}

_pacman_conf_restore_kde() {
  # Remove only the KDE packages we added, restoring the original IgnorePkg line.
  # Safest approach: remove the whole IgnorePkg line then re-add the original
  # content minus our additions. If the line was absent originally, remove it.
  local original_line="$1"
  if [[ -z "$original_line" ]]; then
    sudo sed -i "/^IgnorePkg/d" /etc/pacman.conf
  else
    sudo sed -i "s/^IgnorePkg.*/${original_line}/" /etc/pacman.conf
  fi
}

#####################################################################################
if ! command -v pacman >/dev/null 2>&1; then
  printf "${STY_RED}[$0]: pacman not found, it seems that the system is not ArchLinux or Arch-based distros. Aborting...${STY_RST}\n"
  exit 1
fi

# Keep makepkg from resetting sudo credentials
if [[ -z "${PACMAN_AUTH:-}" ]]; then
  export PACMAN_AUTH="sudo"
fi

showfun remove_deprecated_dependencies
v remove_deprecated_dependencies

# Issue #363
case $SKIP_SYSUPDATE in
  true) sleep 0;;
  *) v sudo pacman -Syu --noconfirm;;
esac

# Use yay. Because paru does not support cleanbuild.
# Also see https://wiki.hyprland.org/FAQ/#how-do-i-update
if ! command -v yay >/dev/null 2>&1;then
  echo -e "${STY_YELLOW}[$0]: \"yay\" not found.${STY_RST}"
  showfun install-yay
  v install-yay
fi

showfun implicitize_old_dependencies
v implicitize_old_dependencies

# https://github.com/end-4/dots-hyprland/issues/581
# yay -Bi is kinda hit or miss, instead cd into the relevant directory and manually source and install deps
install-local-pkgbuild() {
  local location=$1
  local installflags=$2

  x pushd $location

  source ./PKGBUILD

  # Install depends[] one-by-one so a single failure doesn't block the rest.
  # optdepends[] is only installed for mainstream-extras (default apps).
  # For all other packages optdepends are intentionally skipped.
  local failed_deps=()
  for dep in "${depends[@]}"; do
    # Block anything on the KDE/Plasma blocklist
    if _is_kde_blocked "$dep"; then
      printf "${STY_YELLOW}[$0]: Skipping blocked KDE/Plasma dep '%s'${STY_RST}\n" "$dep"
      continue
    fi

    if ! yay -S --sudoloop $installflags --ignore "$KDE_IGNORE_ARG" --asdeps "$dep"; then
      printf "${STY_YELLOW}[$0]: WARNING: Failed to install dependency '%s', will retry after others.${STY_RST}\n" "$dep"
      failed_deps+=("$dep")
    fi
  done

  # For mainstream-extras specifically, also install its optdepends —
  # these are the default apps (calculator, office, media player, etc.) that
  # should be present on every installation. The KDE blocklist and --ignore
  # flag still apply, so no Plasma packages can sneak in via this path.
  #
  # Dual-source routing matches archiso's netinstall.conf:
  #   - Name contains a dot (reverse-DNS, e.g. com.spotify.Client) → Flatpak,
  #     installed via `flatpak install --system flathub <ref>` after a
  #     one-shot remote-add for flathub.
  #   - Anything else → native Arch / AUR, installed via the existing yay path.
  # The flatpak binary itself is in this optdepends list and gets installed
  # via the yay path before any Flatpak entries are reached (the list orders
  # `flatpak:` first, ahead of the reverse-DNS entries).
  if [[ "$pkgname" == "mainstream-extras" ]]; then
    # Drop pacman hooks BEFORE the optdepends loop so they're in place
    # when the corresponding packages get installed below. Currently
    # only one — nautilus-copy-path's bundled config.json defaults to
    # 4 menu items; the hook flips uri/name/content to false after
    # every install/upgrade so only "Copy path" surfaces.
    x sudo install -Dm 644 \
        ./sdata/nautilus-copy-path/95-nautilus-copy-path-config.hook \
        /etc/pacman.d/hooks/95-nautilus-copy-path-config.hook

    printf "${STY_CYAN}[$0]: Installing default apps from mainstream-extras optdepends...${STY_RST}\n"
    local _flathub_added=false
    for dep in "${optdepends[@]}"; do
      local pkg="${dep%%:*}"
      if _is_kde_blocked "$pkg"; then
        printf "${STY_YELLOW}[$0]: Skipping blocked KDE/Plasma extras dep '%s'${STY_RST}\n" "$pkg"
        continue
      fi
      # Flatpak ref → reverse-DNS app ID (dot in name).
      if [[ "$pkg" == *.* ]]; then
        if ! command -v flatpak >/dev/null 2>&1; then
          printf "${STY_YELLOW}[$0]: WARNING: flatpak not installed yet, deferring '%s'${STY_RST}\n" "$pkg"
          failed_deps+=("$pkg")
          continue
        fi
        # One-shot flathub remote-add the first time we see a Flatpak ref.
        # --if-not-exists is idempotent, but caching saves a fork per package.
        if ! $_flathub_added; then
          x sudo flatpak remote-add --if-not-exists --system flathub \
              https://flathub.org/repo/flathub.flatpakrepo || true
          _flathub_added=true
        fi
        if ! sudo flatpak install --system --noninteractive --assumeyes \
                flathub "$pkg"; then
          printf "${STY_YELLOW}[$0]: WARNING: Failed to install Flatpak '%s', will retry after others.${STY_RST}\n" "$pkg"
          failed_deps+=("$pkg")
        fi
        continue
      fi
      # Native Arch / AUR path.
      if ! yay -S --sudoloop $installflags --ignore "$KDE_IGNORE_ARG" --asdeps "$pkg"; then
        printf "${STY_YELLOW}[$0]: WARNING: Failed to install extras dep '%s', will retry after others.${STY_RST}\n" "$pkg"
        failed_deps+=("$pkg")
      fi
    done
  fi

  # Retry failed deps once (they may have failed due to ordering/transient
  # issues — e.g. a Flatpak ref hit before `flatpak` itself was installed,
  # or yay racing with another in-flight pacman). Route Flatpak refs to
  # flatpak install on the retry too; without this, com.spotify.Client
  # would get tried as a yay package on the retry and fail twice.
  for dep in "${failed_deps[@]}"; do
    if _is_kde_blocked "$dep"; then continue; fi
    if [[ "$dep" == *.* ]] && command -v flatpak >/dev/null 2>&1; then
      if ! $_flathub_added; then
        x sudo flatpak remote-add --if-not-exists --system flathub \
            https://flathub.org/repo/flathub.flatpakrepo || true
        _flathub_added=true
      fi
      if ! sudo flatpak install --system --noninteractive --assumeyes \
              flathub "$dep"; then
        printf "${STY_RED}[$0]: ERROR: Failed to install Flatpak '%s'. You may need to install it manually.${STY_RST}\n" "$dep"
      fi
      continue
    fi
    if ! yay -S --sudoloop $installflags --ignore "$KDE_IGNORE_ARG" --asdeps "$dep"; then
      printf "${STY_RED}[$0]: ERROR: Failed to install dependency '%s'. You may need to install it manually.${STY_RST}\n" "$dep"
    fi
  done

  # Snapshot the current IgnorePkg line (may be empty) so we can restore it after makepkg.
  # This ensures makepkg's own internal pacman -S calls also respect the KDE block.
  local _orig_ignorepkg
  _orig_ignorepkg=$(grep "^IgnorePkg" /etc/pacman.conf || true)
  _pacman_conf_block_kde

  # man makepkg:
  # -A, --ignorearch: Ignore a missing or incomplete arch field in the build script.
  # -s, --syncdeps: Install missing dependencies using pacman. When build-time or run-time
  #                 dependencies are not found, pacman will try to resolve them.
  # -f, --force: build a package even if it already exists in the PKGDEST
  # -i, --install: Install or upgrade the package after a successful build using pacman(8).
  # In https://github.com/end-4/dots-hyprland/issues/823#issuecomment-3394774645 it's suggested
  # to use `sudo pacman -U --noconfirm *.pkg.tar.zst` instead of `makepkg -i`, however it's
  # possible that multiple *.pkg.tar.zst exist, which makes this command not reliable.
  x makepkg -Afsi --noconfirm

  # Restore pacman.conf to its pre-call state
  _pacman_conf_restore_kde "$_orig_ignorepkg"

  x popd
}

# Install core dependencies from the meta-packages
metapkgs=(./sdata/dist-arch/mainstream-{audio,backlight,basic,fonts-themes,gnome,portal,python,screencapture,toolkit,widgets})
metapkgs+=(./sdata/dist-arch/mainstream-hyprland)
metapkgs+=(./sdata/dist-arch/mainstream-microtex-git)
metapkgs+=(./sdata/dist-arch/mainstream-quickshell-git)
metapkgs+=(./sdata/dist-arch/mainstream-extras)
metapkgs+=(./sdata/dist-arch/mainstream-bibata-modern-classic-bin)

for i in "${metapkgs[@]}"; do
  metainstallflags="--needed"
  $ask && showfun install-local-pkgbuild || metainstallflags="$metainstallflags --noconfirm"
  if declare -F ms_step >/dev/null 2>&1; then
    ms_step installing "$(basename "$i")"
  fi
  v install-local-pkgbuild "$i" "$metainstallflags"
done

## plasma-browser-integration is intentionally not installed.
## It pulls ~600MiB of KDE/Plasma packages on a system without KDE present.
## We use firefox-mpris-hyprland instead (per-tab MPRIS bridge, ~2MB binary,
## no KDE deps) — set up automatically by `setup_firefox_mpris_hyprland` in
## the next step.
printf "${STY_CYAN}[$0]: Skipping plasma-browser-integration (using firefox-mpris-hyprland instead).${STY_RST}\n"
