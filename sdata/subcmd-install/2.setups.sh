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

  if [[ "$OS_GROUP_ID" == "fedora" ]]; then
    x sudo usermod -aG video,input "$(whoami)"
  else
    x sudo usermod -aG video,i2c,input "$(whoami)"
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
            # nvidia-dkms works across kernels; nvidia-utils for OpenGL, nvidia-settings for GUI config.
            # modprobe options + cmdline + mkinitcpio modules are handled by setup_gpu_autoconfig later.
            x sudo pacman -S --needed --noconfirm nvidia-dkms nvidia-utils nvidia-settings egl-wayland
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
}


function setup_gamescope(){
  # Install python-evdev — required for the input proxy in toggle_gamescope.sh.
  # jq and seatd are pulled in by other packages on Arch but listed explicitly
  # as a safety net. --needed makes this a no-op if already installed.
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

  # Sudoers file — allows toggle_gamescope.sh to stop/start sddm, chvt,
  # seatd, python3, setcap, and systemd-run without a password prompt.
  # chmod 440 is required — sudo refuses world-readable sudoers files.
  local _user
  _user=$(whoami)
  sudo bash -c "cat > /etc/sudoers.d/gamescope << EOF
Defaults:${_user} !requiretty
${_user} ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop sddm
${_user} ALL=(ALL) NOPASSWD: /usr/bin/systemctl start sddm
${_user} ALL=(ALL) NOPASSWD: /usr/bin/chvt
${_user} ALL=(ALL) NOPASSWD: /usr/bin/systemd-run
${_user} ALL=(ALL) NOPASSWD: /usr/bin/python3
${_user} ALL=(ALL) NOPASSWD: /usr/bin/seatd
${_user} ALL=(ALL) NOPASSWD: /usr/bin/setcap
EOF"
  x sudo chmod 440 /etc/sudoers.d/gamescope

  # udev rule — allows the input proxy to create a UInput virtual device.
  # On Arch this is not added elsewhere in this script so we add it here.
  # On Fedora it is already handled in the systemd block above.
  if [[ "$OS_GROUP_ID" != "fedora" ]]; then
    x sudo bash -c 'echo KERNEL=="uinput", MODE="0660", GROUP="input" | tee /etc/udev/rules.d/99-uinput.rules'
    x sudo udevadm control --reload-rules
    x sudo udevadm trigger || true
  fi

  # Enable linger so the user's systemd session persists independently
  # of SDDM being stopped. Safe to call here since we are on a live system.
  x loginctl enable-linger "$_user"

  # Ensure the toggle script is executable — safety net in case permissions
  # were lost during dotfile deployment.
  local _toggle="$HOME/.config/hypr/hyprland/scripts/toggle_gamescope.sh"
  if [[ -f "$_toggle" ]]; then
    x chmod +x "$_toggle"
  else
    echo -e "${STY_YELLOW}[$0]: toggle_gamescope.sh not found at $_toggle — skipping chmod.${STY_RST}"
  fi
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

if [[ ! -z $(systemctl --version) ]]; then
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
elif [[ ! -z $(openrc --version) ]]; then
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
function setup_pacman_nopasswd(){
  # Grant NOPASSWD for pacman so yay/makepkg can install AUR packages
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

# Upsert args into /etc/kernel/cmdline (single-line canonical kernel cmdline on
# Arch). This is the source-of-truth consumed by mkinitcpio when building UKIs
# (Unified Kernel Images) — UKIs embed the cmdline into the .efi at build time,
# so direct edits to generated Limine entries would never reach UKI boot
# entries. limine-entry-tool also reads this file first for protocol: linux
# entries, so writing here covers both paths.
# Seeds the file from the currently configured cmdline when absent, preferring
# /boot/limine.conf as a compatibility fallback and otherwise /proc/cmdline
# stripped of BOOT_IMAGE=/initrd=. Then upserts by key-dedup like the other
# helpers.
function _kernel_cmdline_upsert(){
  local cmdline_file="/etc/kernel/cmdline"
  local -a new_args=("$@")
  (( ${#new_args[@]} == 0 )) && return 0
  local -a existing=()
  if [[ -f "$cmdline_file" ]]; then
    local _base; _base=$(tr '\n' ' ' < "$cmdline_file")
    read -r -a existing <<< "$_base"
  else
    local _seed=""
    if [[ -f /boot/limine.conf ]]; then
      _seed=$(awk '/^[[:space:]]*(kernel_cmdline|cmdline):[[:space:]]*/ {
        sub(/^[[:space:]]*(kernel_cmdline|cmdline):[[:space:]]*/, "");
        print; exit
      }' /boot/limine.conf)
    fi
    if [[ -z "$_seed" && -r /proc/cmdline ]]; then
      _seed=$(cat /proc/cmdline)
    fi
    local -a _toks; read -r -a _toks <<< "$_seed"
    local _t
    for _t in "${_toks[@]}"; do
      [[ "$_t" == BOOT_IMAGE=* ]] && continue
      [[ "$_t" == initrd=* ]] && continue
      existing+=("$_t")
    done
  fi
  local -a _keys=() kept=()
  local _a
  for _a in "${new_args[@]}"; do _keys+=("${_a%%=*}"); done
  local _t _tk _k _skip
  for _t in "${existing[@]}"; do
    [[ -z "$_t" ]] && continue
    _tk="${_t%%=*}"
    _skip=false
    for _k in "${_keys[@]}"; do
      if [[ "$_tk" == "$_k" ]]; then _skip=true; break; fi
    done
    $_skip || kept+=("$_t")
  done
  kept+=("${new_args[@]}")
  local _tmp; _tmp=$(mktemp)
  printf '%s\n' "${kept[*]}" > "$_tmp"
  sudo install -m 644 -D "$_tmp" "$cmdline_file"
  rm -f "$_tmp"
}

# Persist kernel cmdline args in the canonical limine-entry-tool source file.
# `limine-update` / `limine-mkinitcpio` regenerate /boot/limine.conf from
# /etc/kernel/cmdline, so we avoid patching the generated config directly.
function _limine_apply_cmdline_args(){
  local -a args=("$@")
  (( ${#args[@]} == 0 )) && return 0
  _kernel_cmdline_upsert "${args[@]}"
}

MKINITCPIO_SYSTEMD_HOOKS=(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)

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
  echo -e "${STY_CYAN}[$0]: Adding plymouth + silencing args to the managed kernel cmdline...${STY_RST}"
  if ! _limine_apply_cmdline_args quiet splash rd.udev.log_level=3 vt.global_cursor_default=0 consoleblank=0 nowatchdog nmi_watchdog=0 audit=0; then
    echo -e "${STY_YELLOW}[$0]: Failed to update /etc/kernel/cmdline for plymouth.${STY_RST}"
  fi

  # Rebuild initramfs so plymouth is active on next boot. On systems with
# limine-mkinitcpio-hook installed, this also regenerates /boot/limine.conf
# boot entries from /etc/kernel/cmdline, keeping everything in sync. When
# setup_gpu_autoconfig also runs, it rebuilds again after adding MODULES —
# that's a small cost for keeping plymouth working standalone.
  _initramfs_rebuild
  echo -e "${STY_GREEN}[$0]: Plymouth BGRT theme configured.${STY_RST}"
}

# Idempotent helper: add kernel modules to /etc/mkinitcpio.conf MODULES=(...).
# Does nothing if the module is already present.
function _mkinitcpio_add_modules(){
  local mod
  for mod in "$@"; do
    if ! grep -qE "\bMODULES=\([^)]*\b${mod}\b" /etc/mkinitcpio.conf; then
      sudo sed -i "s/^MODULES=(/MODULES=(${mod} /" /etc/mkinitcpio.conf
      echo -e "${STY_CYAN}[$0]: Added initramfs module: ${mod}${STY_RST}"
    fi
  done
}

# Idempotent helper: remove a hook from /etc/mkinitcpio.conf HOOKS=(...).
# Only operates on the HOOKS line so we don't accidentally touch MODULES etc.
function _mkinitcpio_remove_hook(){
  local hook="$1"
  if grep -qE "^HOOKS=\([^)]*\b${hook}\b" /etc/mkinitcpio.conf; then
    sudo sed -i -E "/^HOOKS=\(/ s/\b${hook}\b *//" /etc/mkinitcpio.conf
    echo -e "${STY_CYAN}[$0]: Removed initramfs hook: ${hook}${STY_RST}"
  fi
}

# Append an 'env = KEY,VALUE' line into the user's hypr custom env.conf if the
# key isn't already set. Prints a warning (and returns 1) if the file doesn't
# exist, which is the normal case on first install before dotfiles are deployed.
function _hypr_env_upsert(){
  local _key="$1" _val="$2"
  local _env_conf="$HOME/.config/hypr/custom/env.conf"
  [[ -f "$_env_conf" ]] || return 1
  if ! grep -q "^env = ${_key}" "$_env_conf"; then
    printf 'env = %s,%s\n' "$_key" "$_val" >> "$_env_conf"
    echo -e "${STY_CYAN}[$0]: Added hypr env: ${_key}=${_val}${STY_RST}"
  fi
}

# Inject short sleeps before 'hyprctl dispatch dpms on' in hypridle.conf so
# NVIDIA DRM/KMS has time to finish reinit after resume, avoiding the session
# recover prompt. AMD/Intel don't need this (i915/amdgpu resume synchronously).
function _hypr_fix_hypridle_for_nvidia(){
  local _hypridle="$HOME/.config/hypr/hypridle.conf"
  [[ -f "$_hypridle" ]] || return 1
  if grep -qE 'after_sleep_cmd\s*=.*hyprctl dispatch dpms on' "$_hypridle" \
      && ! grep -qE 'after_sleep_cmd\s*=.*sleep\s+[0-9].*&&.*hyprctl dispatch dpms on' "$_hypridle"; then
    sed -i '/after_sleep_cmd/s|hyprctl dispatch dpms on|sleep 2 \&\& hyprctl dispatch dpms on|' "$_hypridle"
    echo -e "${STY_CYAN}[$0]: Added 2s dpms-on delay to after_sleep_cmd (NVIDIA resume fix).${STY_RST}"
  fi
  if grep -qE 'on-resume\s*=.*hyprctl dispatch dpms on' "$_hypridle" \
      && ! grep -qE 'on-resume\s*=.*sleep\s+[0-9].*&&.*hyprctl dispatch dpms on' "$_hypridle"; then
    sed -i '/on-resume/s|hyprctl dispatch dpms on|sleep 1 \&\& hyprctl dispatch dpms on|' "$_hypridle"
    echo -e "${STY_CYAN}[$0]: Added 1s dpms-on delay to on-resume (NVIDIA resume fix).${STY_RST}"
  fi
}

# Detect GPUs by PCI vendor ID and export state flags used by setup_gpu_autoconfig
# and setup_gpu_hypr_tweaks. Safe to call multiple times.
#   HAS_NVIDIA / HAS_AMD / HAS_INTEL — booleans
#   IS_HYBRID                         — true if >1 discrete vendor present
#   NVIDIA_PCI_DEC                    — decimal PCI device ID of first NVIDIA card (0 if none)
function _gpu_detect(){
  HAS_NVIDIA=false; HAS_AMD=false; HAS_INTEL=false; IS_HYBRID=false
  NVIDIA_PCI_DEC=0
  command -v lspci >/dev/null 2>&1 || { echo -e "${STY_YELLOW}[$0]: lspci not found — cannot detect GPU.${STY_RST}"; return 1; }
  local gpu_lines; gpu_lines=$(lspci -nn 2>/dev/null | grep -iE 'VGA|3D|Display' || true)
  [[ -z "$gpu_lines" ]] && return 1
  echo "$gpu_lines" | grep -q '\[10de:' && HAS_NVIDIA=true || true
  echo "$gpu_lines" | grep -q '\[1002:' && HAS_AMD=true    || true
  echo "$gpu_lines" | grep -q '\[8086:' && HAS_INTEL=true  || true
  local _count=0
  $HAS_NVIDIA && ((_count++)) || true
  $HAS_AMD    && ((_count++)) || true
  $HAS_INTEL  && ((_count++)) || true
  [[ $_count -gt 1 ]] && IS_HYBRID=true || true
  if $HAS_NVIDIA; then
    local _id
    _id=$(echo "$gpu_lines" | grep -oE '\[10de:[0-9a-fA-F]{4}\]' | head -1 | grep -oE '[0-9a-fA-F]{4}' | head -1)
    [[ -n "$_id" ]] && NVIDIA_PCI_DEC=$((16#$_id)) || NVIDIA_PCI_DEC=0
  fi
  return 0
}

# Configure system-level bits for the detected GPU(s): kernel modules in the
# initramfs, modprobe options, kernel cmdline args in /etc/kernel/cmdline, and
# NVIDIA power-management systemd services. Ported from the archiso post-install
# script but adapted for a running (non-chroot) system — DKMS modules build
# against the live kernel so the initramfs rebuild runs in the same pass. Skips hypr
# dotfile edits here; those are handled by setup_gpu_hypr_tweaks after dotfiles
# are deployed in 3.files.sh.
function setup_gpu_autoconfig(){
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    echo -e "${STY_YELLOW}[$0]: GPU autoconfig is only implemented for Arch Linux. Skipping.${STY_RST}"
    return 0
  fi
  if ! _gpu_detect; then
    echo -e "${STY_YELLOW}[$0]: No GPU detected — skipping autoconfig.${STY_RST}"
    return 0
  fi
  echo -e "${STY_CYAN}[$0]: GPU autoconfig — Intel=$HAS_INTEL AMD=$HAS_AMD NVIDIA=$HAS_NVIDIA Hybrid=$IS_HYBRID${STY_RST}"

  local -a cmdline_args=()

  # --- Intel (runs first so i915 appears before NVIDIA in MODULES) ---
  if $HAS_INTEL; then
    local _intel_line _is_arc=false
    _intel_line=$(lspci 2>/dev/null | grep -iE "Intel.*(Graphics|UHD|HD|Iris|Arc|Xe)" | head -1 || true)
    echo "$_intel_line" | grep -iqE "Arc|Xe|A[3-7][0-9]{2}" && _is_arc=true || true
    if $_is_arc; then
      echo -e "${STY_CYAN}[$0]: Intel Arc/Xe detected — using xe driver.${STY_RST}"
      _mkinitcpio_add_modules xe
    else
      echo -e "${STY_CYAN}[$0]: Intel (i915) detected.${STY_RST}"
      _mkinitcpio_add_modules i915
      $IS_HYBRID || cmdline_args+=("i915.modeset=1")
    fi
  fi

  # --- AMD ---
  if $HAS_AMD; then
    local _amd_line _is_old_amd=false _is_rdna4=false
    _amd_line=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display" | grep -iE "AMD|ATI|Radeon" | head -1 || true)
    # Pre-GCN naming patterns → legacy radeon path
    echo "$_amd_line" | grep -iqE "\bHD [2-6][0-9]{3}\b|\bRS[0-9]+\b|\bRV[0-9]+\b|\bR[67][0-9]{2}\b" && _is_old_amd=true || true
    lspci 2>/dev/null | grep -iqE "Navi 4[0-9]|RX 9[0-9]{3}|gfx12" && _is_rdna4=true || true
    if $_is_rdna4; then _is_old_amd=false; fi

    if $_is_old_amd; then
      echo -e "${STY_CYAN}[$0]: Pre-GCN AMD — enabling SI/CIK on amdgpu.${STY_RST}"
      sudo mkdir -p /etc/modprobe.d
      sudo tee /etc/modprobe.d/amdgpu.conf > /dev/null << 'AMDEOF'
options amdgpu si_support=1
options amdgpu cik_support=1
options radeon si_support=0
options radeon cik_support=0
AMDEOF
      _mkinitcpio_add_modules amdgpu radeon
      cmdline_args+=("amdgpu.si_support=1" "amdgpu.cik_support=1")
    else
      echo -e "${STY_CYAN}[$0]: GCN/RDNA AMD — configuring amdgpu.${STY_RST}"
      _mkinitcpio_add_modules amdgpu
      cmdline_args+=("amdgpu.modeset=1")
      if $_is_rdna4; then
        echo -e "${STY_CYAN}[$0]: RDNA 4 — adding sg_display=0 and mem_sleep_default=deep.${STY_RST}"
        # s2idle is broken on Navi 48 through at least 6.17.x; force S3 deep sleep.
        cmdline_args+=("amdgpu.sg_display=0" "mem_sleep_default=deep")
      fi
    fi
  fi

  # --- NVIDIA ---
  if $HAS_NVIDIA; then
    echo -e "${STY_CYAN}[$0]: NVIDIA PCI device ID: $(printf '0x%04x' "$NVIDIA_PCI_DEC") ($NVIDIA_PCI_DEC)${STY_RST}"
    if (( NVIDIA_PCI_DEC >= 1728 )); then
      # Fermi or newer — proprietary nvidia stack. Pre-Fermi stays on nouveau
      # (the default kms hook handles it). Keep kms in HOOKS; NVIDIA is loaded
      # early through MODULES below while the canonical systemd hook order remains
      # intact.
      _mkinitcpio_add_modules nvidia nvidia_modeset nvidia_uvm nvidia_drm
      sudo mkdir -p /etc/modprobe.d
      sudo tee /etc/modprobe.d/nvidia.conf > /dev/null << 'NVIDIAEOF'
options nvidia-drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
NVIDIAEOF
      cmdline_args+=("nvidia_drm.modeset=1")
      local svc
      for svc in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service; do
        sudo systemctl enable "$svc" >/dev/null 2>&1 \
          && echo -e "${STY_CYAN}[$0]: Enabled $svc${STY_RST}" \
          || echo -e "${STY_YELLOW}[$0]: $svc not found (driver version may not ship it).${STY_RST}"
      done
      sudo systemctl enable nvidia-powerd.service >/dev/null 2>&1 || true
    else
      echo -e "${STY_BLUE}[$0]: Pre-Fermi NVIDIA — keeping nouveau (kms hook kept).${STY_RST}"
    fi
  fi

  # --- PRIME (only when we have multiple vendors) ---
  if $IS_HYBRID; then
    echo -e "${STY_CYAN}[$0]: Hybrid GPU detected — configuring PRIME.${STY_RST}"
    if $HAS_NVIDIA && $HAS_INTEL; then
      _mkinitcpio_add_modules i915
      cmdline_args+=("i915.modeset=1")
    elif $HAS_NVIDIA && $HAS_AMD; then
      _mkinitcpio_add_modules amdgpu
    fi
  fi

  # --- Generic S3 deep sleep preference when available ---
  if [[ -f /sys/power/mem_sleep ]] && grep -q 'deep' /sys/power/mem_sleep; then
    cmdline_args+=("mem_sleep_default=deep")
  fi

  # --- resume= for hibernation, if a swap partition exists ---
  local swap_partuuid
  swap_partuuid=$(blkid -t TYPE=swap -o export 2>/dev/null | awk -F= '/^PARTUUID=/{print $2; exit}' || true)
  if [[ -n "$swap_partuuid" ]]; then
    local _current_cmdline=""
    if [[ -f /etc/kernel/cmdline ]]; then
      _current_cmdline=$(tr '\n' ' ' < /etc/kernel/cmdline)
    elif [[ -f /boot/limine.conf ]]; then
      _current_cmdline=$(awk '/^[[:space:]]*(kernel_cmdline|cmdline):[[:space:]]*/ {
        sub(/^[[:space:]]*(kernel_cmdline|cmdline):[[:space:]]*/, "")
        print
        exit
      }' /boot/limine.conf)
    elif [[ -r /proc/cmdline ]]; then
      _current_cmdline=$(cat /proc/cmdline)
    fi
    if grep -Eq '(^|[[:space:]])resume=' <<< "$_current_cmdline"; then
      echo -e "${STY_BLUE}[$0]: resume= already present in the managed kernel cmdline — skipping.${STY_RST}"
    else
      cmdline_args+=("resume=PARTUUID=$swap_partuuid")
      echo -e "${STY_CYAN}[$0]: Will set hibernation resume= to swap PARTUUID=$swap_partuuid.${STY_RST}"
    fi
  else
    echo -e "${STY_BLUE}[$0]: No swap partition found — skipping resume= injection.${STY_RST}"
  fi

  # --- Apply collected kernel cmdline args in a single pass ---
  # Persist them in /etc/kernel/cmdline and let limine-mkinitcpio regenerate
  # the boot entries from that single source of truth.
  if (( ${#cmdline_args[@]} > 0 )); then
    echo -e "${STY_CYAN}[$0]: Applying limine kernel cmdline args: ${cmdline_args[*]}${STY_RST}"
    if ! _limine_apply_cmdline_args "${cmdline_args[@]}"; then
      echo -e "${STY_YELLOW}[$0]: Failed to update /etc/kernel/cmdline for GPU boot flags.${STY_RST}"
    fi
  fi

  # --- Rebuild initramfs so new MODULES/HOOKS take effect on next boot ---
  # Also regenerates /boot/limine.conf boot entries from /etc/kernel/cmdline on systems
  # with limine-mkinitcpio-hook installed.
  _initramfs_rebuild

  # --- Apply dotfile-level tweaks if the target files already exist
  #     (reinstall case). For first install, 3.files.sh calls this again after
  #     the dotfiles are deployed.
  setup_gpu_hypr_tweaks

  echo -e "${STY_GREEN}[$0]: GPU autoconfig complete.${STY_RST}"
}

# Apply dotfile-level GPU tweaks (NVIDIA Wayland env vars in hypr custom
# env.conf, dpms delays in hypridle.conf, AQ_DRM_DEVICES for hybrid NVIDIA).
# Separated from setup_gpu_autoconfig because these files only exist after
# 3.files.sh deploys dotfiles. Safe to call more than once — each insertion is
# idempotent and skips silently when the target file is missing.
function setup_gpu_hypr_tweaks(){
  if [[ "$OS_GROUP_ID" != "arch" ]]; then return 0; fi
  # Re-detect in case flags aren't set (when called from 3.files.sh directly).
  if [[ -z "${HAS_NVIDIA:-}" ]]; then
    _gpu_detect >/dev/null 2>&1 || return 0
  fi
  local _env_conf="$HOME/.config/hypr/custom/env.conf"
  if [[ ! -f "$_env_conf" ]]; then
    echo -e "${STY_YELLOW}[$0]: $_env_conf not found — deferring hypr GPU tweaks until after dotfiles are deployed.${STY_RST}"
    return 0
  fi

  if $HAS_NVIDIA && (( NVIDIA_PCI_DEC >= 1728 )); then
    # NVIDIA Wayland env vars. NVD_BACKEND=direct is a VA-API perf hint safe
    # on Turing+; harmless on older Fermi/Kepler so we set it unconditionally
    # within the Fermi+ branch.
    _hypr_env_upsert "LIBVA_DRIVER_NAME"         "nvidia"         || true
    _hypr_env_upsert "GBM_BACKEND"               "nvidia-drm"     || true
    _hypr_env_upsert "__GLX_VENDOR_LIBRARY_NAME" "nvidia"         || true
    _hypr_env_upsert "NVD_BACKEND"               "direct"         || true
    _hypr_env_upsert "WLR_NO_HARDWARE_CURSORS"   "1"              || true
    _hypr_fix_hypridle_for_nvidia || true
  fi

  # Hybrid with NVIDIA: pin the Aquamarine DRM device to the NVIDIA card via
  # the stable by-path symlink. card0/card1 enumeration is non-deterministic
  # across reboots, but /dev/dri/by-path/pci-<addr>-card follows the PCIe slot.
  if $IS_HYBRID && $HAS_NVIDIA; then
    local _nvidia_pciaddr
    _nvidia_pciaddr=$(lspci -D 2>/dev/null | grep -iE "NVIDIA|GeForce|Quadro|Tesla" | head -1 | awk '{print $1}')
    if [[ -n "$_nvidia_pciaddr" ]]; then
      _hypr_env_upsert "AQ_DRM_DEVICES" "/dev/dri/by-path/pci-${_nvidia_pciaddr}-card" || true
    fi
  fi
}

showfun setup_pacman_nopasswd
v setup_pacman_nopasswd

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

showfun teardown_pacman_nopasswd
v teardown_pacman_nopasswd

showfun setup_gamescope
v setup_gamescope
