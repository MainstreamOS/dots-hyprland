# This script is meant to be sourced.
# It's not for directly running.

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
#####################################################################################
# These python packages are installed using uv into the venv (virtual environment). Once the folder of the venv gets deleted, they are all gone cleanly. So it's considered as setups, not dependencies.

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

showfun install-python-packages
v install-python-packages

showfun setup_user_group
v setup_user_group

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
  # Fix fingerprint bug when sleeping by killing fprintd before sleep
  showfun setup_kill_fprintd_service
  v setup_kill_fprintd_service
  v sudo systemctl enable kill-fprintd.service
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

v gsettings set org.gnome.desktop.interface font-name 'Google Sans Flex Medium 11 @opsz=11,wght=500'
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

showfun setup_gamescope
v setup_gamescope
