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
    git pull origin "$branch"
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

  cp -f "$build_dir/$so_filename" "$plugin_dir/$so_filename"
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

  if [[ "$_had_prebuilt" == true ]]; then
    echo -e "${STY_BLUE}[$0]: $name: prebuilt $so_filename present at $plugin_path${STY_RST}"
    echo -e "${STY_BLUE}[$0]:   Will rebuild against current hyprland to guarantee ABI match.${STY_RST}"
  fi

  if _build_hyprland_plugin_fresh "$name" "$repo_url" "$branch" "$subdir" "$so_filename"; then
    return 0
  fi

  if [[ "$_had_prebuilt" == true ]]; then
    echo -e "${STY_YELLOW}[$0]: $name: keeping prebuilt $so_filename as fallback.${STY_RST}"
    echo -e "${STY_YELLOW}[$0]:   This .so may not load if the build host's hyprland version differs${STY_RST}"
    echo -e "${STY_YELLOW}[$0]:   from yours. The pacman rebuild hook installed below will retry${STY_RST}"
    echo -e "${STY_YELLOW}[$0]:   from source on the next \`pacman -Syu\` that touches hyprland.${STY_RST}"
    return 0
  fi

  echo -e "${STY_RED}[$0]: $name: install failed — fresh build failed and no prebuilt fallback.${STY_RST}"
  echo -e "${STY_RED}[$0]:   Verify network connectivity and that the hyprland package + base-devel${STY_RST}"
  echo -e "${STY_RED}[$0]:   are installed, then re-run the installer.${STY_RST}"
  return 1
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
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "$plugin_path" >> "${INSTALLED_LISTFILE}"

  # The plugin { hyprbars { ... } } settings block already lives in
  # custom/general.lua (shipped with the dots). We prepend the load directive
  # to the same file — Hyprland requires the .so to be loaded before its
  # settings block is parsed, otherwise the config is silently ignored.
  local _general_lua="$HOME/.config/hypr/custom/general.lua"
  if [[ -f "$_general_lua" ]]; then
    if ! grep -qE 'hl\.plugin\.load.*hyprbars\.so' "$_general_lua"; then
      local _tmp; _tmp=$(mktemp)
      {
        echo "-- hyprbars plugin load directive (built from source at install time)"
        echo "-- TitleBars.qml toggles the comment prefix on this exact line."
        echo "-- hl.plugin.load(\"${plugin_path}\")"
        echo ""
        cat "$_general_lua"
      } > "$_tmp"
      mv "$_tmp" "$_general_lua"
      echo -e "${STY_CYAN}[$0]: Added commented hl.plugin.load(\"${plugin_path}\") to $_general_lua (enable via Title Bars toggle)${STY_RST}"
    else
      echo -e "${STY_BLUE}[$0]: $_general_lua already loads hyprbars; skipping.${STY_RST}"
    fi
  else
    echo -e "${STY_YELLOW}[$0]: $_general_lua missing — add this line to a sourced hypr config manually:${STY_RST}"
    echo -e "${STY_YELLOW}  hl.plugin.load(\"${plugin_path}\")${STY_RST}"
  fi

  # ---------------------------------------------------------------------------
  # Install rebuild hook so future `pacman -Syu` keeps hyprbars in sync.
  # Hyprland's plugin ABI is pinned to the exact compositor version, so a
  # plugin built today stops loading the moment hyprland gets a patch bump
  # (the "headers ver is not equal to running hyprland ver" error). The
  # pacman hook re-runs the build whenever the `hyprland` package is
  # installed/upgraded; the script is shared by archiso so the same logic
  # ships on freshly-installed systems too.
  # ---------------------------------------------------------------------------
  local _rebuild_src="$REPO_ROOT/sdata/hyprbars/rebuild.sh"
  local _hook_src="$REPO_ROOT/sdata/hyprbars/95-hyprbars-rebuild.hook"
  local _conf_src="$REPO_ROOT/sdata/hyprbars/hyprbars.conf"
  if [[ -f "$_rebuild_src" && -f "$_hook_src" ]]; then
    echo -e "${STY_CYAN}[$0]: Installing pacman rebuild hook for hyprbars...${STY_RST}"
    try sudo install -Dm755 "$_rebuild_src" /usr/local/lib/hyprbars/rebuild.sh
    try sudo install -Dm644 "$_hook_src"    /etc/pacman.d/hooks/95-hyprbars-rebuild.hook
    # Only drop the config file if the user hasn't customized one already —
    # they may have pinned a different commit/fork than the shipped default.
    if [[ -f "$_conf_src" && ! -f /etc/hyprbars.conf ]]; then
      try sudo install -Dm644 "$_conf_src" /etc/hyprbars.conf
    fi
    echo -e "${STY_GREEN}[$0]: Hook installed — hyprbars will auto-rebuild on hyprland upgrades.${STY_RST}"
  else
    echo -e "${STY_YELLOW}[$0]: rebuild hook sources missing under sdata/hyprbars/ — skipping auto-rebuild setup.${STY_RST}"
    echo -e "${STY_YELLOW}[$0]:   You will need to manually rebuild hyprbars after each hyprland upgrade.${STY_RST}"
  fi

  # ---------------------------------------------------------------------------
  # Install the systemd retry timer + service. The pacman hook above only fires
  # when hyprland is upgraded, so it can't recover from "hyprland released
  # today, upstream hyprland-plugins doesn't have a compat commit yet" — the
  # build fails and stays failed until the *next* hyprland upgrade. The timer
  # ticks once a day; the moment upstream merges a fix the next tick picks it
  # up and title bars come back automatically.
  # ---------------------------------------------------------------------------
  local _service_src="$REPO_ROOT/sdata/hyprbars/hyprbars-rebuild.service"
  local _timer_src="$REPO_ROOT/sdata/hyprbars/hyprbars-rebuild.timer"
  if [[ -f "$_service_src" && -f "$_timer_src" ]]; then
    echo -e "${STY_CYAN}[$0]: Installing hyprbars retry timer...${STY_RST}"
    try sudo install -Dm644 "$_service_src" /etc/systemd/system/hyprbars-rebuild.service
    try sudo install -Dm644 "$_timer_src"   /etc/systemd/system/hyprbars-rebuild.timer
    try sudo systemctl daemon-reload
    try sudo systemctl enable --now hyprbars-rebuild.timer
    echo -e "${STY_GREEN}[$0]: Timer enabled — title bars self-heal once upstream catches up after a Hyprland release.${STY_RST}"
  else
    echo -e "${STY_YELLOW}[$0]: hyprbars-rebuild.{service,timer} missing — skipping retry timer setup.${STY_RST}"
  fi

  # ---------------------------------------------------------------------------
  # Install the user-side notification script and wire it into Hyprland's
  # exec-once. Reads /var/lib/hyprbars/status (written by rebuild.sh on state
  # transitions) and surfaces friendly desktop notifications:
  #   * after a failed rebuild  -> "Title bars are off for now"
  #   * after recovery          -> "Title bars are back"
  # Wording deliberately avoids version numbers, "rebuild", or "plugin" so the
  # user just sees a status update, not a build report.
  # ---------------------------------------------------------------------------
  local _notify_src="$REPO_ROOT/sdata/hyprbars/hyprbars-status-notify.sh"
  if [[ -f "$_notify_src" ]]; then
    echo -e "${STY_CYAN}[$0]: Installing hyprbars status notifier...${STY_RST}"
    try sudo install -Dm755 "$_notify_src" /usr/local/bin/hyprbars-status-notify

    # Wire into the user's custom execs.lua. Idempotent — re-running the
    # installer doesn't add duplicate hl.on subscriptions. Each hl.on registers
    # an independent callback, so appending a second one for the same event is
    # additive (not destructive).
    if [[ -f "$EXECS_LUA" ]]; then
      if ! grep -q 'hyprbars-status-notify' "$EXECS_LUA"; then
        {
          echo ""
          echo "-- Surface friendly desktop notifications when title bars are temporarily"
          echo "-- off (after a Hyprland update) or come back. Reads /var/lib/hyprbars/status"
          echo "-- written by the system-side hyprbars-rebuild service."
          echo "hl.on(\"hyprland.start\", function() hl.exec_cmd(\"/usr/local/bin/hyprbars-status-notify\") end)"
        } >> "$EXECS_LUA"
        echo -e "${STY_BLUE}[$0]: Added hyprbars-status-notify hl.on subscription to $EXECS_LUA${STY_RST}"
      else
        echo -e "${STY_BLUE}[$0]: $EXECS_LUA already runs hyprbars-status-notify; skipping.${STY_RST}"
      fi
    else
      mkdir -p "$(dirname "$EXECS_LUA")"
      {
        echo "-- Hyprland custom start-up commands (managed by dots-hyprland)"
        echo ""
        echo "-- Surface friendly desktop notifications when title bars are temporarily"
        echo "-- off (after a Hyprland update) or come back. Reads /var/lib/hyprbars/status"
        echo "-- written by the system-side hyprbars-rebuild service."
        echo "hl.on(\"hyprland.start\", function() hl.exec_cmd(\"/usr/local/bin/hyprbars-status-notify\") end)"
      } > "$EXECS_LUA"
      echo -e "${STY_BLUE}[$0]: Created $EXECS_LUA with hyprbars-status-notify entry${STY_RST}"
    fi
  fi
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
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "$plugin_path" >> "${INSTALLED_LISTFILE}"

  # Add the load directive (active, not commented) to custom/general.lua so
  # the bar's top-left hot corner — which dispatches `scrolloverview:overview
  # on` — actually has a plugin to talk to. This is a deliberate deviation
  # from the hyprbars install, which keeps the directive commented because
  # there's a separate UI toggle for hyprbars; scroll-overview has no such
  # toggle and the hot corner depends on the plugin being loaded.
  local _general_lua="$HOME/.config/hypr/custom/general.lua"
  if [[ -f "$_general_lua" ]]; then
    if ! grep -qE 'hl\.plugin\.load.*scrolloverview\.so' "$_general_lua"; then
      local _tmp; _tmp=$(mktemp)
      {
        echo "-- scrolloverview plugin load directive (built from source at install time)"
        echo "hl.plugin.load(\"${plugin_path}\")"
        echo ""
        cat "$_general_lua"
      } > "$_tmp"
      mv "$_tmp" "$_general_lua"
      echo -e "${STY_CYAN}[$0]: Added hl.plugin.load(\"${plugin_path}\") to $_general_lua${STY_RST}"
    else
      echo -e "${STY_BLUE}[$0]: $_general_lua already loads scrolloverview; skipping.${STY_RST}"
    fi
  else
    echo -e "${STY_YELLOW}[$0]: $_general_lua missing — add this line to a sourced hypr config manually:${STY_RST}"
    echo -e "${STY_YELLOW}  hl.plugin.load(\"${plugin_path}\")${STY_RST}"
  fi

  # ---------------------------------------------------------------------------
  # Install rebuild hook so future `pacman -Syu` keeps scrolloverview in sync.
  # Same rationale as hyprbars: Hyprland's plugin ABI is pinned to the exact
  # compositor version, so a plugin built today stops loading the moment
  # hyprland gets a patch bump. The pacman hook re-runs the build whenever
  # the `hyprland` package is installed/upgraded.
  # ---------------------------------------------------------------------------
  local _rebuild_src="$REPO_ROOT/sdata/scrolloverview/rebuild.sh"
  local _hook_src="$REPO_ROOT/sdata/scrolloverview/95-scrolloverview-rebuild.hook"
  local _conf_src="$REPO_ROOT/sdata/scrolloverview/scrolloverview.conf"
  if [[ -f "$_rebuild_src" && -f "$_hook_src" ]]; then
    echo -e "${STY_CYAN}[$0]: Installing pacman rebuild hook for scrolloverview...${STY_RST}"
    try sudo install -Dm755 "$_rebuild_src" /usr/local/lib/scrolloverview/rebuild.sh
    try sudo install -Dm644 "$_hook_src"    /etc/pacman.d/hooks/95-scrolloverview-rebuild.hook
    if [[ -f "$_conf_src" && ! -f /etc/scrolloverview.conf ]]; then
      try sudo install -Dm644 "$_conf_src" /etc/scrolloverview.conf
    fi
    echo -e "${STY_GREEN}[$0]: Hook installed — scrolloverview will auto-rebuild on hyprland upgrades.${STY_RST}"
  else
    echo -e "${STY_YELLOW}[$0]: rebuild hook sources missing under sdata/scrolloverview/ — skipping auto-rebuild setup.${STY_RST}"
    echo -e "${STY_YELLOW}[$0]:   You will need to manually rebuild scrolloverview after each hyprland upgrade.${STY_RST}"
  fi

  # ---------------------------------------------------------------------------
  # Install the systemd retry timer + service. Same rationale as for hyprbars:
  # the pacman hook only fires when hyprland is upgraded, so it can't recover
  # from "hyprland released today, upstream hyprland-scroll-overview doesn't
  # have a compat commit yet" — the build fails and stays failed until the
  # *next* hyprland upgrade. The timer ticks once a day and self-heals as
  # soon as upstream merges a fix.
  # ---------------------------------------------------------------------------
  local _so_service_src="$REPO_ROOT/sdata/scrolloverview/scrolloverview-rebuild.service"
  local _so_timer_src="$REPO_ROOT/sdata/scrolloverview/scrolloverview-rebuild.timer"
  if [[ -f "$_so_service_src" && -f "$_so_timer_src" ]]; then
    echo -e "${STY_CYAN}[$0]: Installing scrolloverview retry timer...${STY_RST}"
    try sudo install -Dm644 "$_so_service_src" /etc/systemd/system/scrolloverview-rebuild.service
    try sudo install -Dm644 "$_so_timer_src"   /etc/systemd/system/scrolloverview-rebuild.timer
    try sudo systemctl daemon-reload
    try sudo systemctl enable --now scrolloverview-rebuild.timer
    echo -e "${STY_GREEN}[$0]: Timer enabled — workspace overview self-heals once upstream catches up after a Hyprland release.${STY_RST}"
  else
    echo -e "${STY_YELLOW}[$0]: scrolloverview-rebuild.{service,timer} missing — skipping retry timer setup.${STY_RST}"
  fi

  # ---------------------------------------------------------------------------
  # Install the user-side notification script and wire it into Hyprland's
  # exec-once. Reads /var/lib/scrolloverview/status (written by rebuild.sh on
  # state transitions) and surfaces friendly desktop notifications:
  #   * after a failed rebuild  -> "Workspace overview is off for now"
  #   * after recovery          -> "Workspace overview is back"
  # Wording deliberately avoids version numbers, "rebuild", or "plugin" so
  # the user just sees a status update, not a build report.
  # ---------------------------------------------------------------------------
  local _so_notify_src="$REPO_ROOT/sdata/scrolloverview/scrolloverview-status-notify.sh"
  local _so_execs_lua="$HOME/.config/hypr/custom/execs.lua"
  if [[ -f "$_so_notify_src" ]]; then
    echo -e "${STY_CYAN}[$0]: Installing scrolloverview status notifier...${STY_RST}"
    try sudo install -Dm755 "$_so_notify_src" /usr/local/bin/scrolloverview-status-notify

    # Wire into the user's custom execs.lua. Idempotent — re-running the
    # installer doesn't add duplicate hl.on subscriptions. Each hl.on registers
    # an independent callback, so appending another for the same event is
    # additive (not destructive).
    if [[ -f "$_so_execs_lua" ]]; then
      if ! grep -q 'scrolloverview-status-notify' "$_so_execs_lua"; then
        {
          echo ""
          echo "-- Surface friendly desktop notifications when the workspace overview is"
          echo "-- temporarily off (after a Hyprland update) or comes back. Reads"
          echo "-- /var/lib/scrolloverview/status written by the system-side"
          echo "-- scrolloverview-rebuild service."
          echo "hl.on(\"hyprland.start\", function() hl.exec_cmd(\"/usr/local/bin/scrolloverview-status-notify\") end)"
        } >> "$_so_execs_lua"
        echo -e "${STY_BLUE}[$0]: Added scrolloverview-status-notify hl.on subscription to $_so_execs_lua${STY_RST}"
      else
        echo -e "${STY_BLUE}[$0]: $_so_execs_lua already runs scrolloverview-status-notify; skipping.${STY_RST}"
      fi
    else
      mkdir -p "$(dirname "$_so_execs_lua")"
      {
        echo "-- Hyprland custom start-up commands (managed by dots-hyprland)"
        echo ""
        echo "-- Surface friendly desktop notifications when the workspace overview is"
        echo "-- temporarily off (after a Hyprland update) or comes back. Reads"
        echo "-- /var/lib/scrolloverview/status written by the system-side"
        echo "-- scrolloverview-rebuild service."
        echo "hl.on(\"hyprland.start\", function() hl.exec_cmd(\"/usr/local/bin/scrolloverview-status-notify\") end)"
      } > "$_so_execs_lua"
      echo -e "${STY_BLUE}[$0]: Created $_so_execs_lua with scrolloverview-status-notify entry${STY_RST}"
    fi
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

function setup_proton_ge(){
  # Download the latest GE-Proton release into ~/.steam/root/compatibilitytools.d
  # and preseed Steam's global compat-tool default to that version.
  #
  # Safe to re-run: skips the download when the latest tag is already installed,
  # and never clobbers existing per-game compat-tool overrides in config.vdf.

  echo -e "${STY_CYAN}[$0]: Checking for latest GE-Proton release...${STY_RST}"

  local _missing=()
  for cmd in curl tar python3; do
    command -v "$cmd" &>/dev/null || _missing+=("$cmd")
  done
  if (( ${#_missing[@]} > 0 )); then
    echo -e "${STY_RED}[$0]: Missing required tools: ${_missing[*]} — skipping Proton GE install.${STY_RST}"
    return 1
  fi

  # ── Resolve latest release tag (e.g. "GE-Proton10-5") ─────────────────────
  local api_url="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"
  local release_json
  release_json=$(curl -fsSL "$api_url") || {
    echo -e "${STY_RED}[$0]: GitHub API query failed — check network.${STY_RST}"
    return 1
  }

  local tag
  if command -v jq &>/dev/null; then
    tag=$(echo "$release_json" | jq -r '.tag_name')
  else
    tag=$(echo "$release_json" | python3 -c \
      "import sys,json; print(json.load(sys.stdin)['tag_name'])")
  fi

  if [[ -z "$tag" || "$tag" == "null" ]]; then
    echo -e "${STY_RED}[$0]: Could not determine latest Proton GE tag.${STY_RST}"
    return 1
  fi
  echo -e "${STY_CYAN}[$0]: Latest GE-Proton: $tag${STY_RST}"

  # ── Download + extract (skip if already present) ───────────────────────────
  local compat_dir="$HOME/.steam/root/compatibilitytools.d"
  local install_dir="$compat_dir/$tag"

  if [[ -d "$install_dir" ]]; then
    echo -e "${STY_BLUE}[$0]: $tag already installed — skipping download.${STY_RST}"
  else
    local tarball_url
    if command -v jq &>/dev/null; then
      tarball_url=$(echo "$release_json" | \
        jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url')
    else
      tarball_url=$(echo "$release_json" | python3 -c "
import sys, json
for a in json.load(sys.stdin)['assets']:
    if a['name'].endswith('.tar.gz'):
        print(a['browser_download_url']); break
")
    fi

    if [[ -z "$tarball_url" ]]; then
      echo -e "${STY_RED}[$0]: No .tar.gz asset found for $tag.${STY_RST}"
      return 1
    fi

    echo -e "${STY_CYAN}[$0]: Downloading $tag...${STY_RST}"
    x mkdir -p "$compat_dir"
    local tmp_tar; tmp_tar=$(mktemp --suffix=.tar.gz)
    x curl -fL --progress-bar -o "$tmp_tar" "$tarball_url"
    echo -e "${STY_CYAN}[$0]: Extracting to $compat_dir...${STY_RST}"
    x tar -xzf "$tmp_tar" -C "$compat_dir"
    rm -f "$tmp_tar"
    echo -e "${STY_GREEN}[$0]: Installed $tag to $install_dir${STY_RST}"
    x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
    realpath -se "$install_dir" >> "${INSTALLED_LISTFILE}"
  fi

  # ── Preseed Steam config ───────────────────────────────────────────────────
  # Sets the "0" (global default) CompatToolMapping entry only.
  # Existing per-game overrides and all other Steam settings are left alone.
  local config_dir="$HOME/.steam/root/config"
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
    x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
    realpath -se "$config_vdf" >> "${INSTALLED_LISTFILE}"
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

showfun setup_proton_ge
v setup_proton_ge

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
  printf "\n${STY_RED}[$0]: \!! Important \!! : Please ensure environment variable ${STY_RST} \$ILLOGICAL_IMPULSE_VIRTUAL_ENV ${STY_RED} is set to proper value (by default \"~/.local/state/quickshell/.venv\"), or Quickshell config will not work. We have already provided this configuration in ~/.config/hypr/hyprland/env.lua, but you need to ensure it is included in hyprland.lua, and also a restart is needed for applying it.${STY_RST}\n"
fi
