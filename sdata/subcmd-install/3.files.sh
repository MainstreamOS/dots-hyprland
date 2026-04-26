# This script is meant to be sourced.
# It's not for directly running.
printf "\n"
ms_section "Copying config files..."

# shellcheck shell=bash

function warning_overwrite(){
  printf "${STY_YELLOW}"
  printf "The command below overwrites the destination.\n"
  printf "${STY_RST}"
}
function auto_backup_configs(){
  local backup=false
  case $ask in
    false) if [[ ! -d "$BACKUP_DIR" ]]; then local backup=true;fi;;
    *)
      printf "${STY_RED}"
      printf "Would you like to backup clashing dirs/files to \"$BACKUP_DIR\"?\n"
      printf "${STY_RST}"
      while true;do
        echo "  y = Yes, backup"
        echo "  n/s = No, skip to next"
        local p; read -p "====> " p
        case $p in
          [yY]) echo -e "${STY_BLUE}OK, doing backup...${STY_RST}"
            local backup=true;break ;;
          [nNsS]) echo -e "${STY_BLUE}Alright, skipping...${STY_RST}"
            local backup=false;break ;;
          *) echo -e "${STY_RED}Please enter [y/n/s].${STY_RST}";;
        esac
      done
      ;;
  esac
  if $backup;then
    backup_clashing_targets dots/.config $XDG_CONFIG_HOME "${BACKUP_DIR}/.config"
    backup_clashing_targets dots/.local/share $XDG_DATA_HOME "${BACKUP_DIR}/.local/share"
    printf "${STY_BLUE}Backup into \"${BACKUP_DIR}\" finished.${STY_RST}\n"
  fi
}
function gen_firstrun(){
  x mkdir -p "$(dirname ${FIRSTRUN_FILE})"
  x touch "${FIRSTRUN_FILE}"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "${FIRSTRUN_FILE}" >> "${INSTALLED_LISTFILE}"
}
cp_file(){
  # NOTE: This function is only for using in other functions
  x mkdir -p "$(dirname $2)"
  x cp -f "$1" "$2"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "$2" >> "${INSTALLED_LISTFILE}"
}
rsync_dir(){
  # NOTE: This function is only for using in other functions
  x mkdir -p "$2"
  local dest="$(realpath -se $2)"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  rsync -a --out-format='%i %n' "$1"/ "$2"/ | awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf d "/" $0 "\n" }' >> "${INSTALLED_LISTFILE}"
}
rsync_dir__ignore_existing(){
  # NOTE: This function is only for using in other functions
  x mkdir -p "$2"
  local dest="$(realpath -se $2)"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  rsync -a --ignore-existing --out-format='%i %n' "$1"/ "$2"/ | awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf d "/" $0 "\n" }' >> "${INSTALLED_LISTFILE}"
}
rsync_dir__sync(){
  # NOTE: This function is only for using in other functions
  # `--delete' for rsync to make sure that
  # original dotfiles and new ones in the SAME DIRECTORY
  # (eg. in ~/.config/hypr) won't be mixed together
  x mkdir -p "$2"
  local dest="$(realpath -se $2)"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  rsync -a --delete --out-format='%i %n' "$1"/ "$2"/ | awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf d "/" $0 "\n" }' >> "${INSTALLED_LISTFILE}"
}
rsync_dir__sync_exclude(){
  # NOTE: This function is only for using in other functions
  # Same as rsync_dir__sync but with exclude patterns support
  # Usage: rsync_dir__sync_exclude <src> <dest> <exclude_pattern1> [<exclude_pattern2> ...]
  local src="$1"
  local dest_dir="$2"
  shift 2
  local excludes=()
  for pattern in "$@"; do
    excludes+=(--exclude "$pattern")
  done
  x mkdir -p "$dest_dir"
  local dest="$(realpath -se $dest_dir)"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  rsync -a --delete "${excludes[@]}" --out-format='%i %n' "$src"/ "$dest_dir"/ | awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf d "/" $0 "\n" }' >> "${INSTALLED_LISTFILE}"
}
function install_file(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -f $t ];then
    warning_overwrite
  fi
  v cp_file $s $t
}
function install_file__auto_backup(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -f $t ];then
    echo -e "${STY_YELLOW}[$0]: \"$t\" already exists.${STY_RST}"
    if ${INSTALL_FIRSTRUN};then
      echo -e "${STY_BLUE}[$0]: It seems to be the firstrun.${STY_RST}"
      v mv $t $t.old
      v cp_file $s $t
    else
      echo -e "${STY_BLUE}[$0]: It seems not a firstrun.${STY_RST}"
      v cp_file $s $t.new
    fi
  else
    echo -e "${STY_GREEN}[$0]: \"$t\" does not exist yet.${STY_RST}"
    v cp_file $s $t
  fi
}
function install_dir(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -d $t ];then
    warning_overwrite
  fi
  v rsync_dir $s $t
}
function install_dir__sync(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -d $t ];then
    warning_overwrite
  fi
  v rsync_dir__sync $s $t
}
function install_dir__skip_ifexist(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -d $t ];then
    echo -e "${STY_BLUE}[$0]: \"$t\" already exists, will not do anything.${STY_RST}"
  else
    echo -e "${STY_YELLOW}[$0]: \"$t\" does not exist yet.${STY_RST}"
    v rsync_dir $s $t
  fi
}
function install_dir__ignore_existing(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -d $t ];then
    echo -e "${STY_BLUE}[$0]: \"$t\" already exists, will not do anything.${STY_RST}"
  else
    echo -e "${STY_YELLOW}[$0]: \"$t\" does not exist yet.${STY_RST}"
    v rsync_dir__ignore_existing $s $t
  fi
}
function install_dir__sync_exclude(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  # Sync directory with exclude patterns
  # Usage: install_dir__sync_exclude <src> <dest> <exclude_pattern1> [<exclude_pattern2> ...]
  local s=$1
  local t=$2
  shift 2
  if [ -d $t ];then
    warning_overwrite
  fi
  v rsync_dir__sync_exclude $s $t "$@"
}
function setup_hyprland_plugins(){
  # Build hyprbars from source into a user-owned plugin directory and load it
  # with a `plugin = ...` directive. No hyprpm, no systemd service, no sudoers
  # grant — the .so is owned by the user and Hyprland loads it as the user.
  echo -e "${STY_CYAN}[$0]: Building hyprbars plugin from source...${STY_RST}"

  # Remove artifacts from earlier hyprpm-based approaches if they exist. Doing
  # this unconditionally means a reinstall always lands in a clean state.
  try systemctl --user stop hyprland-plugins-setup.service 2>/dev/null
  try rm -f "$HOME/.config/systemd/user/hyprland-plugins-setup.service"
  try systemctl --user daemon-reload 2>/dev/null
  try sudo rm -f /usr/local/bin/hyprland-plugins-setup
  try sudo rm -f /etc/sudoers.d/hyprpm
  local EXECS_CONF="$HOME/.config/hypr/custom/execs.conf"
  if [[ -f "$EXECS_CONF" ]] && grep -q 'hyprland-plugins-setup' "$EXECS_CONF"; then
    sed -i '/# Defer hyprpm to first login/d; /hyprland-plugins-setup/d' "$EXECS_CONF"
    echo -e "${STY_BLUE}[$0]: Removed old hyprland-plugins-setup trigger from $EXECS_CONF${STY_RST}"
  fi

  # Fail fast if the build deps aren't there — hyprbars' Makefile depends on
  # pkg-config finding each of these. `hyprland` itself ships the headers +
  # hyprland.pc on Arch via the main package.
  local _missing=()
  for pc in hyprland pixman-1 libdrm pangocairo libinput libudev wayland-server xkbcommon; do
    pkg-config --exists "$pc" 2>/dev/null || _missing+=("$pc")
  done
  if (( ${#_missing[@]} > 0 )); then
    echo -e "${STY_RED}[$0]: Missing pkg-config deps for hyprbars: ${_missing[*]}${STY_RST}"
    echo -e "${STY_RED}[$0]: Install the corresponding dev packages and re-run the installer.${STY_RST}"
    return 1
  fi

  # Clone/update into the repo cache dir (same pattern as install_google_sans_flex).
  local src_dir="$REPO_ROOT/cache/hyprland-plugins"
  x mkdir -p "$src_dir"
  x cd "$src_dir"
  try git init -b main
  try git remote add origin https://github.com/hyprwm/hyprland-plugins
  x git pull origin main

  # Persist build output to a log so failures can be diffed across Hyprland
  # updates — the real install still prints everything to the terminal too.
  local build_log="$HOME/.local/share/hyprland/plugins/hyprbars-build.log"
  x mkdir -p "$(dirname "$build_log")"
  local _hv="(hyprctl unavailable)"
  hyprctl version &>/dev/null && _hv=$(hyprctl version | head -n1)
  {
    echo "=== hyprbars build @ $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "Hyprland:      $_hv"
    echo "Plugin commit: $(git -C "$src_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "---"
  } > "$build_log"
  echo -e "${STY_CYAN}[$0]: Build log: $build_log${STY_RST}"

  x cd "$src_dir/hyprbars"
  try make clean
  # Process substitution preserves make's exit code (unlike `| tee`) so the `x`
  # wrapper still catches build failures instead of seeing tee's success.
  x make all -j"$(nproc)" > >(tee -a "$build_log") 2>&1
  x cd "$REPO_ROOT"

  # Drop the .so under the user's data dir. Absolute path required by the
  # `plugin = ` directive; Hyprland doesn't expand ~ there.
  local plugin_dir="$HOME/.local/share/hyprland/plugins"
  local plugin_path="$plugin_dir/hyprbars.so"
  x mkdir -p "$plugin_dir"
  x cp -f "$src_dir/hyprbars/hyprbars.so" "$plugin_path"
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "$plugin_path" >> "${INSTALLED_LISTFILE}"
  echo -e "${STY_GREEN}[$0]: Installed hyprbars.so to $plugin_path${STY_RST}"

  # The plugin { hyprbars { ... } } settings block already lives in
  # custom/general.conf (shipped with the dots). We prepend the load directive
  # to the same file — Hyprland requires the .so to be loaded before its
  # settings block is parsed, otherwise the config is silently ignored.
  local _general_conf="$HOME/.config/hypr/custom/general.conf"
  if [[ -f "$_general_conf" ]]; then
    if ! grep -q 'plugin *= *.*hyprbars\.so' "$_general_conf"; then
      local _tmp; _tmp=$(mktemp)
      {
        echo "# hyprbars plugin load directive (built from source at install time)"
        echo "# plugin = ${plugin_path}"
        echo ""
        cat "$_general_conf"
      } > "$_tmp"
      mv "$_tmp" "$_general_conf"
      echo -e "${STY_CYAN}[$0]: Added '# plugin = ${plugin_path}' to $_general_conf (commented out — enable via Title Bars toggle)${STY_RST}"
    else
      echo -e "${STY_BLUE}[$0]: $_general_conf already loads hyprbars; skipping.${STY_RST}"
    fi
  else
    echo -e "${STY_YELLOW}[$0]: $_general_conf missing — add this line to a sourced hypr config manually:${STY_RST}"
    echo -e "${STY_YELLOW}  plugin = ${plugin_path}${STY_RST}"
  fi
}

function install_google_sans_flex(){
  local font_name="Google Sans Flex"
  local src_name="google-sans-flex"
  local src_url="https://github.com/end-4/google-sans-flex"
  local src_dir="$REPO_ROOT/cache/$src_name"
  local target_dir="${XDG_DATA_HOME}/fonts/illogical-impulse-$src_name"
  if fc-list | grep -qi "$font_name"; then return; fi
  x mkdir -p $src_dir
  x cd $src_dir
  try git init -b main
  try git remote add origin $src_url
  x git pull origin main 
  x git submodule update --init --recursive
  warning_overwrite
  rsync_dir "$src_dir" "$target_dir" 
  x fc-cache -fv
  x cd $REPO_ROOT
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "$target_dir" >> "${INSTALLED_LISTFILE}"
}

#####################################################################################
# In case some dirs does not exists
for i in "$XDG_BIN_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"; do
  if ! test -e "$i"; then
    v mkdir -p "$i"
  fi
done
case "${INSTALL_FIRSTRUN}" in
  # When specify --firstrun
  true) sleep 0 ;;
  # When not specify --firstrun
  *)
    if test -f "${FIRSTRUN_FILE}"; then
      INSTALL_FIRSTRUN=false
    else
      INSTALL_FIRSTRUN=true
    fi
    ;;
esac


showfun auto_update_git_submodule
v auto_update_git_submodule

# Backup
if [[ ! "${SKIP_BACKUP}" == true ]]; then auto_backup_configs; fi

case "${EXPERIMENTAL_FILES_SCRIPT}" in
  true)source sdata/subcmd-install/3.files-exp.sh;;
  *)source sdata/subcmd-install/3.files-legacy.sh;;
esac

if [[ ! "$OS_GROUP_ID" == "fedora" ]]; then
  showfun install_google_sans_flex
  v install_google_sans_flex

  # 2.setups.sh runs before this file, so retry the system-wide sync now that
  # the user font install has been created or refreshed.
  if declare -F sync_google_sans_flex_systemwide >/dev/null 2>&1; then
    showfun sync_google_sans_flex_systemwide
    v sync_google_sans_flex_systemwide
  fi
fi

showfun setup_hyprland_plugins
v setup_hyprland_plugins

# Apply GPU-dependent hypr dotfile tweaks (NVIDIA Wayland env vars, hypridle
# dpms delays, AQ_DRM_DEVICES for hybrid NVIDIA) now that custom/env.conf and
# hypridle.conf exist on disk. Safe no-op on non-NVIDIA systems and re-runs.
# Defined in 2.setups.sh; still in scope here because both files are sourced
# by ./setup in the same shell.
if declare -F setup_gpu_hypr_tweaks >/dev/null 2>&1; then
  showfun setup_gpu_hypr_tweaks
  v setup_gpu_hypr_tweaks
fi

#####################################################################################

v gen_firstrun
v dedup_and_sort_listfile "${INSTALLED_LISTFILE}" "${INSTALLED_LISTFILE}"

# Prevent hyprland from not fully loaded
sleep 1
try hyprctl reload

#####################################################################################
printf "\n"
ms_step_raw "finalizing install..."
printf "\n"
ms_ready "reboot to enter Mainstream."
printf "\n"
ms_hint "in Hyprland: Super+W = wallpaper · Super+Tab = keybinds"
printf "\n"

if [[ -z "${ILLOGICAL_IMPULSE_VIRTUAL_ENV}" ]]; then
  printf "\n${STY_RED}[$0]: \!! Important \!! : Please ensure environment variable ${STY_RST} \$ILLOGICAL_IMPULSE_VIRTUAL_ENV ${STY_RED} is set to proper value (by default \"~/.local/state/quickshell/.venv\"), or Quickshell config will not work. We have already provided this configuration in ~/.config/hypr/hyprland/env.conf, but you need to ensure it is included in hyprland.conf, and also a restart is needed for applying it.${STY_RST}\n"
fi
