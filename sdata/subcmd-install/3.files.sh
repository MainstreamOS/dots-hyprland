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
record_installed(){
  mkdir -p "$(dirname "$INSTALLED_LISTFILE")"
  realpath -se "$1" >> "$INSTALLED_LISTFILE"
}
_rsync_to_listfile(){
  local src=$1 dst=$2; shift 2
  x mkdir -p "$dst"
  local dest; dest=$(realpath -se "$dst")
  x mkdir -p "$(dirname "$INSTALLED_LISTFILE")"
  rsync -a "$@" --out-format='%i %n' "$src"/ "$dst"/ | awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf d "/" $0 "\n" }' >> "$INSTALLED_LISTFILE"
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
  record_installed "${FIRSTRUN_FILE}"
}
cp_file(){
  # NOTE: This function is only for using in other functions
  x mkdir -p "$(dirname $2)"
  x cp -f "$1" "$2"
  record_installed "$2"
}
rsync_dir(){
  # NOTE: This function is only for using in other functions
  _rsync_to_listfile "$1" "$2"
}
rsync_dir__ignore_existing(){
  # NOTE: This function is only for using in other functions
  _rsync_to_listfile "$1" "$2" --ignore-existing
}
rsync_dir__sync(){
  # NOTE: This function is only for using in other functions
  # `--delete' for rsync to make sure that
  # original dotfiles and new ones in the SAME DIRECTORY
  # (eg. in ~/.config/hypr) won't be mixed together
  _rsync_to_listfile "$1" "$2" --delete
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
  _rsync_to_listfile "$src" "$dest_dir" "${excludes[@]}" --delete
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
# The version both halves of the ABI guard are stamped with. pacman first
# because it reports pkgrel and pkg-config does not; a pkgrel-only rebuild
# changes the plugin ABI while the bare version stays put. Kept identical to
# the rebuild scripts under sdata/*/rebuild.sh — the guard in
# dots/.config/hypr/custom/general.lua compares what they write, so a format
# that drifts between them fails closed.
function _hyprland_stamp_version(){
  local _v
  _v=$(pacman -Q hyprland 2>/dev/null | awk '{print $2}')
  [[ -n "$_v" ]] || _v=$(pkg-config --modversion hyprland 2>/dev/null || echo "")
  printf '%s' "$_v"
}

# _build_hyprland_plugin_fresh: clone/update + build a Hyprland plugin
# from source against the *running* hyprland, install the produced .so
# to its plugin path. Returns 0 on success, 1 on any failure (missing
# deps, network, build error, etc.). Caller decides what to do with
# a failure.
#
# Args:
#   $1 plugin name (used for cache dir + log filename)
#   $2 repo URL
#   $3 branch
#   $4 path within the repo where the Makefile lives ("" for repo root)
#   $5 .so filename produced by the build
#
# Side effects on success:
#   - $HOME/.local/share/hyprland/plugins/$5 is created/replaced
#   - $HOME/.local/share/hyprland/plugins/${1}-build.log is written
function _build_hyprland_plugin_fresh(){
  local name="$1"
  local repo_url="$2"
  local branch="$3"
  local subdir="$4"
  local so_filename="$5"

  # Pkg-config sanity. hyprland itself ships hyprland.pc + headers on
  # Arch via the main package; the others come in transitively but we
  # double-check so a missing one fails clearly instead of as a cryptic
  # build error.
  local _missing=()
  for pc in hyprland pixman-1 libdrm pangocairo libinput libudev wayland-server xkbcommon; do
    pkg-config --exists "$pc" 2>/dev/null || _missing+=("$pc")
  done
  if (( ${#_missing[@]} > 0 )); then
    echo -e "${STY_YELLOW}[$0]: $name: cannot build (missing pkg-config: ${_missing[*]})${STY_RST}"
    return 1
  fi

  # Build toolchain.
  local _need_tools=()
  for t in g++ make git pkg-config; do
    command -v "$t" >/dev/null 2>&1 || _need_tools+=("$t")
  done
  if (( ${#_need_tools[@]} > 0 )); then
    echo -e "${STY_YELLOW}[$0]: $name: cannot build (missing tools: ${_need_tools[*]})${STY_RST}"
    return 1
  fi

  # Clone/update the source.
  local src_dir="$REPO_ROOT/cache/$name"
  mkdir -p "$src_dir"
  if ! (
    cd "$src_dir"
    if [[ ! -d .git ]]; then
      git init -b "$branch" >/dev/null 2>&1
      git remote add origin "$repo_url" >/dev/null 2>&1
    fi
    git fetch origin "$branch" && git reset --hard FETCH_HEAD
  ); then
    echo -e "${STY_YELLOW}[$0]: $name: cannot build (clone/pull failed — network issue?)${STY_RST}"
    return 1
  fi

  local build_dir="$src_dir"
  [[ -n "$subdir" ]] && build_dir="$src_dir/$subdir"

  # Build with logging. Process substitution preserves make's exit code
  # (unlike `| tee`).
  local plugin_dir="$HOME/.local/share/hyprland/plugins"
  mkdir -p "$plugin_dir"
  local build_log="$plugin_dir/${name}-build.log"
  local _hv="(hyprctl unavailable)"
  hyprctl version &>/dev/null && _hv=$(hyprctl version | head -n1)
  {
    echo "=== $name build @ $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "Hyprland:      $_hv"
    echo "pkg-config:    hyprland $(pkg-config --modversion hyprland 2>/dev/null || echo unknown)"
    echo "Plugin commit: $(git -C "$src_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "---"
  } > "$build_log"
  echo -e "${STY_CYAN}[$0]: $name: build log → $build_log${STY_RST}"

  if ! (
    cd "$build_dir"
    make clean 2>/dev/null || true
    make all -j"$(nproc)"
  ) > >(tee -a "$build_log") 2>&1 ; then
    echo -e "${STY_YELLOW}[$0]: $name: build failed (see $build_log)${STY_RST}"
    return 1
  fi

  if [[ ! -f "$build_dir/$so_filename" ]]; then
    echo -e "${STY_YELLOW}[$0]: $name: build succeeded but $so_filename not found at $build_dir${STY_RST}"
    return 1
  fi

  # Replace via rename: a truncating copy would corrupt the mapping of a
  # plugin the running session has loaded and crash the compositor. The
  # rename swaps the inode atomically; a live session keeps the old copy
  # until relaunch.
  local _staged_so
  _staged_so=$(mktemp -p "$plugin_dir" ".${so_filename}.XXXXXX")
  cp -f "$build_dir/$so_filename" "$_staged_so"
  chmod 755 "$_staged_so"
  mv -f "$_staged_so" "$plugin_dir/$so_filename"
  printf '%s\n' "$(_hyprland_stamp_version)" > "$plugin_dir/$so_filename.builtfor"
  echo -e "${STY_GREEN}[$0]: $name: built freshly against current hyprland → $plugin_dir/$so_filename${STY_RST}"
  return 0
}

# _ensure_hyprland_plugin: bulletproof installer for a Hyprland plugin.
# Always *tries* to build fresh against the installed hyprland — that's
# the only way to guarantee ABI match. If the fresh build fails AND a
# prebuilt .so was shipped via /etc/skel (archiso path), keep the
# prebuilt as a best-effort fallback and warn the user. If neither path
# works, hard error.
#
# Same signature as _build_hyprland_plugin_fresh.
# Returns 0 if a usable .so is in place, 1 if not.
function _ensure_hyprland_plugin(){
  local name="$1"
  local repo_url="$2"
  local branch="$3"
  local subdir="$4"
  local so_filename="$5"

  local plugin_dir="$HOME/.local/share/hyprland/plugins"
  local plugin_path="$plugin_dir/$so_filename"
  local _had_prebuilt=false
  [[ -f "$plugin_path" ]] && _had_prebuilt=true

  # Record which Hyprland this system runs, so the guard in custom/general.lua
  # has something to compare each .so's stamp against. Written before the build
  # so a failed build still leaves the guard armed.
  local _stamp_ver
  _stamp_ver=$(_hyprland_stamp_version)
  if [[ -n "$_stamp_ver" ]]; then
    try sudo mkdir -p /var/lib/hyprland-plugins
    printf '%s\n' "$_stamp_ver" | try sudo tee /var/lib/hyprland-plugins/hyprland-version >/dev/null
  fi

  if [[ "$_had_prebuilt" == true ]]; then
    echo -e "${STY_BLUE}[$0]: $name: prebuilt $so_filename present at $plugin_path${STY_RST}"
    echo -e "${STY_BLUE}[$0]:   Will rebuild against current hyprland to guarantee ABI match.${STY_RST}"
  fi

  if _build_hyprland_plugin_fresh "$name" "$repo_url" "$branch" "$subdir" "$so_filename"; then
    return 0
  fi

  if [[ "$_had_prebuilt" == true ]]; then
    echo -e "${STY_YELLOW}[$0]: $name: keeping prebuilt $so_filename as fallback.${STY_RST}"
    echo -e "${STY_YELLOW}[$0]:   It loads only if it is stamped for hyprland $_stamp_ver; a prebuilt${STY_RST}"
    echo -e "${STY_YELLOW}[$0]:   for any other version stays disabled rather than crashing the${STY_RST}"
    echo -e "${STY_YELLOW}[$0]:   compositor. The pacman rebuild hook installed below will retry${STY_RST}"
    echo -e "${STY_YELLOW}[$0]:   from source on the next \`pacman -Syu\` that touches hyprland.${STY_RST}"
    return 0
  fi

  echo -e "${STY_RED}[$0]: $name: install failed — fresh build failed and no prebuilt fallback.${STY_RST}"
  echo -e "${STY_RED}[$0]:   Verify network connectivity and that the hyprland package + base-devel${STY_RST}"
  echo -e "${STY_RED}[$0]:   are installed, then re-run the installer.${STY_RST}"
  return 1
}

_install_plugin_rebuild_hook(){
  local name="$1"
  local _rebuild_src="$REPO_ROOT/sdata/$name/rebuild.sh"
  local _hook_src="$REPO_ROOT/sdata/$name/95-$name-rebuild.hook"
  local _conf_src="$REPO_ROOT/sdata/$name/$name.conf"
  if [[ -f "$_rebuild_src" && -f "$_hook_src" ]]; then
    echo -e "${STY_CYAN}[$0]: Installing pacman rebuild hook for $name...${STY_RST}"
    try sudo install -Dm755 "$_rebuild_src" "/usr/local/lib/$name/rebuild.sh"
    try sudo install -Dm644 "$_hook_src"    "/etc/pacman.d/hooks/95-$name-rebuild.hook"
    if [[ -f "$_conf_src" && ! -f "/etc/$name.conf" ]]; then
      try sudo install -Dm644 "$_conf_src" "/etc/$name.conf"
    fi
    echo -e "${STY_GREEN}[$0]: Hook installed — $name will auto-rebuild on hyprland upgrades.${STY_RST}"
  else
    echo -e "${STY_YELLOW}[$0]: rebuild hook sources missing under sdata/$name/ — skipping auto-rebuild setup.${STY_RST}"
    echo -e "${STY_YELLOW}[$0]:   You will need to manually rebuild $name after each hyprland upgrade.${STY_RST}"
  fi
}
_remove_legacy_plugin_timer(){
  local name="$1"
  try sudo systemctl disable --now "$name-rebuild.timer" 2>/dev/null
  try sudo rm -f "/etc/systemd/system/$name-rebuild.timer" "/etc/systemd/system/$name-rebuild.service"
}
_wire_plugin_status_notify(){
  local name="$1"
  local execs_lua="$2"
  local notify_comment="$3"
  local _notify_src="$REPO_ROOT/sdata/$name/$name-status-notify.sh"
  local _notify_bin="/usr/local/bin/$name-status-notify"
  if [[ -f "$_notify_src" ]]; then
    echo -e "${STY_CYAN}[$0]: Installing $name status notifier...${STY_RST}"
    try sudo install -Dm755 "$_notify_src" "$_notify_bin"
    if [[ -f "$execs_lua" ]]; then
      if ! grep -q "$name-status-notify" "$execs_lua"; then
        {
          echo ""
          printf '%s\n' "$notify_comment"
          echo "hl.on(\"hyprland.start\", function() hl.exec_cmd(\"$_notify_bin\") end)"
        } >> "$execs_lua"
        echo -e "${STY_BLUE}[$0]: Added $name-status-notify hl.on subscription to $execs_lua${STY_RST}"
      else
        echo -e "${STY_BLUE}[$0]: $execs_lua already runs $name-status-notify; skipping.${STY_RST}"
      fi
    else
      mkdir -p "$(dirname "$execs_lua")"
      {
        echo "-- Hyprland custom start-up commands (managed by dots-hyprland)"
        echo ""
        printf '%s\n' "$notify_comment"
        echo "hl.on(\"hyprland.start\", function() hl.exec_cmd(\"$_notify_bin\") end)"
      } > "$execs_lua"
      echo -e "${STY_BLUE}[$0]: Created $execs_lua with $name-status-notify entry${STY_RST}"
    fi
  fi
}

function setup_hyprland_plugins(){
  # Set up hyprbars: the .so lives at
  # ~/.local/share/hyprland/plugins/hyprbars.so loaded via a
  # `plugin = ...` directive (commented out by default — enable via
  # the Title Bars toggle in Settings). No hyprpm, no systemd service,
  # no sudoers — the .so is owned by the user and Hyprland loads it as
  # the user.
  #
  # Bulletproof flow (handled by _ensure_hyprland_plugin):
  #   1. archiso may have shipped a prebuilt hyprbars.so via /etc/skel
  #   2. Always try to rebuild fresh against the installed hyprland —
  #      that's the only way to guarantee ABI match for first-load
  #   3. If the rebuild succeeds, the freshly-built .so replaces the
  #      prebuilt
  #   4. If the rebuild fails and a prebuilt is in place, keep the
  #      prebuilt as a best-effort fallback and let the pacman rebuild
  #      hook fix it on the next hyprland upgrade
  #   5. If the rebuild fails and no prebuilt exists, hard error
  echo -e "${STY_CYAN}[$0]: Setting up hyprbars plugin...${STY_RST}"

  # Remove artifacts from earlier hyprpm-based approaches if they exist.
  # Doing this unconditionally means a reinstall always lands in a
  # clean state.
  try systemctl --user stop hyprland-plugins-setup.service 2>/dev/null
  try rm -f "$HOME/.config/systemd/user/hyprland-plugins-setup.service"
  try systemctl --user daemon-reload 2>/dev/null
  try sudo rm -f /usr/local/bin/hyprland-plugins-setup
  try sudo rm -f /etc/sudoers.d/hyprpm
  local EXECS_LUA="$HOME/.config/hypr/custom/execs.lua"
  if [[ -f "$EXECS_LUA" ]] && grep -q 'hyprland-plugins-setup' "$EXECS_LUA"; then
    sed -i '/-- Defer hyprpm to first login/d; /hyprland-plugins-setup/d' "$EXECS_LUA"
    echo -e "${STY_BLUE}[$0]: Removed old hyprland-plugins-setup trigger from $EXECS_LUA${STY_RST}"
  fi

  if ! _ensure_hyprland_plugin \
        "hyprbars" \
        "https://github.com/MainstreamOS/hyprland-plugins" \
        "mainstream" \
        "hyprbars" \
        "hyprbars.so"; then
    return 1
  fi

  local plugin_dir="$HOME/.local/share/hyprland/plugins"
  local plugin_path="$plugin_dir/hyprbars.so"
  record_installed "$plugin_path"

  # The plugin { hyprbars { ... } } settings block already lives in
  # custom/general.lua (shipped with the dots). We prepend the load directive
  # to the same file — Hyprland requires the .so to be loaded before its
  # settings block is parsed, otherwise the config is silently ignored.
  # hyprbars stays loaded always; the Title Bars toggle flips
  # plugin:hyprbars:enabled via the titlebars.enabled flag, not this line.
  # ---------------------------------------------------------------------------
  # Plugin machinery moved out of custom/general.lua and into the shipped
  # hyprland/plugins.lua. custom/ is written once at install and never again, so
  # anything left in the old copy would go on loading the plugins and
  # registering its own config.reloaded handler beside the shipped one: the
  # plugins would be configured twice per reload, by two versions of the same
  # code.
  #
  # Only a file that still carries that machinery is touched, and it is moved
  # aside rather than deleted, because it is the user's file and anything they
  # added to it is theirs.
  # ---------------------------------------------------------------------------
  local _custom_general="$HOME/.config/hypr/custom/general.lua"
  if [[ -f "$_custom_general" ]] && grep -q 'applyPluginConfig' "$_custom_general"; then
    if mv "$_custom_general" "$_custom_general.pre-plugins-move"; then
      install -Dm644 "dots/.config/hypr/custom/general.lua" "$_custom_general"
      echo -e "${STY_CYAN}[$0]: Plugin settings now ship in hyprland/plugins.lua; your old custom/general.lua was kept as general.lua.pre-plugins-move${STY_RST}"
    else
      echo -e "${STY_YELLOW}[$0]: Could not move $_custom_general aside; plugins may be configured twice until it is${STY_RST}"
    fi
  fi

  # No load directive is written here. hyprland/plugins.lua loads this same
  # path only when the .so was built for the running Hyprland, and a bare
  # load line written beside it would run without that check — which is how
  # a stale plugin takes the compositor down at login.
  echo -e "${STY_BLUE}[$0]: hyprbars.so ready at ${plugin_path} (loaded by hyprland/plugins.lua once it matches the running Hyprland).${STY_RST}"

  # ---------------------------------------------------------------------------
  # Install rebuild hook so future `pacman -Syu` keeps hyprbars in sync.
  # Hyprland's plugin ABI is pinned to the exact compositor version, so a
  # plugin built today stops loading the moment hyprland gets a patch bump
  # (the "headers ver is not equal to running hyprland ver" error). The
  # pacman hook re-runs the build whenever the `hyprland` package is
  # installed/upgraded; the script is shared by archiso so the same logic
  # ships on freshly-installed systems too.
  # ---------------------------------------------------------------------------
  _install_plugin_rebuild_hook "hyprbars"

  # The install-time build + the pacman hook above keep hyprbars in sync on
  # hyprland upgrades. The old per-boot retry timer rebuilt on every boot even
  # when nothing changed (redundant + wasteful), so it's no longer installed —
  # matching the archiso path. Disable + remove any copy left from an earlier run.
  _remove_legacy_plugin_timer "hyprbars"

  # ---------------------------------------------------------------------------
  # Install the user-side notification script and wire it into Hyprland's
  # exec-once. Reads /var/lib/hyprbars/status (written by rebuild.sh on state
  # transitions) and surfaces friendly desktop notifications:
  #   * after a failed rebuild  -> "Title bars are off for now"
  #   * after recovery          -> "Title bars are back"
  # Wording deliberately avoids version numbers, "rebuild", or "plugin" so the
  # user just sees a status update, not a build report.
  # ---------------------------------------------------------------------------
  _wire_plugin_status_notify "hyprbars" "$EXECS_LUA" \
"-- Surface friendly desktop notifications when title bars are temporarily
-- off (after a Hyprland update) or come back. Reads /var/lib/hyprbars/status
-- written by the system-side hyprbars-rebuild service."
}

function setup_scrolloverview_plugin(){
  # Set up hyprland-scroll-overview: the .so lives at
  # ~/.local/share/hyprland/plugins/scrolloverview.so loaded via a
  # `plugin = ...` directive. No hyprpm, no systemd service, no
  # sudoers — the .so is owned by the user and Hyprland loads it as
  # the user.
  #
  # Bulletproof flow (handled by _ensure_hyprland_plugin):
  #   1. archiso may have shipped a prebuilt scrolloverview.so via
  #      /etc/skel
  #   2. Always try to rebuild fresh against the installed hyprland —
  #      that's the only way to guarantee ABI match for first-load
  #   3. If the rebuild succeeds, the freshly-built .so replaces the
  #      prebuilt
  #   4. If the rebuild fails and a prebuilt is in place, keep the
  #      prebuilt as a best-effort fallback and let the pacman rebuild
  #      hook fix it on the next hyprland upgrade
  #   5. If the rebuild fails and no prebuilt exists, hard error
  echo -e "${STY_CYAN}[$0]: Setting up scrolloverview plugin...${STY_RST}"

  if ! _ensure_hyprland_plugin \
        "scrolloverview" \
        "https://github.com/MainstreamOS/hyprland-scroll-overview" \
        "mainstream" \
        "" \
        "scrolloverview.so"; then
    return 1
  fi

  local plugin_dir="$HOME/.local/share/hyprland/plugins"
  local plugin_path="$plugin_dir/scrolloverview.so"
  record_installed "$plugin_path"

  # As with hyprbars, no load directive is written here: hyprland/plugins.lua
  # loads this path behind the same version check, and an unguarded copy of
  # that line is what turns a stale plugin into a failed login.
  echo -e "${STY_BLUE}[$0]: scrolloverview.so ready at ${plugin_path} (loaded by hyprland/plugins.lua once it matches the running Hyprland).${STY_RST}"

  # ---------------------------------------------------------------------------
  # Install rebuild hook so future `pacman -Syu` keeps scrolloverview in sync.
  # Same rationale as hyprbars: Hyprland's plugin ABI is pinned to the exact
  # compositor version, so a plugin built today stops loading the moment
  # hyprland gets a patch bump. The pacman hook re-runs the build whenever
  # the `hyprland` package is installed/upgraded.
  # ---------------------------------------------------------------------------
  _install_plugin_rebuild_hook "scrolloverview"

  # The install-time build + the pacman hook above keep scrolloverview in sync on
  # hyprland upgrades. The old per-boot retry timer rebuilt on every boot even
  # when nothing changed (redundant + wasteful), so it's no longer installed —
  # matching the archiso path. Disable + remove any copy left from an earlier run.
  _remove_legacy_plugin_timer "scrolloverview"

  # ---------------------------------------------------------------------------
  # Install the user-side notification script and wire it into Hyprland's
  # exec-once. Reads /var/lib/scrolloverview/status (written by rebuild.sh on
  # state transitions) and surfaces friendly desktop notifications:
  #   * after a failed rebuild  -> "Workspace overview is off for now"
  #   * after recovery          -> "Workspace overview is back"
  # Wording deliberately avoids version numbers, "rebuild", or "plugin" so
  # the user just sees a status update, not a build report.
  # ---------------------------------------------------------------------------
  _wire_plugin_status_notify "scrolloverview" "$HOME/.config/hypr/custom/execs.lua" \
"-- Surface friendly desktop notifications when the workspace overview is
-- temporarily off (after a Hyprland update) or comes back. Reads
-- /var/lib/scrolloverview/status written by the system-side
-- scrolloverview-rebuild service."
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
  record_installed "$target_dir"
}

function _console_preload_steam_deck_client(){
  # Pre-fetch Steam's Deck-branch (gamescope / Big Picture) client so the first
  # boot into gaming isn't spent downloading it. Headless via Xvfb, best-effort;
  # on any failure the first-boot preload timer (mainstream-gaming) is the
  # fallback. Mirrors the ISO Console install's live download.
  local steam_dir="$HOME/.local/share/Steam"
  local manifest="$steam_dir/package/steam_client_steamdeck_stable_ubuntu12.installed"
  if [[ -s "$manifest" ]]; then
    echo -e "${STY_BLUE}[$0]: Steam Deck client already present — skipping pre-fetch.${STY_RST}"
    return 0
  fi
  local pulled_xvfb=0
  if ! command -v xvfb-run >/dev/null 2>&1; then
    try sudo pacman -S --needed --noconfirm xorg-server-xvfb || return 0
    pulled_xvfb=1
  fi
  mkdir -p "$steam_dir/package"
  if [[ ! -e "$steam_dir/steam.sh" && -f /usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz ]]; then
    tar -xf /usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz -C "$steam_dir" 2>/dev/null || true
  fi
  echo steamdeck_stable > "$steam_dir/package/beta"
  echo -e "${STY_CYAN}[$0]: Pre-fetching the Steam gamescope client (this can take a few minutes)...${STY_RST}"
  setsid xvfb-run -a steam -silent </dev/null >/dev/null 2>&1 &
  local _i
  for _i in $(seq 1 180); do
    [[ -s "$manifest" ]] && break
    sleep 5
  done
  steam -shutdown >/dev/null 2>&1 || true
  sleep 3
  pkill -u "$USER" -f steam 2>/dev/null || true
  pkill -u "$USER" -f Xvfb  2>/dev/null || true
  if [[ "$pulled_xvfb" -eq 1 ]]; then
    sudo pacman -Rns --noconfirm xorg-server-xvfb >/dev/null 2>&1 || true
  fi
  if [[ -s "$manifest" ]]; then
    echo -e "${STY_GREEN}[$0]: Steam gamescope client ready.${STY_RST}"
    record_installed "$steam_dir" || true
  else
    echo -e "${STY_YELLOW}[$0]: Client not fully fetched — the first-boot preload will finish it.${STY_RST}"
  fi
}

function setup_console_mode(){
  # Mirror of the ISO's Console install: install Steam and the 32-bit gaming
  # stack, boot straight into the Steam gamescope session on first boot, and
  # pre-fetch the Deck client. mainstream-gaming (always installed) provides the
  # gaming-mode-* tooling and the sddm arm-check; setup_sddm_pixie and
  # setup_gamescope (2.setups.sh) already installed SDDM and the gamescope
  # runtime by the time this runs.
  [[ "${CONSOLE_MODE_INSTALL:-false}" == true ]] || return 0
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    echo -e "${STY_YELLOW}[$0]: Console mode is Arch-only. Skipping.${STY_RST}"
    return 0
  fi
  ms_section "Setting up Console (gaming) mode..."

  # 1. Steam + the 32-bit gaming stack (the heavy half kept out of the base
  #    install). gaming-mode-install ships with mainstream-gaming.
  if [[ -x /usr/bin/gaming-mode-install ]]; then
    try sudo /usr/bin/gaming-mode-install
  else
    echo -e "${STY_YELLOW}[$0]: gaming-mode-install missing — installing Steam directly.${STY_RST}"
    try sudo pacman -Sy --needed --noconfirm steam
  fi

  # 2. Controller support, like the ISO Console install: the Xbox Bluetooth
  #    driver and the game-devices udev rules, one command per package so a
  #    missing repo entry skips that package without losing the other.
  try sudo pacman -S --needed --noconfirm mainstream-xpadneo
  try sudo pacman -S --needed --noconfirm game-devices-udev

  # 3. Boot straight into the Steam gamescope session. gaming-mode-arm-check (an
  #    sddm ExecStartPre from mainstream-gaming) reads boot-target on the first
  #    cold boot and arms the autologin.
  if [[ -x /usr/bin/gaming-mode-switch ]]; then
    try sudo /usr/bin/gaming-mode-switch set boot-target gaming
  else
    echo -e "${STY_YELLOW}[$0]: gaming-mode-switch missing — cannot set boot-to-gaming (is mainstream-gaming installed?).${STY_RST}"
  fi

  # 4. Pre-provision the Deck client so the first boot isn't a download.
  if command -v steam >/dev/null 2>&1; then
    _console_preload_steam_deck_client || true
  fi
}

function setup_proton_ge(){
  # Download the latest GE-Proton release into ~/.local/share/Steam/compatibilitytools.d
  # and preseed Steam's global compat-tool default to that version.
  #
  # Safe to re-run: skips the download when the latest tag is already installed,
  # and never clobbers existing per-game compat-tool overrides in config.vdf.

  # ── Skip unless Steam is installed ──────────────────────────────────────────
  if ! command -v steam &>/dev/null; then
    echo -e "${STY_BLUE}[$0]: Steam not installed — skipping Proton GE.${STY_RST}"
    return 0
  fi

  echo -e "${STY_CYAN}[$0]: Checking for latest GE-Proton release...${STY_RST}"

  local _missing=()
  for cmd in curl tar python3; do
    command -v "$cmd" &>/dev/null || _missing+=("$cmd")
  done
  if (( ${#_missing[@]} > 0 )); then
    echo -e "${STY_RED}[$0]: Missing required tools: ${_missing[*]} — skipping Proton GE install.${STY_RST}"
    return 0
  fi

  # ── Resolve latest release tag (e.g. "GE-Proton10-5") ─────────────────────
  local api_url="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"
  local release_json
  release_json=$(curl -fsSL "$api_url") || {
    echo -e "${STY_YELLOW}[$0]: GitHub API query failed — skipping Proton GE (set a version in Steam later).${STY_RST}"
    return 0
  }

  local tag
  if command -v jq &>/dev/null; then
    tag=$(echo "$release_json" | jq -r '.tag_name')
  else
    tag=$(echo "$release_json" | python3 -c \
      "import sys,json; print(json.load(sys.stdin)['tag_name'])")
  fi

  if [[ -z "$tag" || "$tag" == "null" ]]; then
    echo -e "${STY_YELLOW}[$0]: Could not determine latest Proton GE tag — skipping.${STY_RST}"
    return 0
  fi
  echo -e "${STY_CYAN}[$0]: Latest GE-Proton: $tag${STY_RST}"

  # ── Download + extract (skip if already present) ───────────────────────────
  local steam_store="$HOME/.local/share/Steam"
  local compat_dir="$steam_store/compatibilitytools.d"
  local install_dir="$compat_dir/$tag"

  if [[ -d "$install_dir" ]]; then
    echo -e "${STY_BLUE}[$0]: $tag already installed — skipping download.${STY_RST}"
  else
    # GE-Proton now ships an -aarch64 tarball alongside the x86_64 build, so a
    # broad endswith(".tar.gz") match returns TWO urls and corrupts the curl
    # argument with an embedded newline. Match the exact x86_64 asset name.
    local tarball_url
    if command -v jq &>/dev/null; then
      tarball_url=$(echo "$release_json" | \
        jq -r --arg tag "$tag" '.assets[] | select(.name == ($tag + ".tar.gz")) | .browser_download_url')
    else
      tarball_url=$(echo "$release_json" | python3 -c "
import sys, json
tag = '$tag'
for a in json.load(sys.stdin)['assets']:
    if a['name'] == tag + '.tar.gz':
        print(a['browser_download_url']); break
")
    fi

    if [[ -z "$tarball_url" ]]; then
      echo -e "${STY_YELLOW}[$0]: No x86_64 .tar.gz asset found for $tag — skipping.${STY_RST}"
      return 0
    fi

    echo -e "${STY_CYAN}[$0]: Downloading $tag...${STY_RST}"
    mkdir -p "$compat_dir" || true
    local tmp_tar; tmp_tar=$(mktemp --suffix=.tar.gz)
    # Non-fatal: GE-Proton is an optional gaming extra, so a download/extract
    # hiccup must skip (return 0) rather than abort the whole install via x().
    if ! curl -fL --progress-bar -o "$tmp_tar" "$tarball_url"; then
      echo -e "${STY_YELLOW}[$0]: GE-Proton download failed — skipping (set a Proton version in Steam later).${STY_RST}"
      rm -f "$tmp_tar"
      return 0
    fi
    echo -e "${STY_CYAN}[$0]: Extracting to $compat_dir...${STY_RST}"
    if ! tar -xzf "$tmp_tar" -C "$compat_dir"; then
      echo -e "${STY_YELLOW}[$0]: GE-Proton extract failed — skipping.${STY_RST}"
      rm -f "$tmp_tar"
      return 0
    fi
    rm -f "$tmp_tar"
    echo -e "${STY_GREEN}[$0]: Installed $tag to $install_dir${STY_RST}"
    record_installed "$install_dir" || true
  fi

  # ── Preseed Steam config ───────────────────────────────────────────────────
  # Sets the "0" (global default) CompatToolMapping entry only.
  # Existing per-game overrides and all other Steam settings are left alone.
  local config_dir="$steam_store/config"
  local config_vdf="$config_dir/config.vdf"
  x mkdir -p "$config_dir"

  if [[ ! -f "$config_vdf" ]]; then
    # No config yet — write a minimal seed file Steam will extend on first launch.
    echo -e "${STY_CYAN}[$0]: Creating $config_vdf seeded with $tag...${STY_RST}"
    cat > "$config_vdf" <<EOF
"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"CompatToolMapping"
				{
					"0"
					{
						"name"		"$tag"
						"config"	""
						"priority"	"1"
					}
				}
			}
		}
	}
}
EOF
    echo -e "${STY_GREEN}[$0]: Created $config_vdf — global Proton default: $tag.${STY_RST}"
    record_installed "$config_vdf"
  else
    # config.vdf already exists — surgically patch only the "0" block inside
    # CompatToolMapping so we never clobber per-game overrides or other settings.
    echo -e "${STY_CYAN}[$0]: Patching $config_vdf → global default: $tag...${STY_RST}"
    python3 - "$config_vdf" "$tag" <<'PYEOF'
import sys, re

vdf_path, tag = sys.argv[1], sys.argv[2]

with open(vdf_path) as f:
    content = f.read()

zero_block = (
    '\n\t\t\t\t\t"0"\n'
    '\t\t\t\t\t{\n'
    f'\t\t\t\t\t\t"name"\t\t"{tag}"\n'
    '\t\t\t\t\t\t"config"\t""\n'
    '\t\t\t\t\t\t"priority"\t"1"\n'
    '\t\t\t\t\t}\n\t\t\t\t'
)

ctm_re = re.compile(r'("CompatToolMapping"\s*\{)(.*?)(\})', re.DOTALL)
m = ctm_re.search(content)

if m:
    # Strip any existing "0" entry, then prepend our block.
    body = re.sub(r'\s*"0"\s*\{[^}]*\}', '', m.group(2), flags=re.DOTALL)
    new_content = content[:m.start()] + m.group(1) + zero_block + body + m.group(3) + content[m.end():]
else:
    sys.stderr.write("Warning: CompatToolMapping not found in config.vdf — skipping patch.\n")
    sys.exit(0)

with open(vdf_path, 'w') as f:
    f.write(new_content)

print(f"Patched: global Proton default → {tag}")
PYEOF
    if [[ $? -eq 0 ]]; then
      echo -e "${STY_GREEN}[$0]: $config_vdf updated.${STY_RST}"
    else
      echo -e "${STY_YELLOW}[$0]: Could not patch $config_vdf — set Proton version manually in Steam.${STY_RST}"
    fi
  fi

  # ── Link ~/.steam to the Steam data dir ────────────────────────────────────
  x mkdir -p "$HOME/.steam"
  # A prior Steam run can leave ~/.steam/{steam,root} as real directories, which
  # ln -sfnT can't overwrite; clear a stale one first (these only point at the
  # data in $steam_store) so the last install step doesn't abort.
  for _steam_link in "$HOME/.steam/steam" "$HOME/.steam/root"; do
    if [[ -e "$_steam_link" && ! -L "$_steam_link" ]]; then
      rmdir "$_steam_link" 2>/dev/null \
        || mv --backup=numbered -T "$_steam_link" "$_steam_link.pre-mainstream" 2>/dev/null \
        || true
    fi
  done
  x ln -sfnT "$steam_store" "$HOME/.steam/steam"
  x ln -sfnT "$steam_store" "$HOME/.steam/root"
}

function apply_os_only_prune(){
  # Mirror of the ISO's OS-only install method: the default apps are not
  # installed, so drop the shipped .desktop overrides that would point at
  # nothing and prune the dock's pinned defaults down to apps that actually
  # resolve. Presence is only checked — nothing is ever uninstalled, so apps
  # the user already has keep their entries and pins.
  local desktop_dir="$XDG_DATA_HOME/applications"
  local cleanup_map=(
    "gimp:gimp.desktop:org.gimp.GIMP.desktop"
    "mpv:mpv.desktop"
    "spotify-launcher:spotify-launcher.desktop"
    "resources:net.nokyan.Resources.desktop"
    "impression:io.gitlab.adhami3310.Impression.desktop"
    "chromium:chromium.desktop"
  )
  local entry pkg df present
  for entry in "${cleanup_map[@]}"; do
    IFS=':' read -ra _parts <<< "$entry"
    pkg="${_parts[0]}"
    present=false
    pacman -Qq "$pkg" &>/dev/null && present=true
    if [[ "$present" == false ]]; then
      for df in "${_parts[@]:1}"; do
        if [[ -f "/var/lib/flatpak/exports/share/applications/$df" ]] || \
           [[ -f "$XDG_DATA_HOME/flatpak/exports/share/applications/$df" ]]; then
          present=true; break
        fi
      done
    fi
    if [[ "$present" == false ]]; then
      for df in "${_parts[@]:1}"; do
        if [[ -f "$desktop_dir/$df" ]]; then
          try rm -f "$desktop_dir/$df"
          echo -e "${STY_BLUE}[$0]: OS-only: removed $df ($pkg not installed)${STY_RST}"
        fi
      done
    fi
  done

  local config_qml="$XDG_CONFIG_HOME/quickshell/ii/modules/common/Config.qml"
  if [[ ! -f "$config_qml" ]]; then
    echo -e "${STY_BLUE}[$0]: OS-only: Config.qml not deployed; dock prune skipped.${STY_RST}"
    return 0
  fi
  python3 - "$config_qml" "$XDG_CONFIG_HOME/quickshell/ii/config.json" <<'PYEOF' || echo -e "${STY_YELLOW}[$0]: OS-only dock prune failed; dock defaults left as-is.${STY_RST}"
import json, os, re, sys

qml_path, json_path = sys.argv[1], sys.argv[2]
home = os.path.expanduser("~")
exempt = {"settings", "welcome-tutorial"}
app_dirs = [
    "/usr/share/applications",
    "/usr/local/share/applications",
    os.environ.get("XDG_DATA_HOME", f"{home}/.local/share") + "/applications",
    "/var/lib/flatpak/exports/share/applications",
    f"{home}/.local/share/flatpak/exports/share/applications",
]

available = set()
for directory in app_dirs:
    try:
        for entry in os.listdir(directory):
            if entry.endswith(".desktop"):
                available.add(entry[:-8].lower())
    except OSError:
        pass

def keep(app_id):
    if app_id.startswith("folder:"):
        return True
    if app_id.lower() in exempt:
        return True
    return app_id.lower() in available

pat = re.compile(r'(property\s+list<string>\s+pinnedApps\s*:\s*\[)(.*?)(\])', re.DOTALL)
src = open(qml_path, encoding="utf-8").read()
dropped = []

def rewrite(m):
    head, body, tail = m.group(1), m.group(2), m.group(3)
    ids = re.findall(r'"([^"]+)"', body)
    if "settings" not in ids:            # dock array only; leave launcher alone
        return m.group(0)
    kept = [i for i in ids if keep(i)]
    if kept == ids:
        return m.group(0)
    dropped.extend(i for i in ids if i not in kept)
    new_body = "\n                    " + ", ".join(f'"{i}"' for i in kept) + ",\n                "
    return head + new_body + tail

new = pat.sub(rewrite, src)
if dropped:
    open(qml_path, "w", encoding="utf-8").write(new)
    print("[os-only] pruned dock defaults: " + ", ".join(dropped))
else:
    print("[os-only] dock defaults already clean")

if os.path.isfile(json_path):
    try:
        with open(json_path, encoding="utf-8") as f:
            cfg = json.load(f)
        pins = cfg.get("dock", {}).get("pinnedApps")
        if isinstance(pins, list):
            kept = [i for i in pins if keep(i)]
            if kept != pins:
                cfg["dock"]["pinnedApps"] = kept
                with open(json_path, "w", encoding="utf-8") as f:
                    json.dump(cfg, f, indent=4)
                print("[os-only] pruned existing dock pins: "
                      + ", ".join(i for i in pins if i not in kept))
    except (ValueError, OSError):
        print("[os-only] config.json unreadable; existing dock pins left as-is")
PYEOF
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
  true) true ;;
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

# Starter Mainstream wallpapers for Super+W
if [[ -d dots/Pictures/Wallpapers ]]; then
  v rsync_dir__ignore_existing dots/Pictures/Wallpapers "$HOME/Pictures/Wallpapers"
fi

if [[ "${OS_ONLY_INSTALL:-false}" == true ]]; then
  showfun apply_os_only_prune
  v apply_os_only_prune
fi

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

showfun setup_scrolloverview_plugin
v setup_scrolloverview_plugin

# Apply GPU-dependent hypr dotfile tweaks (NVIDIA Wayland env vars, hypridle
# dpms delays, AQ_DRM_DEVICES for hybrid NVIDIA) now that custom/env.lua and
# hypridle.conf exist on disk. Safe no-op on non-NVIDIA systems and re-runs.
# Defined in 2.setups.sh; still in scope here because both files are sourced
# by ./setup in the same shell.
if declare -F setup_gpu_hypr_tweaks >/dev/null 2>&1; then
  showfun setup_gpu_hypr_tweaks
  v setup_gpu_hypr_tweaks
fi

showfun setup_console_mode
v setup_console_mode

showfun setup_proton_ge
v setup_proton_ge

#####################################################################################

# Reclaim install-time caches before finishing. Purge ONLY the pacman packages
# this run downloaded — those newer than the start marker dropped in
# 0.greeting.sh — so a setup run over an existing install leaves the user's
# pre-existing cache intact. Also drop uv's wheel cache and the dotfiles build
# cache (cloned plugin/font/mpris sources + build trees, dead weight once the
# .so/packages are installed; re-runs reclone). Best-effort so a failure can't
# abort the install.
function cleanup_install_caches(){
  [[ "$OS_GROUP_ID" == "arch" ]] || return 0
  echo -e "${STY_CYAN}[$0]: Cleaning up install caches...${STY_RST}"
  if [[ -f "$PACMAN_CACHE_MARKER" ]]; then
    try sudo find /var/cache/pacman/pkg -maxdepth 1 -type f -name '*.pkg.tar.*' -cnewer "$PACMAN_CACHE_MARKER" -delete
  fi
  try rm -rf "$HOME/.cache/uv"
  try rm -rf "$XDG_CACHE_HOME/dots-hyprland/cache"
}
v cleanup_install_caches

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
  printf "\n${STY_RED}[$0]: \!! Important \!! : Please ensure environment variable ${STY_RST} \$ILLOGICAL_IMPULSE_VIRTUAL_ENV ${STY_RED} is set to proper value (by default \"~/.local/state/quickshell/.venv\"), or Quickshell config will not work. We have already provided this configuration in ~/.config/hypr/hyprland/env.lua, but you need to ensure it is included in hyprland.lua, and also a restart is needed for applying it.${STY_RST}\n"
fi
