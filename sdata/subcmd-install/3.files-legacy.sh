# This script is meant to be sourced.
# It's not for directly running.

# shellcheck shell=bash

#####################################################################################
# MISC (For dots/.config/* but not quickshell, not fish, not Hyprland, not fontconfig)
case "${SKIP_MISCCONF}" in
  true) sleep 0;;
  *)
    for i in $(find dots/.config/ -mindepth 1 -maxdepth 1 ! -name 'quickshell' ! -name 'fish' ! -name 'hypr' ! -name 'fontconfig' -exec basename {} \;); do
#      i="dots/.config/$i"
      echo "[$0]: Found target: dots/.config/$i"
      if [ -d "dots/.config/$i" ];then install_dir__sync "dots/.config/$i" "$XDG_CONFIG_HOME/$i"
      elif [ -f "dots/.config/$i" ];then install_file "dots/.config/$i" "$XDG_CONFIG_HOME/$i"
      fi
    done
    install_dir "dots/.local/share/konsole" "${XDG_DATA_HOME}"/konsole
    install_dir "dots/.local/share/applications" "${XDG_DATA_HOME}"/applications
    ;;
esac

case "${SKIP_QUICKSHELL}" in
  true) sleep 0;;
  *)
     # Should overwriting the whole directory not only ~/.config/quickshell/ii/ cuz https://github.com/end-4/dots-hyprland/issues/2294#issuecomment-3448671064
    install_dir__sync dots/.config/quickshell "$XDG_CONFIG_HOME"/quickshell
    ;;
esac

case "${SKIP_FISH}" in
  true) sleep 0;;
  *)
    install_dir__sync_exclude dots/.config/fish "$XDG_CONFIG_HOME"/fish "conf.d"
    ;;
esac

case "${SKIP_FONTCONFIG}" in
  true) sleep 0;;
  *)
    case "$FONTSET_DIR_NAME" in
      "") install_dir__sync dots/.config/fontconfig "$XDG_CONFIG_HOME"/fontconfig ;;
      *) install_dir__sync dots-extra/fontsets/$FONTSET_DIR_NAME "$XDG_CONFIG_HOME"/fontconfig ;;
    esac;;
esac

# For Hyprland
case "${SKIP_HYPRLAND}" in
  true) sleep 0;;
  *)
    install_dir__sync dots/.config/hypr/hyprland "$XDG_CONFIG_HOME"/hypr/hyprland
    for i in hyprlock.conf {monitors,workspaces}.conf ; do
      install_file__auto_backup "dots/.config/hypr/$i" "${XDG_CONFIG_HOME}/hypr/$i"
    done
    for i in hyprland.conf ; do
      case "${SKIP_HYPRLAND_ENTRY}" in
        true) sleep 0;;
        *) install_file "dots/.config/hypr/$i" "${XDG_CONFIG_HOME}/hypr/$i" ;;
      esac
    done
    for i in hypridle.conf ; do
      if [[ "${INSTALL_VIA_NIX}" == true ]]; then
        install_file__auto_backup "dots-extra/via-nix/$i" "${XDG_CONFIG_HOME}/hypr/$i"
      else
        install_file__auto_backup "dots/.config/hypr/$i" "${XDG_CONFIG_HOME}/hypr/$i"
      fi
    done
    if [ "$OS_GROUP_ID" = "fedora" ];then
      v bash -c "printf \"# Polkit authentication agent fallback\nexec-once = systemctl --user start hyprpolkitagent\n\" >> ${XDG_CONFIG_HOME}/hypr/hyprland/execs.conf"
    fi

    install_dir__ignore_existing "dots/.config/hypr/custom" "${XDG_CONFIG_HOME}/hypr/custom"
    ;;
esac

# Nautilus bookmarks
BOOKMARKS_FILE="${XDG_CONFIG_HOME}/gtk-3.0/bookmarks"
if [ ! -f "$BOOKMARKS_FILE" ]; then
    x mkdir -p "$(dirname "$BOOKMARKS_FILE")"
    cat > "$BOOKMARKS_FILE" <<EOF
file://${HOME}/Desktop Desktop
file://${HOME}/Downloads Downloads
file://${HOME}/Documents Documents
file://${HOME}/Music Music
file://${HOME}/Pictures Pictures
file://${HOME}/Videos Videos
EOF
    x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
    realpath -se "$BOOKMARKS_FILE" >> "${INSTALLED_LISTFILE}"
fi

# Set Nautilus as default file manager and ensure XDG user dirs exist
xdg-mime default org.gnome.Nautilus.desktop inode/directory
xdg-user-dirs-update

install_file "dots/.local/share/icons/illogical-impulse.svg" "${XDG_DATA_HOME}"/icons/illogical-impulse.svg
install_file "dots/.local/share/icons/hicolor/scalable/apps/mainstream-logo.svg" "${XDG_DATA_HOME}"/icons/hicolor/scalable/apps/mainstream-logo.svg
