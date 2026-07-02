# This script is meant to be sourced.
# It's not for directly running.

printf "\n"
ms_section "Configuring..."

function prepare_systemd_user_service(){
  if [[ ! -e "/usr/lib/systemd/user/ydotool.service" ]]; then
    x sudo ln -s /usr/lib/systemd/{system,user}/ydotool.service
  fi
}

function setup_user_group(){
  if [[ -z $(getent group i2c) ]] && [[ "$OS_GROUP_ID" != "fedora" ]]; then
    # On Fedora this is not needed. Tested with desktop computer with NVIDIA video card.
    x sudo groupadd i2c
  fi

  # Match the archiso/Calamares default group set so both install paths grant
  # the user the same device access (render for GPU compute, audio, storage, lp,
  # optical, …). Only add groups that exist so a missing one can't fail the whole
  # usermod call.
  local _want=(wheel network audio video input power storage lp optical render i2c)
  [[ "$OS_GROUP_ID" == "fedora" ]] && _want=(wheel network audio video input power render)
  local _add=() _g
  for _g in "${_want[@]}"; do getent group "$_g" >/dev/null 2>&1 && _add+=("$_g"); done
  if [[ ${#_add[@]} -gt 0 ]]; then
    x sudo usermod -aG "$(IFS=,; echo "${_add[*]}")" "$(whoami)"
  fi
}

function setup_sddm_bg_polkit(){
  # Install polkit policy and rule so wallpaper changes can update SDDM background without a password
  local helper_src="${REPO_ROOT}/dots/.config/quickshell/ii/scripts/colors/sddm-bg-helper.sh"
  x sudo cp "$helper_src" /usr/local/bin/sddm-bg-helper
  x sudo chmod 755 /usr/local/bin/sddm-bg-helper
  x sudo cp "${REPO_ROOT}/sdata/polkit/org.illogicalimpulse.sddm-bg.policy" /usr/share/polkit-1/actions/
  x sudo cp "${REPO_ROOT}/sdata/polkit/50-sddm-bg.rules" /usr/share/polkit-1/rules.d/
}

function setup_power_key_polkit(){
  # Install helper script and polkit policy/rule so the settings panel can change HandlePowerKey without a password
  x sudo cp "${REPO_ROOT}/sdata/polkit/power-key-helper.sh" /usr/local/bin/power-key-helper
  x sudo chmod 755 /usr/local/bin/power-key-helper
  x sudo cp "${REPO_ROOT}/sdata/polkit/org.illogicalimpulse.power-key.policy" /usr/share/polkit-1/actions/
  x sudo cp "${REPO_ROOT}/sdata/polkit/50-power-key.rules" /usr/share/polkit-1/rules.d/
  # Create default logind drop-in if it doesn't exist yet
  if [[ ! -f "/etc/systemd/logind.conf.d/10-power-key.conf" ]]; then
    x sudo mkdir -p /etc/systemd/logind.conf.d
    x sudo tee /etc/systemd/logind.conf.d/10-power-key.conf > /dev/null << 'EOF'
[Login]
HandlePowerKey=suspend
EOF
  fi
}

function setup_disk_mounter(){
  # Install the privileged helper + polkit policy used by the
  # ~/.config/quickshell/ii/disk-mounter.qml app ("Auto Drive Mount").
  #
  # The policy declares allow_active=auth_admin_keep, which caches the
  # admin authentication for ~5 minutes after the first prompt. Without
  # this, every mount/unmount triggers a fresh polkit dialog.
  x sudo install -Dm755 "${REPO_ROOT}/sdata/polkit/disk-mounter" \
      /usr/local/bin/disk-mounter
  x sudo install -Dm644 "${REPO_ROOT}/sdata/polkit/org.mainstreamos.disk-mounter.policy" \
      /usr/share/polkit-1/actions/org.mainstreamos.disk-mounter.policy

  # Enable avahi-daemon so the app's Network tab can discover SMB hosts
  # on the LAN via avahi-browse. Idempotent; --now also starts it.
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files avahi-daemon.service >/dev/null 2>&1; then
      x sudo systemctl enable --now avahi-daemon.service || true
    fi
  fi
}

function setup_kill_fprintd_service(){
  # Fix fingerprint bug when sleeping
  # Fprintd waits 30 seconds after a successful login before quitting, so sleeping during that time period may cause fprintd to break.
  if [[ ! -f "/etc/systemd/system/kill-fprintd.service" ]]; then
    x sudo tee /etc/systemd/system/kill-fprintd.service > /dev/null << 'EOF'
[Unit]
Description=Kill fprintd before sleep
Before=sleep.target

[Service]
ExecStart=killall fprintd

[Install]
WantedBy=sleep.target
EOF
  fi
}

function setup_pwfeedback(){
  # Show '*' for each typed character at sudo password prompts. By default
  # sudo gives no visual feedback, which catches new users out — they can't
  # tell whether the keyboard is being read. Drop-in lives under sudoers.d
  # so package upgrades to /etc/sudoers can never clobber it. visudo -cf
  # validates before install so a syntax error never leaves the system in
  # an unsudoable state.
  local tmp; tmp=$(mktemp)
  printf 'Defaults pwfeedback\n' > "$tmp"
  if sudo visudo -cf "$tmp" >/dev/null 2>&1; then
    x sudo install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/pwfeedback
  else
    echo -e "${STY_RED}[$0]: pwfeedback drop-in failed visudo validation; not installing.${STY_RST}"
  fi
  rm -f "$tmp"
}
function detect_gpu_vendors(){
  # Returns space-separated list of: nvidia amd intel vm
  local vendors=()

  # Check for VM/virtual GPU first
  if [[ -d /sys/class/dmi/id ]]; then
    local sys_vendor
    sys_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "")
    case "$sys_vendor" in
      *QEMU*|*VirtualBox*|*VMware*|*Microsoft*|*Parallels*|*Xen*)
        vendors+=(vm)
        ;;
    esac
  fi

  # Check PCI devices for GPU vendors
  if command -v lspci >/dev/null 2>&1; then
    local gpu_lines
    gpu_lines=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || true)
    if echo "$gpu_lines" | grep -qi 'nvidia'; then
      vendors+=(nvidia)
    fi
    if echo "$gpu_lines" | grep -qi 'amd\|ati\|radeon'; then
      vendors+=(amd)
    fi
    if echo "$gpu_lines" | grep -qi 'intel'; then
      vendors+=(intel)
    fi
  else
    # Fallback: check sysfs vendor IDs
    for d in /sys/class/drm/card*/device; do
      [[ -r "$d/vendor" ]] || continue
      local vid
      vid=$(<"$d/vendor")
      case "$vid" in
        0x10de) [[ ! " ${vendors[*]} " =~ " nvidia " ]] && vendors+=(nvidia);;
        0x1002) [[ ! " ${vendors[*]} " =~ " amd " ]] && vendors+=(amd);;
        0x8086) [[ ! " ${vendors[*]} " =~ " intel " ]] && vendors+=(intel);;
      esac
    done
  fi

  echo "${vendors[*]}"
}

function setup_gpu_drivers(){
  local vendors
  vendors=$(detect_gpu_vendors)

  if [[ -z "$vendors" ]]; then
    echo -e "${STY_YELLOW}[$0]: No GPU detected. Skipping driver installation.${STY_RST}"
    return 0
  fi

  echo -e "${STY_CYAN}[$0]: Detected GPU vendor(s): ${vendors}${STY_RST}"

  for vendor in $vendors; do
    case "$vendor" in
      nvidia)
        echo -e "${STY_CYAN}[$0]: Installing NVIDIA drivers...${STY_RST}"
        case "$OS_GROUP_ID" in
          arch)
            # Pick the driver branch by GPU generation: Turing+ -> nvidia-open,
            # Maxwell/Kepler/Fermi -> frozen legacy branch, pre-Fermi -> nouveau.
            # modprobe options + cmdline + mkinitcpio modules are handled by setup_gpu_autoconfig later.
            gpu_detect || true
            gpu_classify_nvidia_driver
            echo -e "${STY_CYAN}[$0]: NVIDIA generation ${NVIDIA_GEN} -> driver family ${NVIDIA_DRIVER_FAMILY}${STY_RST}"
            if [[ ${#NVIDIA_REPO_PKGS[@]} -gt 0 ]]; then
              # Straight from official repos / [mainstream]: nvidia-open (Turing+) or nouveau (pre-Fermi).
              local _repo=() _lib32=()
              for _p in "${NVIDIA_REPO_PKGS[@]}"; do
                case "$_p" in lib32-*) _lib32+=("$_p");; *) _repo+=("$_p");; esac
              done
              [[ "$NVIDIA_DRIVER_FAMILY" != nouveau ]] && _repo+=(egl-wayland)
              x sudo pacman -S --needed --noconfirm "${_repo[@]}"
              # 32-bit GL needs the multilib repo; best-effort so a non-multilib host doesn't abort the install.
              [[ ${#_lib32[@]} -gt 0 ]] && try sudo pacman -S --needed --noconfirm "${_lib32[@]}"
            else
              # Frozen legacy branch (nvidia-580xx/470xx/390xx) — only present if [mainstream] prebuilt it.
              # The *-dkms packages build against the kernel, so linux-headers + dkms must be present first.
              x sudo pacman -S --needed --noconfirm linux-headers dkms
              # Try the legacy branch; if unavailable, fall back to nouveau and leave a breadcrumb.
              if ! sudo pacman -S --needed --noconfirm "${NVIDIA_LOCAL_PKGS[@]}" egl-wayland; then
                echo -e "${STY_YELLOW}[$0]: Legacy NVIDIA branch ${NVIDIA_DRIVER_FAMILY} unavailable — falling back to nouveau.${STY_RST}"
                x sudo pacman -S --needed --noconfirm xf86-video-nouveau mesa
                note_failure "NVIDIA ${NVIDIA_GEN} card: proprietary branch ${NVIDIA_DRIVER_FAMILY} not available; installed nouveau instead."
                flush_failures
              fi
            fi
            ;;
          fedora)
            # Use RPM Fusion for NVIDIA on Fedora
            if ! rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
              echo -e "${STY_YELLOW}[$0]: RPM Fusion (nonfree) is needed for NVIDIA drivers.${STY_RST}"
              x sudo dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
            fi
            x sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda nvidia-vaapi-driver
            ;;
          gentoo)
            echo -e "${STY_YELLOW}[$0]: For NVIDIA on Gentoo, please ensure your kernel config and USE flags are set.${STY_RST}"
            echo -e "${STY_YELLOW}[$0]: See: https://wiki.gentoo.org/wiki/NVIDIA/nvidia-drivers${STY_RST}"
            x sudo emerge --noreplace x11-drivers/nvidia-drivers
            ;;
          *)
            echo -e "${STY_YELLOW}[$0]: NVIDIA detected but no automatic driver install for OS_GROUP_ID=${OS_GROUP_ID}.${STY_RST}"
            echo -e "${STY_YELLOW}[$0]: Please install NVIDIA drivers manually.${STY_RST}"
            ;;
        esac
        ;;
      amd)
        echo -e "${STY_CYAN}[$0]: Installing AMD GPU drivers...${STY_RST}"
        case "$OS_GROUP_ID" in
          arch)
            x sudo pacman -S --needed --noconfirm mesa vulkan-radeon libva-mesa-driver
            # 32-bit Vulkan so Steam/multilib apps don't pull lib32-nvidia-utils
            # as the provider on AMD (best-effort: needs multilib, which Steam needs too).
            try sudo pacman -S --needed --noconfirm lib32-mesa lib32-vulkan-radeon
            ;;
          fedora)
            x sudo dnf install -y mesa-dri-drivers mesa-vulkan-drivers mesa-va-drivers
            ;;
          gentoo)
            echo -e "${STY_YELLOW}[$0]: For AMD on Gentoo, ensure VIDEO_CARDS=\"amdgpu radeonsi\" in make.conf.${STY_RST}"
            x sudo emerge --noreplace media-libs/mesa
            ;;
          *)
            echo -e "${STY_YELLOW}[$0]: AMD GPU detected but no automatic driver install for OS_GROUP_ID=${OS_GROUP_ID}.${STY_RST}"
            ;;
        esac
        ;;
      intel)
        echo -e "${STY_CYAN}[$0]: Installing Intel GPU drivers...${STY_RST}"
        case "$OS_GROUP_ID" in
          arch)
            x sudo pacman -S --needed --noconfirm mesa vulkan-intel intel-media-driver
            try sudo pacman -S --needed --noconfirm lib32-mesa lib32-vulkan-intel
            ;;
          fedora)
            x sudo dnf install -y mesa-dri-drivers mesa-vulkan-drivers intel-media-driver
            ;;
          gentoo)
            echo -e "${STY_YELLOW}[$0]: For Intel on Gentoo, ensure VIDEO_CARDS=\"intel\" in make.conf.${STY_RST}"
            x sudo emerge --noreplace media-libs/mesa
            ;;
          *)
            echo -e "${STY_YELLOW}[$0]: Intel GPU detected but no automatic driver install for OS_GROUP_ID=${OS_GROUP_ID}.${STY_RST}"
            ;;
        esac
        ;;
      vm)
        echo -e "${STY_CYAN}[$0]: Virtual machine detected. Installing VM display drivers...${STY_RST}"
        case "$OS_GROUP_ID" in
          arch)
            x sudo pacman -S --needed --noconfirm mesa xf86-video-vmware
            ;;
          fedora)
            x sudo dnf install -y mesa-dri-drivers xorg-x11-drv-vmware
            ;;
          gentoo)
            x sudo emerge --noreplace media-libs/mesa
            ;;
          *)
            echo -e "${STY_YELLOW}[$0]: VM detected but no automatic driver install for OS_GROUP_ID=${OS_GROUP_ID}.${STY_RST}"
            ;;
        esac
        ;;
    esac
  done

  # Vulkan-provider catch-all: guarantee a (lib32-)vulkan-driver provider exists
  # before Steam / other multilib apps install, so pacman's --noconfirm provider
  # resolution can't fall back to the alphabetically-first one (lib32-nvidia-utils)
  # on AMD/Intel/VM systems. Mirrors archiso install-gpu-drivers.
  if [[ "$OS_GROUP_ID" == "arch" ]]; then
    if ! pacman -T vulkan-driver >/dev/null 2>&1; then
      try sudo pacman -S --needed --noconfirm vulkan-swrast
    fi
    if ! pacman -T lib32-vulkan-driver >/dev/null 2>&1; then
      try sudo pacman -S --needed --noconfirm lib32-vulkan-swrast
    fi
  fi
}


function setup_gamescope(){
  # Runtime dependencies for the gamescope Gaming Mode session. gamescope is also
  # pulled in by the mainstream-gaming package; python-evdev, jq and seatd are
  # listed explicitly as a safety net. --needed makes this a no-op if already
  # installed.
  #
  # The old in-session toggle (a broad /etc/sudoers.d/gamescope, the uinput input
  # proxy, loginctl enable-linger and toggle_gamescope.sh) is gone: Gaming Mode
  # now uses the SteamOS-style SDDM session switch shipped by mainstream-gaming,
  # which carries its own tightly-scoped /etc/sudoers.d/gaming-mode.
  case "$OS_GROUP_ID" in
    arch)
      x sudo pacman -S --needed --noconfirm gamescope python-evdev jq seatd
      ;;
    fedora)
      x sudo dnf install -y gamescope python3-evdev jq seatd
      ;;
    *)
      echo -e "${STY_YELLOW}[$0]: Unsupported OS for gamescope setup. Install gamescope, python-evdev, jq, and seatd manually.${STY_RST}"
      ;;
  esac
}


if [[ "${SKIP_GPUDRIVERS}" != true ]]; then
  showfun setup_gpu_drivers
  v setup_gpu_drivers
fi

showfun install-python-packages
v install-python-packages

showfun setup_user_group
v setup_user_group

showfun setup_sddm_bg_polkit
v setup_sddm_bg_polkit

showfun setup_disk_mounter
v setup_disk_mounter

if command -v systemctl >/dev/null 2>&1; then
  # For Fedora, uinput is required for the virtual keyboard to function, and udev rules enable input group users to utilize it.
  if [[ "$OS_GROUP_ID" == "fedora" ]]; then
    v bash -c "echo uinput | sudo tee /etc/modules-load.d/uinput.conf"
    v bash -c 'echo SUBSYSTEM==\"misc\", KERNEL==\"uinput\", MODE=\"0660\", GROUP=\"input\" | sudo tee /etc/udev/rules.d/99-uinput.rules'
  else
    v bash -c "echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf"
  fi
  # TODO: find a proper way for enable Nix installed ydotool. When running `systemctl --user enable ydotool, it errors "Failed to enable unit: Unit ydotool.service does not exist".
  if [[ ! "${INSTALL_VIA_NIX}" == true ]]; then
    if [[ "$OS_GROUP_ID" == "fedora" ]]; then
      v prepare_systemd_user_service
    fi
    # When $DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR are empty, it commonly means that the current user has been logged in with `su - user` or `ssh user@hostname`. In such case `systemctl --user enable <service>` is not usable. It should be `sudo systemctl --machine=$(whoami)@.host --user enable <service>` instead.
    if [[ ! -z "${DBUS_SESSION_BUS_ADDRESS}" ]]; then
      v systemctl --user enable ydotool --now
    else
      v sudo systemctl --machine=$(whoami)@.host --user enable ydotool --now
    fi
  fi
  v sudo systemctl enable bluetooth --now
  if systemctl list-unit-files firewalld.service >/dev/null 2>&1; then
    v sudo systemctl enable firewalld.service || true
    v sudo install -Dm644 "${REPO_ROOT}/sdata/firewalld/MainstreamWorkstation.xml" /etc/firewalld/zones/MainstreamWorkstation.xml
    if [[ "$(sudo firewall-offline-cmd --get-default-zone 2>/dev/null)" != MainstreamWorkstation ]]; then
      v sudo firewall-offline-cmd --set-default-zone=MainstreamWorkstation
    fi
  fi
  # Enable Bluetooth autoconnect for paired devices
  if [ -f /etc/bluetooth/main.conf ]; then
    v sudo sed -i 's/^#\?AutoEnable\s*=.*/AutoEnable=true/' /etc/bluetooth/main.conf
    grep -q '^AutoEnable' /etc/bluetooth/main.conf || v sudo sed -i '/^\[Policy\]/a AutoEnable=true' /etc/bluetooth/main.conf
  fi
  # Install power button helper and polkit policy
  showfun setup_power_key_polkit
  v setup_power_key_polkit
  # Fix fingerprint bug when sleeping by killing fprintd before sleep
  showfun setup_kill_fprintd_service
  v setup_kill_fprintd_service
  v sudo systemctl enable kill-fprintd.service
  # Visual feedback ('*' per keystroke) at sudo prompts.
  showfun setup_pwfeedback
  v setup_pwfeedback
elif command -v openrc >/dev/null 2>&1; then
  v bash -c "echo 'modules=i2c-dev' | sudo tee -a /etc/conf.d/modules"
  v sudo rc-update add modules boot
  v sudo rc-update add ydotool default
  v sudo rc-update add bluetooth default

  x sudo rc-service ydotool start
  x sudo rc-service bluetooth start
else
  printf "${STY_RED}"
  printf "====================INIT SYSTEM NOT FOUND====================\n"
  printf "${STY_RST}"
  pause
fi

if [[ "$OS_GROUP_ID" == "gentoo" ]]; then
  v sudo chown -R $(whoami):$(whoami) ~/.local/
fi

# Font setup — single source of truth for everything font-related that
# doesn't flow through the shell's own config.json (appearance.fonts.*).
# Covers: GTK defaults (gsettings + settings.ini), system-wide font install
# for non-user-session consumers (SDDM, polkit dialogs, …), and a fontconfig
# cache refresh so the rules deployed by 3.files.sh
# (dots/.config/fontconfig/fonts.conf) take effect immediately.
function setup_fonts(){
  local main_family="Google Sans Flex"
  local mono_family="JetBrains Mono NF"
  local reading_family="Readex Pro"
  local main_pango="${main_family} Medium 11 @opsz=11,wght=500"
  local gtk_font="${main_family} Medium 11"

  # --- GNOME/GTK interface fonts (gsettings) ---
  # font-name is the UI default, document-font-name is used for text-body
  # views (some GTK apps fall back to it for large-text regions), and
  # monospace-font-name drives terminal/code widgets. @opsz/wght are pango
  # 1.52+ variable-font axis overrides.
  v gsettings set org.gnome.desktop.interface font-name            "${main_pango}"
  v gsettings set org.gnome.desktop.interface document-font-name   "${reading_family} 11"
  v gsettings set org.gnome.desktop.interface monospace-font-name  "${mono_family} 11"

  # --- GTK3 / GTK4 settings.ini ---
  # Belt-and-suspenders with gsettings: some GTK3 apps (and some sandboxed
  # launch paths) read settings.ini but not the DConf schema.
  local _gtk3="$HOME/.config/gtk-3.0/settings.ini"
  local _gtk4="$HOME/.config/gtk-4.0/settings.ini"
  mkdir -p "$(dirname "$_gtk3")" "$(dirname "$_gtk4")"
  local _f
  for _f in "$_gtk3" "$_gtk4"; do
    if [[ -f "$_f" ]] && grep -q '^\[Settings\]' "$_f"; then
      if grep -q '^gtk-font-name=' "$_f"; then
        sed -i "s|^gtk-font-name=.*|gtk-font-name=${gtk_font}|" "$_f"
      else
        sed -i "/^\[Settings\]/a gtk-font-name=${gtk_font}" "$_f"
      fi
    else
      printf '[Settings]\ngtk-font-name=%s\n' "${gtk_font}" > "$_f"
    fi
  done

  # --- System-wide install of the main font ---
  # End-4's illogical-impulse-fonts drop Google Sans Flex into the user font
  # dir, which `sddm` and other non-session processes cannot read. The sync is
  # safe to re-run after 3.files.sh installs or updates the user copy.
  sync_google_sans_flex_systemwide

  # --- User fontconfig cache refresh ---
  # The dots/.config/fontconfig/fonts.conf (deployed by 3.files.sh) rewrites
  # sans-serif/Sans/system-ui to Google Sans Flex and biases the default
  # weight to Medium. fc-cache ensures pango/cairo consumers pick it up on
  # next app launch without waiting for the per-dir mtime timer.
  v fc-cache -f >/dev/null 2>&1 || true
}
showfun setup_fonts
v setup_fonts

v gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
v gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
v gsettings set org.gnome.desktop.wm.preferences button-layout ":"

# Set mpv as default video player for all video MIME types
function setup_default_video_player(){
  local video_types=(
    video/mp4
    video/x-matroska
    video/webm
    video/x-msvideo
    video/mpeg
    video/ogg
    video/quicktime
    video/x-flv
    video/3gpp
    video/3gpp2
    video/x-ms-wmv
    video/x-ms-asf
    video/mp2t
    video/vnd.mpegurl
    video/x-m4v
  )
  for mime in "${video_types[@]}"; do
    v xdg-mime default mpv.desktop "$mime"
  done
}
showfun setup_default_video_player
v setup_default_video_player

# Set GNOME Text Editor as default for plain-text and common text-ish MIME types.
# Skipped if the desktop entry isn't present (e.g. gnome-text-editor not installed).
function setup_default_text_editor(){
  local desktop=org.gnome.TextEditor.desktop
  if ! test -f /usr/share/applications/$desktop && ! test -f "$XDG_DATA_HOME/applications/$desktop"; then
    echo -e "${STY_YELLOW}[$0]: $desktop not found; skipping text editor defaults.${STY_RST}"
    return 0
  fi
  local text_types=(
    text/plain
    text/markdown
    text/csv
    text/x-log
    text/x-readme
    text/x-changelog
    text/x-copying
    text/x-makefile
    text/x-patch
    text/x-diff
    text/x-qml
    text/xml
    application/xml
    application/json
  )
  for mime in "${text_types[@]}"; do
    v xdg-mime default "$desktop" "$mime"
  done
}
showfun setup_default_text_editor
v setup_default_text_editor

# Set GNOME Loupe as default for the image MIME types it supports.
# Skipped if the desktop entry isn't installed.
function setup_default_image_viewer(){
  local desktop=org.gnome.Loupe.desktop
  if ! test -f /usr/share/applications/$desktop && ! test -f "$XDG_DATA_HOME/applications/$desktop"; then
    echo -e "${STY_YELLOW}[$0]: $desktop not found; skipping image viewer defaults.${STY_RST}"
    return 0
  fi
  local image_types=(
    image/apng
    image/bmp
    image/gif
    image/jp2
    image/jpeg
    image/png
    image/qoi
    image/tiff
    image/vnd.microsoft.icon
    image/webp
    image/x-dds
    image/x-exr
    image/x-portable-anymap
    image/x-portable-bitmap
    image/x-portable-graymap
    image/x-portable-pixmap
    image/x-qoi
    image/x-tga
    image/x-win-bitmap
    image/x-xbitmap
    image/x-xpixmap
    image/svg+xml
    image/svg+xml-compressed
    image/avif
    image/heic
    image/jxl
  )
  for mime in "${image_types[@]}"; do
    v xdg-mime default "$desktop" "$mime"
  done
}
showfun setup_default_image_viewer
v setup_default_image_viewer

# Optional: Limine + Snapper automatic backup setup (Arch, btrfs, UEFI only)
function setup_limine_snapper(){
  local ROOT_FSTYPE
  ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "")
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    echo -e "${STY_YELLOW}[$0]: Limine + Snapper setup is only supported on Arch Linux. Skipping.${STY_RST}"
    return 0
  fi
  if [[ ! -d /sys/firmware/efi ]]; then
    echo -e "${STY_YELLOW}[$0]: System is not booted in UEFI mode. Skipping limine + snapper setup.${STY_RST}"
    return 0
  fi
  if [[ "$ROOT_FSTYPE" != "btrfs" ]]; then
    echo -e "${STY_YELLOW}[$0]: Root filesystem is not btrfs (found: ${ROOT_FSTYPE:-unknown}). Skipping limine + snapper setup.${STY_RST}"
    return 0
  fi
  echo -e "${STY_CYAN}[$0]: Your system qualifies for limine + snapper automatic backup setup.${STY_RST}"
  echo "  This will:"
  echo "    - Replace your current bootloader with limine"
  echo "    - Configure snapper for automatic btrfs snapshots (20% space, max 5)"
  echo "    - Add snapshot entries to the limine boot menu"
  echo ""
  local p
  if $ask; then
    read -rp "Set up limine + snapper? [y/N] " p
  else
    p=y
  fi
  if [[ "$p" =~ ^[Yy]$ ]]; then
    x sudo bash "${REPO_ROOT}/scripts/limine-snapper/setup-limine-snapper.sh" --yes
    # Deploy the non-interactive restore wrapper used by the settings recovery page.
    # Uses expect to handle /dev/tty prompts that pipe-based automation cannot reach.
    if [[ -f "${REPO_ROOT}/scripts/limine-snapper/limine-restore-auto" ]]; then
      x sudo install -m 755 "${REPO_ROOT}/scripts/limine-snapper/limine-restore-auto" /usr/local/bin/limine-restore-auto
      echo -e "${STY_CYAN}[$0]: limine-restore-auto installed to /usr/local/bin/${STY_RST}"
    else
      echo -e "${STY_YELLOW}[$0]: scripts/limine-snapper/limine-restore-auto not found — skipping. Recovery page restore button will not work.${STY_RST}"
    fi
  else
    echo -e "${STY_BLUE}[$0]: Skipping limine + snapper setup.${STY_RST}"
  fi
}
function setup_update_helper(){
  # Install /usr/local/bin/mainstream-update-helper — the privileged
  # script invoked by the Quickshell Update settings panel
  # (UpdateConfig.qml). The helper writes a *temporary* narrow NOPASSWD
  # rule scoped to the calling user, runs topgrade for system updates,
  # drops to the user for yay/paru AUR builds, and removes the temp
  # rule on every exit path. No persistent NOPASSWD on disk.
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    echo -e "${STY_YELLOW}[$0]: update helper setup is currently Arch-only. Skipping.${STY_RST}"
    return 0
  fi
  x sudo install -Dm755 "${REPO_ROOT}/sdata/update/mainstream-update-helper" \
      /usr/local/bin/mainstream-update-helper
}

function setup_updatems(){
  # Install /usr/local/bin/updatems — the user-facing dotfiles refresh
  # command. Lightweight wrapper around `./setup exp-update` that gates
  # on a tag-bump check against the upstream MainstreamOS/dots-hyprland
  # remote, auto-clones the dotfiles repo if absent, and auto-stashes
  # local edits before applying. Invoked standalone OR from the
  # mainstream-update-helper as the "Dotfiles" step (section 5).
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    echo -e "${STY_YELLOW}[$0]: updatems setup is currently Arch-only. Skipping.${STY_RST}"
    return 0
  fi
  x sudo install -Dm755 "${REPO_ROOT}/sdata/update/updatems" \
      /usr/local/bin/updatems
}

function setup_updatems_system(){
  # Install /usr/local/bin/updatems-system — the root-context companion
  # to updatems that refreshes system-level files (Plymouth theme, SDDM
  # polkit + bg helper, and the update tooling itself) after a tag bump.
  # Invoked from mainstream-update-helper section 5b right after the
  # user-level updatems step. File copies only — initramfs rebuild and
  # kernel-cmdline rewrite are NOT done here (see ./setup install-setups
  # for those install-time concerns).
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    echo -e "${STY_YELLOW}[$0]: updatems-system setup is currently Arch-only. Skipping.${STY_RST}"
    return 0
  fi
  x sudo install -Dm755 "${REPO_ROOT}/sdata/update/updatems-system" \
      /usr/local/bin/updatems-system
}

function setup_pacman_nopasswd(){
  # Grant NOPASSWD for pacman so makepkg and the package installs can run
  # (e.g. limine-snapper-sync) without prompting mid-install.
  # Removed again by teardown_pacman_nopasswd after the relevant installs.
  local _user; _user="$(whoami)"
  x sudo bash -c "cat > /etc/sudoers.d/install-pacman-nopasswd << EOF
${_user} ALL=(ALL) NOPASSWD: /usr/bin/pacman
EOF"
  x sudo chmod 440 /etc/sudoers.d/install-pacman-nopasswd
}

function teardown_pacman_nopasswd(){
  x sudo rm -f /etc/sudoers.d/install-pacman-nopasswd
}

function _limine_default_upsert(){
  local key="$1"
  local value="$2"
  local config_file="/etc/default/limine"
  local _tmp
  local _line
  local _found=false

  _tmp=$(mktemp)
  if [[ -f "$config_file" ]]; then
    while IFS= read -r _line || [[ -n "$_line" ]]; do
      if [[ "$_line" =~ ^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*= ]]; then
        printf '%s=%s\n' "$key" "$value" >> "$_tmp"
        _found=true
      else
        printf '%s\n' "$_line" >> "$_tmp"
      fi
    done < "$config_file"
  fi
  if ! $_found; then
    [[ -s "$_tmp" ]] && printf '\n' >> "$_tmp"
    printf '%s=%s\n' "$key" "$value" >> "$_tmp"
  fi
  sudo install -m 644 -D "$_tmp" "$config_file"
  rm -f "$_tmp"
}

function _limine_configure_generator_defaults(){
  # Keep Limine entry naming explicit instead of implicitly following
  # /etc/os-release PRETTY_NAME. This makes the boot menu stable even if
  # branding overlays change later.
  if command -v limine-update >/dev/null 2>&1 || command -v limine-mkinitcpio >/dev/null 2>&1 || [[ -f /etc/default/limine ]]; then
    _limine_default_upsert "TARGET_OS_NAME" '"Mainstream OS\\"'
    # Suppress the auto-generated "/EFI fallback" (and any systemd-boot /
    # rEFInd) top-level entry. $ESP/EFI/BOOT/BOOTX64.EFI is Limine itself on
    # this install, so that entry would just chainload Limine into itself.
    _limine_default_upsert "FIND_BOOTLOADERS" "no"
  fi
}

MKINITCPIO_SYSTEMD_HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems)

function _mkinitcpio_ensure_systemd_stack(){
  [[ "$OS_GROUP_ID" == "arch" ]] || return 0
  sudo pacman -S --needed --noconfirm systemd plymouth
}

function _mkinitcpio_enforce_systemd_hooks(){
  [[ "$OS_GROUP_ID" == "arch" ]] || return 0
  local hook_line="HOOKS=(${MKINITCPIO_SYSTEMD_HOOKS[*]})"

  if [[ ! -f /etc/mkinitcpio.conf ]]; then
    echo -e "${STY_YELLOW}[$0]: /etc/mkinitcpio.conf not found — cannot set systemd initramfs hooks.${STY_RST}"
    return 1
  fi

  if grep -qxF "$hook_line" /etc/mkinitcpio.conf; then
    echo -e "${STY_BLUE}[$0]: systemd mkinitcpio hooks already configured.${STY_RST}"
    return 0
  fi

  if grep -qE '^HOOKS=\(' /etc/mkinitcpio.conf; then
    sudo sed -i -E "s|^HOOKS=\([^)]*\).*|${hook_line}|" /etc/mkinitcpio.conf
  else
    printf '%s\n' "$hook_line" | sudo tee -a /etc/mkinitcpio.conf > /dev/null
  fi
  echo -e "${STY_CYAN}[$0]: Set mkinitcpio hooks to: ${MKINITCPIO_SYSTEMD_HOOKS[*]}${STY_RST}"
}

# Rebuild initramfs. On systems with limine-mkinitcpio-hook installed, prefers
# `limine-mkinitcpio` which regenerates both the initramfs AND /boot/limine.conf
# boot entries in one pass (and silences the "use limine-mkinitcpio instead"
# warning that plain `mkinitcpio -P` would emit). Falls back to `mkinitcpio -P`
# when the hook isn't installed.
function _initramfs_rebuild(){
  _mkinitcpio_ensure_systemd_stack || return 1
  _mkinitcpio_enforce_systemd_hooks || return 1
  if command -v limine-mkinitcpio >/dev/null 2>&1; then
    _limine_configure_generator_defaults || true
    echo -e "${STY_CYAN}[$0]: Running limine-mkinitcpio (rebuilds initramfs + limine boot entries)...${STY_RST}"
    sudo limine-mkinitcpio
  else
    echo -e "${STY_CYAN}[$0]: Running mkinitcpio -P...${STY_RST}"
    sudo mkinitcpio -P
  fi
}

function setup_plymouth(){
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    echo -e "${STY_YELLOW}[$0]: Plymouth setup is only supported on Arch Linux. Skipping.${STY_RST}"
    return 0
  fi
  echo -e "${STY_CYAN}[$0]: Installing Plymouth boot splash with Mainstream theme...${STY_RST}"
  # sudo pacman is NOPASSWD within this install window; --noconfirm suppresses
  # pacman's "Proceed with installation? [Y/n]" prompt
  if ! _mkinitcpio_ensure_systemd_stack; then
    echo -e "${STY_YELLOW}[$0]: systemd/Plymouth failed to install — boot splash and systemd initramfs hooks will be skipped.${STY_RST}"
    return 0
  fi
  # Deploy the Mainstream theme bundled in the repo. Overwrites any previously
  # installed copy so updates to assets/script flow through on reinstall.
  local theme_src="${REPO_ROOT}/sdata/plymouth/mainstream"
  local theme_dst="/usr/share/plymouth/themes/mainstream"
  if [[ -d "$theme_src" ]]; then
    sudo rm -rf "$theme_dst"
    sudo cp -r "$theme_src" "$theme_dst"
    sudo chown -R root:root "$theme_dst"
    sudo find "$theme_dst" -type d -exec chmod 755 {} +
    sudo find "$theme_dst" -type f -exec chmod 644 {} +
    echo -e "${STY_CYAN}[$0]: Installed Mainstream theme to ${theme_dst}${STY_RST}"
  else
    echo -e "${STY_YELLOW}[$0]: ${theme_src} not found — falling back to bgrt theme.${STY_RST}"
  fi
  # Non-interactive — writes to /etc/plymouth/plymouthd.conf
  if [[ -d "$theme_dst" ]]; then
    sudo plymouth-set-default-theme mainstream
  else
    sudo plymouth-set-default-theme bgrt
  fi
  # Persist the desired boot flags in /etc/kernel/cmdline so future
  # limine-mkinitcpio regenerations keep the splash/silencing settings.
  echo -e "${STY_CYAN}[$0]: Ensuring the plymouth splash flags are in the managed kernel cmdline...${STY_RST}"
  cmdline_upsert quiet splash rd.udev.log_level=3 vt.global_cursor_default=0 consoleblank=0 nowatchdog nmi_watchdog=0
  # Quiet the journal's audit spam without disabling the audit subsystem (the old
  # audit=0 boot flag did the latter).
  x sudo systemctl mask systemd-journald-audit.socket || true

  # Rebuild initramfs so plymouth is active on next boot. On systems with
# limine-mkinitcpio-hook installed, this also regenerates /boot/limine.conf
# boot entries from /etc/kernel/cmdline, keeping everything in sync. When
# setup_gpu_autoconfig also runs, it rebuilds again after adding MODULES —
# that's a small cost for keeping plymouth working standalone.
  _initramfs_rebuild
  echo -e "${STY_GREEN}[$0]: Plymouth BGRT theme configured.${STY_RST}"
}

# Shared GPU detection + config library -- the single source of truth for both
# the dots ./setup and archiso install paths (sdata/lib/gpu-config.sh). On the
# live system, writes go through sudo. The small-ESP early-KMS guard is
# disabled here: dots installs use the host's existing boot setup (no UKI on
# the ESP), so ESP size does not constrain the initramfs.
source "${REPO_ROOT}/sdata/lib/gpu-config.sh"
GPU_SUDO=sudo
GPU_EARLY_KMS_ESP_THRESHOLD=0

function setup_gpu_autoconfig(){
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    echo -e "${STY_YELLOW}[$0]: GPU autoconfig is only implemented for Arch Linux. Skipping.${STY_RST}"
    return 0
  fi
  if ! gpu_detect; then
    echo -e "${STY_YELLOW}[$0]: No GPU detected — skipping autoconfig.${STY_RST}"
    return 0
  fi
  echo -e "${STY_CYAN}[$0]: GPU autoconfig — Intel=$HAS_INTEL AMD=$HAS_AMD NVIDIA=$HAS_NVIDIA Hybrid=$IS_HYBRID${STY_RST}"
  gpu_apply_autoconfig
  _initramfs_rebuild
}

# Apply dotfile-level GPU tweaks (NVIDIA Wayland env vars in hypr custom
# env.lua, dpms delays in hypridle.conf, AQ_DRM_DEVICES for hybrid NVIDIA).
# Separated from setup_gpu_autoconfig because these files only exist after
# 3.files.sh deploys dotfiles. Safe to call more than once — each insertion is
# idempotent and skips silently when the target file is missing.
function setup_gpu_hypr_tweaks(){
  if [[ "$OS_GROUP_ID" != "arch" ]]; then return 0; fi
  # Re-detect in case flags aren't set (when called from 3.files.sh directly).
  if [[ -z "${HAS_NVIDIA:-}" ]]; then
    gpu_detect >/dev/null 2>&1 || return 0
  fi
  local _env_lua="$HOME/.config/hypr/custom/env.lua"
  if [[ ! -f "$_env_lua" ]]; then
    echo -e "${STY_YELLOW}[$0]: $_env_lua not found — deferring hypr GPU tweaks until after dotfiles are deployed.${STY_RST}"
    return 0
  fi
  gpu_apply_hypr_tweaks "$HOME"
}

showfun setup_pacman_nopasswd
v setup_pacman_nopasswd

# Install the privileged helper the Quickshell Update panel invokes.
showfun setup_update_helper
v setup_update_helper

# Install the updatems dotfiles-refresh command (section 5 of the helper).
showfun setup_updatems
v setup_updatems

# Install the updatems-system root-context companion (section 5b).
showfun setup_updatems_system
v setup_updatems_system

showfun setup_limine_snapper
v setup_limine_snapper

# setup_plymouth runs after setup_limine_snapper so /boot/limine.conf exists
# when we patch kernel_cmdline with splash/silencing args.
showfun setup_plymouth
v setup_plymouth

# setup_gpu_autoconfig runs after setup_plymouth so its cmdline additions
# accumulate on top of the plymouth/silencing args already in limine.conf, and
# its initramfs rebuild picks up both the plymouth hook and any new GPU modules.
showfun setup_gpu_autoconfig
v setup_gpu_autoconfig

# SDDM + pixie-sddm theme
function setup_sddm_pixie(){
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    echo -e "${STY_YELLOW}[$0]: SDDM + pixie theme setup is only supported on Arch Linux. Skipping.${STY_RST}"
    return 0
  fi
  local p
  if $ask; then
    read -rp "Install SDDM with pixie theme? [y/N] " p
  else
    p=y
  fi
  if [[ "$p" =~ ^[Yy]$ ]]; then
    x sudo bash "${REPO_ROOT}/scripts/setup-sddm-pixie.sh"
  else
    echo -e "${STY_BLUE}[$0]: Skipping SDDM + pixie theme setup.${STY_RST}"
  fi
}
showfun setup_sddm_pixie
v setup_sddm_pixie

# Audio defaults — enable the units that the mainstream-audio package ships.
#
# The mainstream-audio package installs three files that fix the two most
# common audio failure modes on a fresh install:
#   * /etc/wireplumber/wireplumber.conf.d/51-disable-hdmi-default.conf
#     — lowers HDMI/DP sink priority below analog so WirePlumber's
#       default-picker doesn't silently route to a discrete GPU's HDA.
#   * /usr/lib/systemd/system/mainstream-audio-firstboot.service
#   * /usr/lib/mainstream/audio-firstboot
#     — first-boot oneshot: alsactl init for UCM-driven codec defaults,
#       unmute Master/Speaker/Headphone/PCM/Front, disable flaky Auto-Mute,
#       persist mixer state via alsactl store.
#
# See sdata/dist-arch/mainstream-audio/ for the sources. The package is
# pulled in earlier in the install loop (install-deps.sh) so all three
# files exist on disk by the time this runs.
#
# What this function does that the package can't: turn the units on. Arch
# packages don't auto-enable services on install, and we don't ship a
# /usr/lib/systemd/system-preset/ file because explicit enables are easier
# to reason about in two places (this script + the archiso install-dotfiles).
function setup_audio_defaults(){
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    echo -e "${STY_YELLOW}[$0]: audio defaults setup is currently Arch-only. Skipping.${STY_RST}"
    return 0
  fi

  if [[ ! -f /usr/lib/systemd/system/mainstream-audio-firstboot.service ]]; then
    echo -e "${STY_YELLOW}[$0]: mainstream-audio-firstboot.service not installed — is mainstream-audio package present? Skipping.${STY_RST}"
    return 0
  fi

  # alsa-restore / alsa-state are usually auto-enabled by alsa-utils'
  # upstream systemd preset; the explicit enable is a cheap safety net
  # against preset changes and is harmless if already on (|| true).
  x sudo systemctl enable mainstream-audio-firstboot.service \
    || echo -e "${STY_YELLOW}[$0]: Failed to enable mainstream-audio-firstboot.service${STY_RST}"
  x sudo systemctl enable alsa-restore.service 2>/dev/null || true
  x sudo systemctl enable alsa-state.service   2>/dev/null || true
}
showfun setup_audio_defaults
v setup_audio_defaults

# Brand /etc/os-release as Mainstream OS so the dots ./setup path matches the ISO
# (which ships a real /etc/os-release). Stock Arch symlinks /etc/os-release to the
# filesystem-owned /usr/lib/os-release; replace the symlink with a real override so
# /usr/lib/os-release stays untouched (no pacman conflicts on filesystem upgrades).
function setup_os_release_branding(){
  [[ "$OS_GROUP_ID" == "arch" ]] || { echo -e "${STY_YELLOW}[$0]: os-release branding is Arch-only. Skipping.${STY_RST}"; return 0; }
  echo -e "${STY_CYAN}[$0]: Branding /etc/os-release as Mainstream OS...${STY_RST}"
  sudo rm -f /etc/os-release
  x sudo tee /etc/os-release >/dev/null <<'EOF'
NAME="Mainstream OS"
PRETTY_NAME="Mainstream OS"
ID=arch
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;0;141;195"
HOME_URL="https://mainstreamos.org/"
DOCUMENTATION_URL="https://mainstreamos.org/docs"
SUPPORT_URL="https://github.com/MainstreamOS/dots-hyprland/discussions"
BUG_REPORT_URL="https://github.com/MainstreamOS/dots-hyprland/issues"
PRIVACY_POLICY_URL="https://mainstreamos.org/privacy"
DONATE_URL="https://mainstreamos.org/donate"
LOGO=mainstream-logo
EOF
}
showfun setup_os_release_branding
v setup_os_release_branding

# Set the login shell to zsh to match the ISO (Calamares users.conf shell:
# /usr/bin/zsh). Guarded so it no-ops until mainstream-basic carries zsh.
function setup_default_shell(){
  [[ "$OS_GROUP_ID" == "arch" ]] || return 0
  command -v zsh >/dev/null 2>&1 || { echo -e "${STY_YELLOW}[$0]: zsh not installed — skipping default-shell change.${STY_RST}"; return 0; }
  local _zsh _cur
  _zsh="$(command -v zsh)"
  _cur="$(getent passwd "$(whoami)" | cut -d: -f7)"
  if [[ "$_cur" != "$_zsh" ]]; then
    echo -e "${STY_CYAN}[$0]: Setting login shell to ${_zsh}...${STY_RST}"
    x sudo usermod -s "$_zsh" "$(whoami)"
  fi
}
showfun setup_default_shell
v setup_default_shell

# Printing: cups is socket-activated on the ISO (cups.service starts on the
# first print job), so enable cups.socket rather than the service. Guarded so it
# no-ops until mainstream-basic carries cups.
function setup_printing(){
  [[ "$OS_GROUP_ID" == "arch" ]] || return 0
  pacman -Qq cups >/dev/null 2>&1 || { echo -e "${STY_YELLOW}[$0]: cups not installed — skipping printing setup.${STY_RST}"; return 0; }
  echo -e "${STY_CYAN}[$0]: Enabling cups.socket (print spooler on demand)...${STY_RST}"
  x sudo systemctl enable cups.socket
}
showfun setup_printing
v setup_printing

# NetworkManager-wait-online delays boot until the network is up — a desktop
# doesn't need it (NM brings the network up asynchronously after login). Disable
# it to shave boot time. Best-effort: harmless if it isn't enabled.
function setup_network_wait(){
  [[ "$OS_GROUP_ID" == "arch" ]] || return 0
  echo -e "${STY_CYAN}[$0]: Disabling NetworkManager-wait-online (boot speed)...${STY_RST}"
  try sudo systemctl disable NetworkManager-wait-online.service
}
showfun setup_network_wait
v setup_network_wait

# Raise the inotify watch limit so Quickshell's file watchers (config + style
# hot-reload, generated colors, wallpaper) don't hit the kernel default ceiling.
function setup_inotify_limits(){
  x sudo bash -c "printf 'fs.inotify.max_user_watches = 524288\nfs.inotify.max_user_instances = 512\n' > /etc/sysctl.d/99-mainstream-inotify.conf && sysctl --system >/dev/null 2>&1 || true"
}
showfun setup_inotify_limits
v setup_inotify_limits

# mpris-hyprland: per-tab MPRIS bridge for Firefox/Zen/LibreWolf/etc.
# Replaces plasma-browser-integration with a lightweight (~2MB binary)
# alternative that doesn't drag in the KDE chain. Always installed —
# the media-control panel needs this to show track info, position,
# YouTube thumbnails, and a working seek bar for any Firefox-based
# browser. Auto-detects which forks are installed and writes per-fork
# native-messaging manifests for each.
function setup_mpris_hyprland(){
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    echo -e "${STY_YELLOW}[$0]: mpris-hyprland setup is currently Arch-only. Skipping.${STY_RST}"
    return 0
  fi
  # On Mainstream OS ISO installs it's already provided prebuilt by the
  # [mainstream] repo — nothing to do. Only build it for standalone installs
  # that don't have it yet. The setup script makepkg's the PKGBUILD, which
  # pulls its own build deps (rust/cargo/zip/git) via makepkg -s, so no
  # toolchain needs to be pre-present.
  if pacman -Qq mpris-hyprland &>/dev/null; then
    echo -e "${STY_GREEN}[$0]: mpris-hyprland already installed — skipping.${STY_RST}"
    return 0
  fi
  x bash "${REPO_ROOT}/scripts/setup-mpris-hyprland.sh" \
    || echo -e "${STY_YELLOW}[$0]: mpris-hyprland install hit an error — see above. Continuing with the rest of setup.${STY_RST}"
}
showfun setup_mpris_hyprland
v setup_mpris_hyprland

showfun teardown_pacman_nopasswd
v teardown_pacman_nopasswd

showfun setup_gamescope
v setup_gamescope
