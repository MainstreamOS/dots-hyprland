# This script is meant to be sourced.
# It's not for directly running.

# shellcheck shell=bash

#####################################################################################
# Notes by @clsty:
#
# I'm not the one who developed this script (see issue#2284 which discussed about the history).
# However it contains many unnecessary logics. This is typically what AI will do.
# I don't really care if it's AI-generated or not, it's just an extra option in addition to ./setup install, so as long as the users say it works, it should be fine.
# However, it's not easy to maintain something like this.
# The redundant logic should be cleaned up someday.
#
# This also applies for exp-update.tester.sh, TBH I don't think that file is really needed, and it also looks like AI-generated. Just guessing though.
#####################################################################################
#
# exp-update.sh - Enhanced dotfiles update script
#
# Features:
# - Auto-detect repository structure (dots/ prefix or direct config)
# - Pull latest commits from remote
# - Rebuild packages if PKGBUILD files changed (user choice)
# - Handle config file conflicts with user choices
# - Respect .updateignore file for exclusions with flexible pattern matching:
#   - Exact matches (e.g., "path/to/file")
#   - Directory patterns (e.g., "path/to/dir/")
#   - Wildcards (e.g., "*.log", "path/*/file")
#   - Root-relative patterns (e.g., "/.config")
#   - Substring matching (prefix with "**", e.g., "**temp" matches any path containing "temp")
#
set -euo pipefail

# Note: The detect_repo_structure function below auto-detects the folder layout
# Try to find the packages directory (different names in different versions)
if which pacman &>/dev/null; then
  if [[ -d "${REPO_ROOT}/dist-arch" ]]; then
    ARCH_PACKAGES_DIR="${REPO_ROOT}/dist-arch"
  elif [[ -d "${REPO_ROOT}/arch-packages" ]]; then
    ARCH_PACKAGES_DIR="${REPO_ROOT}/arch-packages"
  elif [[ -d "${REPO_ROOT}/sdata/dist-arch" ]]; then
    ARCH_PACKAGES_DIR="${REPO_ROOT}/sdata/dist-arch"
  else
    ARCH_PACKAGES_DIR="${REPO_ROOT}/dist-arch"  # Default fallback
  fi
fi
UPDATE_IGNORE_FILE="${REPO_ROOT}/.updateignore"
XDG_UPDATE_IGNORE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/updateignore"
#TODO: remove in future and add script to migrate to XDG path
HOME_UPDATE_IGNORE_FILE="${HOME}/.updateignore" # Legacy support 

# Global arrays for cached ignore patterns (performance optimization)
declare -a IGNORE_PATTERNS=()
declare -a IGNORE_SUBSTRING_PATTERNS=()

# Track created directories to avoid redundant mkdir calls
declare -A CREATED_DIRS

# Auto-detect repository structure
detect_repo_structure() {
  local found_dirs=()
  
  # Check for dots/ prefixed structure
  if [[ -d "${REPO_ROOT}/dots/.config" ]]; then
    found_dirs+=("dots/.config")
    [[ -d "${REPO_ROOT}/dots/.local/bin" ]] && found_dirs+=("dots/.local/bin")
    [[ -d "${REPO_ROOT}/dots/.local/share" ]] && found_dirs+=("dots/.local/share")
  # Check for flat structure
  elif [[ -d "${REPO_ROOT}/.config" ]]; then
    found_dirs+=(".config")
    [[ -d "${REPO_ROOT}/.local/bin" ]] && found_dirs+=(".local/bin")
    [[ -d "${REPO_ROOT}/.local/share" ]] && found_dirs+=(".local/share")
  else
    # Manual detection of common directories
    for candidate in "dots/.config" ".config" "dots/.local/bin" ".local/bin" "dots/.local/share" ".local/share"; do
      if [[ -d "${REPO_ROOT}/${candidate}" ]]; then
        # Avoid duplicates
        if [[ ! " ${found_dirs[*]} " =~ " ${candidate} " ]]; then
          found_dirs+=("${candidate}")
        fi
      fi
    done
  fi
  
  if [[ ${#found_dirs[@]} -eq 0 ]]; then
    echo "ERROR: Could not detect repository structure" >&2
    return 1
  fi
  
  echo "${found_dirs[@]}"
}

# Directories to monitor for changes (will be auto-detected)
MONITOR_DIRS=()

# Enhanced safe_read with better terminal handling
safe_read() {
  local prompt="$1"
  local varname="$2"
  local default="${3:-}"
  local input_value=""

  # In non-interactive mode, use default immediately
  if [[ "$NON_INTERACTIVE" == true ]]; then
    if [[ -n "$default" ]]; then
      printf -v "$varname" '%s' "$default"
      return 0
    else
      log_error "Non-interactive mode requires default value for: $prompt"
      return 1
    fi
  fi

  echo -n "$prompt"
  
  # First, try reading from stdin (supports piped input like "yes 1 |")
  if read -r -t 0.1 input_value 2>/dev/null; then
    # Successfully read from stdin (piped input)
    if [[ -n "$input_value" ]]; then
      printf -v "$varname" '%s' "$input_value"
      return 0
    fi
  fi
  
  # If stdin had no data, try interactive terminal
  if [[ -t 0 ]]; then
    # stdin is a terminal
    read -r input_value
  elif [[ -r /dev/tty ]]; then
    # Try reading from tty
    if read -r input_value </dev/tty 2>/dev/null; then
      : # Success
    else
      input_value=""
    fi
  else
    # No interactive terminal available
    if [[ -n "$default" ]]; then
      echo
      log_warning "No terminal available. Using default: $default"
      printf -v "$varname" '%s' "$default"
      return 0
    else
      echo
      log_error "No terminal available and no default provided"
      return 1
    fi
  fi

  if [[ -n "$input_value" ]]; then
    printf -v "$varname" '%s' "$input_value"
    return 0
  elif [[ -n "$default" ]]; then
    echo
    log_warning "Empty input. Using default: $default"
    printf -v "$varname" '%s' "$default"
    return 0
  else
    echo
    log_error "Input required but not provided"
    return 1
  fi
}

# Load and cache ignore patterns for performance
load_ignore_patterns() {
  IGNORE_PATTERNS=()
  IGNORE_SUBSTRING_PATTERNS=()
  
  for ignore_file in "$UPDATE_IGNORE_FILE" "$XDG_UPDATE_IGNORE_FILE" "$HOME_UPDATE_IGNORE_FILE"; do
    [[ ! -f "$ignore_file" ]] && continue
    
    while IFS= read -r pattern || [[ -n "$pattern" ]]; do
      # Skip empty lines and comments
      [[ -z "$pattern" || "$pattern" =~ ^[[:space:]]*# ]] && continue
      # Remove whitespace
      pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$pattern" ]] && continue
      
      # Separate substring patterns from regular patterns
      if [[ "${pattern:0:2}" == "**" ]]; then
        local cleaned_pattern="${pattern#\*\*}"
        # Strip trailing asterisks
        while [[ "$cleaned_pattern" == *"*" ]] && [[ "${cleaned_pattern: -1}" == "*" ]]; do
          cleaned_pattern="${cleaned_pattern%\*}"
        done
        # Ensure we have a non-empty pattern
        if [[ -n "$cleaned_pattern" ]]; then
          IGNORE_SUBSTRING_PATTERNS+=("$cleaned_pattern")
        fi
      else
        IGNORE_PATTERNS+=("$pattern")
      fi
    done < "$ignore_file"
  done
  
  if [[ "$VERBOSE" == true ]]; then
    log_info "Loaded ${#IGNORE_PATTERNS[@]} ignore patterns and ${#IGNORE_SUBSTRING_PATTERNS[@]} substring patterns"
  fi
}

# Optimized should_ignore using cached patterns
should_ignore() {
  local file_path="$1"
  local relative_path="${file_path#$HOME/}"
  local repo_relative=""
  
  if [[ "$file_path" == "$REPO_ROOT"* ]]; then
    repo_relative="${file_path#$REPO_ROOT/}"
  fi

  # Check regular patterns
  for pattern in "${IGNORE_PATTERNS[@]}"; do
    # Exact match
    if [[ "$relative_path" == "$pattern" ]] || [[ "$repo_relative" == "$pattern" ]]; then
      return 0
    fi

    # Wildcard patterns (basic glob matching)
    if [[ "$relative_path" == $pattern ]] || [[ "$repo_relative" == $pattern ]]; then
      return 0
    fi

    # Directory patterns (ending with /)
    if [[ "$pattern" == */ ]]; then
      local dir_pattern="${pattern%/}"
      if [[ "$relative_path" == "$dir_pattern"/* ]] || [[ "$repo_relative" == "$dir_pattern"/* ]]; then
        return 0
      fi
    fi

    # Root-relative patterns (starting with /)
    if [[ "$pattern" == /* ]]; then
      local root_pattern="${pattern#/}"
      if [[ "$relative_path" == "$root_pattern" ]] || [[ "$relative_path" == "$root_pattern"/* ]] ||
         [[ "$repo_relative" == "$root_pattern" ]] || [[ "$repo_relative" == "$root_pattern"/* ]]; then
        return 0
      fi
    fi

    # Patterns with wildcards - check parent directories
    if [[ "$pattern" == *"*"* ]]; then
      local temp_path="$relative_path"
      while [[ "$temp_path" == */* ]]; do
        temp_path="${temp_path%/*}"
        if [[ "$temp_path" == $pattern ]]; then
          return 0
        fi
      done
    fi
  done

  # Check substring patterns
  for substring in "${IGNORE_SUBSTRING_PATTERNS[@]}"; do
    if [[ -n "$substring" && ("$file_path" == *"$substring"* || "$relative_path" == *"$substring"*) ]]; then
      return 0
    fi
  done

  return 1
}

# Efficient directory creation with caching
ensure_directory() {
  local dir="$1"
  
  # Check if already created in this run
  if [[ -n "${CREATED_DIRS[$dir]:-}" ]]; then
    return 0
  fi
  
  if [[ "$DRY_RUN" != true ]]; then
    if [[ ! -d "$dir" ]]; then
      if mkdir -p "$dir" 2>/dev/null; then
        CREATED_DIRS[$dir]=1
        if [[ "$VERBOSE" == true ]]; then
          log_info "Created directory: $dir"
        fi
      else
        log_error "Failed to create directory: $dir"
        return 1
      fi
    else
      CREATED_DIRS[$dir]=1
    fi
  else
    if [[ "$VERBOSE" == true ]] || [[ -z "${CREATED_DIRS[$dir]:-}" ]]; then
      log_info "[DRY-RUN] Would create directory: $dir"
    fi
    CREATED_DIRS[$dir]=1
  fi
  return 0
}

# Function to show file diff
show_diff() {
  local file1="$1"
  local file2="$2"

  echo -e "\n${STY_CYAN}Showing differences:${STY_RST}"
  echo -e "${STY_CYAN}Old file: $file1${STY_RST}"
  echo -e "${STY_CYAN}New file: $file2${STY_RST}"
  echo "----------------------------------------"

  if command -v diff &>/dev/null; then
    diff -u "$file1" "$file2" || true
  else
    echo "diff command not available"
  fi
  echo "----------------------------------------"
}

# Backup file before replacing
backup_file() {
  local file="$1"
  local backup_dir="${REPO_ROOT}/.update-backups"
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would backup: $file"
    return 0
  fi
  
  if [[ ! -f "$file" ]]; then
    log_warning "File does not exist, cannot backup: $file"
    return 1
  fi
  
  ensure_directory "$backup_dir" || return 1
  
  local backup_name
  local relative_name="${file#$HOME/}"
  backup_name="${relative_name//\//_}.${timestamp}.bak"
  # Nearly every path starts at .config, and a leading dot hid each backup
  # from a plain listing of the folder that holds them.
  while [[ "$backup_name" == .* ]]; do backup_name="${backup_name#.}"; done
  
  if cp -p "$file" "${backup_dir}/${backup_name}" 2>/dev/null; then
    EXP_LAST_BACKUP="${backup_dir}/${backup_name}"
    log_info "Backed up to: .update-backups/${backup_name}"
    return 0
  else
    log_error "Failed to create backup"
    return 1
  fi
}

# Writes the release's copy over the home one. The new bytes go in beside it
# and are renamed over it, so Hyprland or Quickshell reading the file while it
# is written sees the old file or the new one, never half of one. A linked
# file is written through as before, since renaming would replace the link.
#
# While EXP_STAGING is set the rename waits for exp_commit_staged, which puts
# a whole set in place at once.
_install_repo_file() {
  local repo_file="$1" home_file="$2" tmp
  if [[ -L "$home_file" ]]; then
    cp -p "$repo_file" "$home_file"
    return
  fi
  tmp="$(dirname "$home_file")/.$(basename "$home_file").update-new.$$"
  # Named for the exit handler, so a run stopped between the two steps does
  # not leave the copy beside the file.
  _exp_inflight_tmp="$tmp"
  if ! cp -p "$repo_file" "$tmp" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    _exp_inflight_tmp=""
    cp -p "$repo_file" "$home_file"
    return
  fi
  if (( ${EXP_STAGING:-0} )); then
    EXP_STAGE+=("$tmp" "$home_file")
    _exp_inflight_tmp=""
    return 0
  fi
  mv -f "$tmp" "$home_file" || { rm -f "$tmp" 2>/dev/null; cp -p "$repo_file" "$home_file"; }
  _exp_inflight_tmp=""
}

# Whether the home copy is byte for byte what an earlier release shipped at
# that path, which means the user never changed it. EXP_BASE_BLOBS holds the
# blob of each path in the releases the update starts from (exp_base_load).
exp_home_is_stock() {
  local home_file="$1" repo_rel="$2" blob
  [[ -n "${EXP_BASE_BLOBS[$repo_rel]:-}" && -f "$home_file" ]] || return 1
  blob=$(git -C "$REPO_ROOT" hash-object --no-filters -- "$home_file" 2>/dev/null) || return 1
  [[ " ${EXP_BASE_BLOBS[$repo_rel]} " == *" ${blob} "* ]]
}

# The unattended backup-and-replace. A file still as the last release shipped
# it is replaced without a backup, since there is nothing of the user's in it;
# one they changed is backed up first and named in the summary at the end.
_backup_and_replace() {
  local repo_file="$1" home_file="$2"
  if [[ "$NON_INTERACTIVE" == true ]] && exp_home_is_stock "$home_file" "${repo_file#"$REPO_ROOT"/}"; then
    if [[ "$DRY_RUN" != true ]]; then
      _install_repo_file "$repo_file" "$home_file"
      log_success "Replaced $home_file with repository version"
    fi
    return 0
  fi
  EXP_LAST_BACKUP=""
  if backup_file "$home_file"; then
    if [[ "$DRY_RUN" != true ]]; then
      _install_repo_file "$repo_file" "$home_file"
      log_success "Replaced $home_file with repository version"
      if [[ -n "$EXP_LAST_BACKUP" ]]; then
        EXP_OWN_REPLACED+=("${home_file}"$'\t'"${EXP_LAST_BACKUP}")
      fi
    fi
  fi
  return 0
}

# Function to handle file conflicts
handle_file_conflict() {
  local repo_file="$1"
  local home_file="$2"
  local filename=$(basename "$home_file")
  local dirname=$(dirname "$home_file")
  local choice=""
  local default_val="${DEFAULT_CHOICE:-6}"  # Use DEFAULT_CHOICE or 6 (skip) as fallback

  # In non-interactive mode, use default directly (acts like pressing Enter)
  if [[ "$NON_INTERACTIVE" == true ]]; then
    choice="$default_val"
    log_info "Using choice $choice for: $home_file"
  else
    echo -e "\n${STY_YELLOW}Conflict detected:${STY_RST} $home_file"
    echo "Repository version differs from your local version."
    # The Decorations pass after the copy writes the user's own values back
    # into these whatever is picked, so a replace is not a reset for them, and
    # someone picking one to get stock decorations back has to know that.
    if [[ -n "$DECO_CARRY_DIR" ]] && [[ "$home_file" == "${DECO_USER_FILES[0]}" || "$home_file" == "${DECO_USER_FILES[1]}" ]]; then
      echo "Values you changed in Settings > Decorations stay in this file whichever you choose."
    fi
    echo
    echo "Choose an action:"
    echo "1) Replace local file with repository version"
    echo "2) Keep local file unchanged"
    echo "3) Backup local file as ${filename}.old, use repository version"
    echo "4) Save repository version as ${filename}.new, keep local file"
    echo "5) Show diff and decide"
    echo "6) Skip this file"
    echo "7) Add to ignore and skip"
    echo "8) Backup to .update-backups/ and replace with repository version"
    echo

    while true; do
      if ! safe_read "Enter your choice (1-8 or name) [${default_val}]: " choice "$default_val"; then
        echo
        log_warning "Failed to read input. Skipping file."
        return
      fi

      # Validate choice
      if [[ "$choice" =~ ^[1-8]$ ]] || [[ "$choice" =~ ^(replace|keep|old|new|diff|skip|ignore|backup)$ ]]; then
        break
      else
        echo "Invalid choice. Please enter 1-8 or a valid name (replace, keep, old ...)."
      fi
    done
  fi

  # The user's copy as it is when the choice lands, which is what the
  # Decorations pass puts back if the choice replaces it.
  deco_carry_snapshot "$home_file"

  case $choice in
  1|replace)
    if [[ "$DRY_RUN" == true ]]; then
      log_info "[DRY-RUN] Would replace $home_file with repository version"
    else
      _install_repo_file "$repo_file" "$home_file"
      log_success "Replaced $home_file with repository version"
    fi
    ;;
  2|keep)
    log_info "Keeping local version of $home_file"
    ;;
  3|old)
    if [[ "$DRY_RUN" == true ]]; then
      log_info "[DRY-RUN] Would backup local file to ${filename}.old and update with repository version"
    else
      mv "$home_file" "${dirname}/${filename}.old"
      cp -p "$repo_file" "$home_file"
      log_success "Backed up local file to ${filename}.old and updated with repository version"
    fi
    ;;
  4|new)
    if [[ "$DRY_RUN" == true ]]; then
      log_info "[DRY-RUN] Would save repository version as ${filename}.new, keep local file"
    else
      cp -p "$repo_file" "${dirname}/${filename}.new"
      log_success "Saved repository version as ${filename}.new, kept local file"
    fi
    ;;
  5|diff)
    show_diff "$home_file" "$repo_file"
    echo
    echo "After reviewing the diff, choose:"
    echo "r) Replace with repository version"
    echo "k) Keep local version"
    echo "b) Backup local and use repository version"
    echo "n) Save repository version as .new"
    echo "s) Skip this file"
    echo "i) Add to ignore and skip"
    echo "B) Backup to .update-backups/ and replace"

    if ! safe_read "Enter your choice (r/k/b/n/s/i/B): " subchoice "s"; then
      echo
      log_warning "Failed to read input. Skipping file."
      return
    fi

    deco_carry_snapshot "$home_file"

    case $subchoice in
    r)
      if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would replace $home_file with repository version"
      else
        _install_repo_file "$repo_file" "$home_file"
        log_success "Replaced $home_file with repository version"
      fi
      ;;
    k)
      log_info "Keeping local version of $home_file"
      ;;
    b)
      if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would backup local file to ${filename}.old and update"
      else
        mv "$home_file" "${dirname}/${filename}.old"
        cp -p "$repo_file" "$home_file"
        log_success "Backed up local file to ${filename}.old and updated"
      fi
      ;;
    n)
      if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would save repository version as ${filename}.new"
      else
        cp -p "$repo_file" "${dirname}/${filename}.new"
        log_success "Saved repository version as ${filename}.new"
      fi
      ;;
    s)
      log_info "Skipping $home_file"
      ;;
    i)
      local relative_path_to_home="${home_file#$HOME/}"
      if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would add '$relative_path_to_home' to $XDG_UPDATE_IGNORE_FILE"
      else
        echo "$relative_path_to_home" >>"$XDG_UPDATE_IGNORE_FILE"
        log_success "Added '$relative_path_to_home' to $XDG_UPDATE_IGNORE_FILE and skipped."
      fi
      ;;
    B)
      _backup_and_replace "$repo_file" "$home_file"
      ;;
    *)
      log_info "Skipping $home_file"
      ;;
    esac
    ;;
  6|skip)
    log_info "Skipping $home_file"
    ;;
  7|ignore)
    local relative_path_to_home="${home_file#$HOME/}"
    if [[ "$DRY_RUN" == true ]]; then
      log_info "[DRY-RUN] Would add '$relative_path_to_home' to $XDG_UPDATE_IGNORE_FILE"
    else
      echo "$relative_path_to_home" >>"$XDG_UPDATE_IGNORE_FILE"
      log_success "Added '$relative_path_to_home' to $XDG_UPDATE_IGNORE_FILE and skipped."
    fi
    ;;
  8|backup)
    _backup_and_replace "$repo_file" "$home_file"
    ;;
  esac
}

# Function to check if PKGBUILD has changed
check_pkgbuild_changed() {
  # The loops hand this a glob match that ends in a slash, and a doubled
  # slash in the path matches nothing git prints.
  local pkg_dir="${1%/}"
  local pkgbuild_path="${pkg_dir}/PKGBUILD"

  [[ ! -f "$pkgbuild_path" ]] && return 1

  local relative_path="${pkgbuild_path#$REPO_ROOT/}"

  if [[ "$FORCE_CHECK" == true ]]; then
    return 0
  fi

  # Check if HEAD@{1} exists before trying to use it
  if ! git rev-parse --verify HEAD@{1} &>/dev/null; then
    # Fresh clone, assume all PKGBUILDs need checking
    return 0
  fi

  if git diff --name-only HEAD@{1} HEAD 2>/dev/null | grep -qxF -- "$relative_path"; then
    return 0
  fi

  return 1
}

# Whether building a package from the clone is the only way its new version
# can arrive: it is installed, and its PKGBUILD is newer than both the build
# that is installed and whatever the repositories serve. Anything a repository
# carries at that version comes in through pacman instead, a package the user
# removed stays removed, and a forced run builds nothing this does not allow.
pkgbuild_wants_build() {
  local pkg_dir="${1%/}" info name want have repo
  command -v vercmp >/dev/null 2>&1 || return 1
  info=$(
    set +eu
    # shellcheck source=/dev/null
    source "${pkg_dir}/PKGBUILD" >/dev/null 2>&1 || exit 1
    printf '%s %s' "${pkgname[0]:-}" "${epoch:+${epoch}:}${pkgver:-}-${pkgrel:-}"
  ) || return 1
  name="${info%% *}"
  want="${info#* }"
  [[ -n "$name" && "$want" != -* && "$want" != *- ]] || return 1
  have=$(pacman -Q "$name" 2>/dev/null) || return 1
  have="${have##* }"
  (( $(vercmp "$want" "$have") > 0 )) || return 1
  repo=$(LC_ALL=C pacman -Si "$name" 2>/dev/null | awk -F': *' '/^Version/ {print $2; exit}')
  if [[ -n "$repo" ]] && (( $(vercmp "$want" "$repo") <= 0 )); then
    return 1
  fi
  return 0
}

# Function to list available packages
list_packages() {
  local available_packages=()
  local changed_packages=()

  if [[ ! -d "$ARCH_PACKAGES_DIR" ]]; then
    log_warning "No package directory found"
    return 1
  fi

  for pkg_dir in "$ARCH_PACKAGES_DIR"/*/; do
    pkg_dir="${pkg_dir%/}"
    if [[ -f "${pkg_dir}/PKGBUILD" ]]; then
      local pkg_name=$(basename "$pkg_dir")
      available_packages+=("$pkg_name")

      if check_pkgbuild_changed "$pkg_dir"; then
        changed_packages+=("$pkg_name")
      fi
    fi
  done

  if [[ ${#available_packages[@]} -eq 0 ]]; then
    log_info "No packages found in package directory"
    return 1
  fi

  echo -e "\n${STY_CYAN}Available packages:${STY_RST}"
  for pkg in "${available_packages[@]}"; do
    if [[ " ${changed_packages[*]} " =~ " ${pkg} " ]]; then
      echo -e "  ${STY_GREEN}● ${pkg}${STY_RST} (PKGBUILD changed)"
    else
      echo -e "  ○ ${pkg}"
    fi
  done

  if [[ ${#changed_packages[@]} -gt 0 ]]; then
    echo -e "\n${STY_YELLOW}Packages with changed PKGBUILDs: ${changed_packages[*]}${STY_RST}"
  fi

  return 0
}

# Function to build selected packages
build_packages() {
  local build_mode="$1"
  local packages_to_build=()

  case "$build_mode" in
  "changed")
    for pkg_dir in "$ARCH_PACKAGES_DIR"/*/; do
      pkg_dir="${pkg_dir%/}"
      if [[ -f "${pkg_dir}/PKGBUILD" ]]; then
        local pkg_name=$(basename "$pkg_dir")
        if check_pkgbuild_changed "$pkg_dir" && pkgbuild_wants_build "$pkg_dir"; then
          packages_to_build+=("$pkg_name")
        fi
      fi
    done
    ;;
  "all")
    for pkg_dir in "$ARCH_PACKAGES_DIR"/*/; do
      pkg_dir="${pkg_dir%/}"
      if [[ -f "${pkg_dir}/PKGBUILD" ]]; then
        local pkg_name=$(basename "$pkg_dir")
        packages_to_build+=("$pkg_name")
      fi
    done
    ;;
  "select")
    echo -e "\nEnter package names separated by spaces (or 'all' for all packages):"
    if ! safe_read "Packages to build: " user_selection ""; then
      log_warning "Failed to read input. Skipping package builds."
      return
    fi

    if [[ "$user_selection" == "all" ]]; then
      for pkg_dir in "$ARCH_PACKAGES_DIR"/*/; do
        pkg_dir="${pkg_dir%/}"
        if [[ -f "${pkg_dir}/PKGBUILD" ]]; then
          local pkg_name=$(basename "$pkg_dir")
          packages_to_build+=("$pkg_name")
        fi
      done
    else
      read -ra packages_to_build <<<"$user_selection"
    fi
    ;;
  esac

  if [[ ${#packages_to_build[@]} -eq 0 ]]; then
    log_info "No packages selected for building"
    return
  fi

  echo -e "\n${STY_CYAN}Packages to build: ${packages_to_build[*]}${STY_RST}"

  if ! safe_read "Proceed with building these packages? (Y/n): " confirm "Y"; then
    log_warning "Failed to read input. Skipping package builds."
    return
  fi

  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    log_info "Package building cancelled by user"
    return
  fi
  
  for pkg_name in "${packages_to_build[@]}"; do
    pkg_dir="${ARCH_PACKAGES_DIR}/${pkg_name}"

    if [[ ! -d "$pkg_dir" || ! -f "${pkg_dir}/PKGBUILD" ]]; then
      log_error "Package not found or missing PKGBUILD: $pkg_name"
      continue
    fi

    log_info "Building package: $pkg_name"
    
    if [[ "$DRY_RUN" == true ]]; then
      log_info "[DRY-RUN] Would build package in temp directory and clean up after"
      continue
    fi

    # Create temp build directory to avoid polluting the repo
    local build_tmp_dir
    build_tmp_dir=$(mktemp -d "/tmp/pkgbuild-${pkg_name}-XXXXXX")
    # Known to the exit handler too, so a run stopped mid-build does not leave
    # it in /tmp, which is held in memory.
    _pkg_build_tmp="$build_tmp_dir"
    
    # Copy package files to temp directory (using /. to include hidden files)
    cp -r "$pkg_dir"/. "$build_tmp_dir/" || {
      log_error "Failed to copy package files to temp directory"
      rm -rf "$build_tmp_dir"
      _pkg_build_tmp=""
      continue
    }

    cd "$build_tmp_dir" || {
      log_error "Failed to change to temp build directory: $build_tmp_dir"
      rm -rf "$build_tmp_dir"
      _pkg_build_tmp=""
      continue
    }

    if makepkg -sCi --noconfirm; then
      log_success "Successfully built and installed $pkg_name"
      ((rebuilt_packages++)) || true
    else
      log_error "Failed to build package $pkg_name"
    fi

    # Clean up temp build directory
    cd "$REPO_ROOT" || log_die "Failed to return to repository directory"
    rm -rf "$build_tmp_dir"
    _pkg_build_tmp=""
    log_info "Cleaned up temp build directory"
    
    # Also clean any old build artifacts in the original package directory
    rm -rf "${pkg_dir}/src" "${pkg_dir}/pkg" "${pkg_dir}"/*.pkg.tar.* 2>/dev/null || true
  done

  if [[ $rebuilt_packages -eq 0 ]]; then
    log_warning "No packages were successfully built"
  else
    log_success "Successfully rebuilt $rebuilt_packages package(s)"
  fi
}

# Optimized function to get list of changed files
get_changed_files() {
  local dir_path="$1"

  if [[ "$FORCE_CHECK" == true ]]; then
    find "$dir_path" -type f -print0 2>/dev/null
    return
  fi

  # With a range to trust, what the release changed is the whole answer, even
  # when that is nothing in this folder. A file it did not touch stays as the
  # user left it, edits and deletions included.
  if [[ -n "${EXP_RANGE_BASE:-}" ]]; then
    local file
    git -C "$REPO_ROOT" diff -z --name-only --diff-filter=ACMR "$EXP_RANGE_BASE" HEAD -- "$dir_path" 2>/dev/null |
      while IFS= read -r -d '' file; do
        [[ -f "${REPO_ROOT}/${file}" ]] && printf '%s\0' "${REPO_ROOT}/${file}"
      done
    return 0
  fi

  # Try git-based detection first
  if git rev-parse --verify HEAD@{1} &>/dev/null 2>&1; then
    local temp_file
    temp_file=$(mktemp)
    
    # Get changed files with specific filters (Added, Copied, Modified, Renamed)
    git diff --name-only --diff-filter=ACMR HEAD@{1} HEAD 2>/dev/null | \
      while IFS= read -r file; do
        local full_path="${REPO_ROOT}/${file}"
        if [[ "$full_path" == "$dir_path"/* ]] && [[ -f "$full_path" ]]; then
          echo "$full_path"
        fi
      done > "$temp_file"
    
    if [[ -s "$temp_file" ]]; then
      # Found changes via git
      tr '\n' '\0' < "$temp_file"
      rm -f "$temp_file"
      return
    fi
    rm -f "$temp_file"
  fi
  
  # Fallback: check all files
  find "$dir_path" -type f -print0 2>/dev/null
}

# Whatever order the copy runs in, a reload that lands part-way through has to
# find a tree it can still load. It always can if files that do not exist yet
# are written before files that are being replaced.
#
# A tree carrying modules the running shell.qml does not reference yet loads
# fine. A shell.qml that has already been replaced and references a module not
# yet written does not, and that is exactly the shape users hit:
#   module "qs.modules.ii.desktopMenu" is not installed
#
# The reload hold is still the primary guard. This makes the window it covers
# survivable rather than fatal if it ever fails to engage again.
order_additions_first() {
  local repo_dir_path="$1" home_dir_path="$2"
  local repo_file rel_path home_file
  local -a additions=() modifications=()

  while IFS= read -r -d '' repo_file; do
    rel_path="${repo_file#"$repo_dir_path"/}"
    home_file="${home_dir_path}/${rel_path}"
    if [[ -e "$home_file" ]]; then
      modifications+=("$repo_file")
    else
      additions+=("$repo_file")
    fi
  done < <(get_changed_files "$repo_dir_path")

  local f
  if (( ${#additions[@]} )); then
    for f in "${additions[@]}"; do printf '%s\0' "$f"; done
  fi
  if (( ${#modifications[@]} )); then
    for f in "${modifications[@]}"; do printf '%s\0' "$f"; done
  fi
}

# Function to check if we have new commits
has_new_commits() {
  if git rev-parse --verify HEAD@{1} &>/dev/null; then
    [[ "$(git rev-parse HEAD)" != "$(git rev-parse HEAD@{1})" ]]
  else
    # Fresh clone or no reflog - assume we want to process files
    return 0
  fi
}

# Keeps the values a user changed in Settings > Decorations when a release
# replaces general.lua. Without the library the update runs as it would
# without the pass, so the calls below stay safe either way.
if [[ -r "${REPO_ROOT}/sdata/lib/decorations-carry.sh" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/sdata/lib/decorations-carry.sh"
fi
if ! declare -F deco_carry_finish >/dev/null; then
  DECO_CARRY_DIR=""
  deco_carry_begin() { :; }
  deco_carry_snapshot() { :; }
  deco_carry_finish() { :; }
fi

# config.json upgrades for settings a release renamed or reshaped, and the
# helper that brings the shell's Python packages in line with a new list.
# Each is optional, and a run without one goes on without that step.
if [[ -r "${REPO_ROOT}/sdata/lib/config-migrations.sh" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/sdata/lib/config-migrations.sh"
fi
if [[ -r "${REPO_ROOT}/sdata/lib/venv-common.sh" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/sdata/lib/venv-common.sh"
fi

EXP_UPDATE_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mainstream/exp-update.log"
EXP_RELOGIN_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/mainstream/relogin-needed"
EXP_DEFERRED_FILE="${REPO_ROOT}/.update-deferred"
EXP_DEFER=0
EXP_DEFER_WAIT_PID=""
EXP_DEFER_WAIT_START=""
EXP_BASE_SPEC=""
EXP_RANGE_BASE=""
EXP_LAST_BACKUP=""
EXP_STAGING=0
files_deferred=0
declare -ga EXP_STAGE=()
declare -ga EXP_OWN_REPLACED=()
declare -ga EXP_OWN_DEFERRED=()
declare -gA EXP_WATCHED=()
declare -gA EXP_BASE_BLOBS=()
declare -gA EXP_BASE_LOADED=()
declare -gA EXP_DEFERRED_SEEN=()
declare -gA EXP_RELOGIN_REASONS=()
_exp_relay_pid=""
_exp_inflight_tmp=""
_exp_holds_taken=0
_exp_shell_released=0

# The Update page of a Settings window from before 3.0.0 runs the update as
# its own child, and when that window restarts or closes, the pipe this
# writes to closes with it. The next write would then end the run wherever it
# stood, with half the files copied and nothing put back. Output goes through
# a relay instead, which outlives its reader and keeps a copy in the log.
# The relay passes on whole lines only, so a run someone answers prompts in
# keeps writing straight to its output, where a prompt shows before its answer.
exp_update_start_log() {
  local size
  [[ -t 1 || "${NON_INTERACTIVE:-false}" != true ]] && return 0
  mkdir -p "${EXP_UPDATE_LOG%/*}" 2>/dev/null || return 0
  size=$(stat -c %s "$EXP_UPDATE_LOG" 2>/dev/null || echo 0)
  if (( size > 1048576 )); then
    mv -f "$EXP_UPDATE_LOG" "${EXP_UPDATE_LOG}.old" 2>/dev/null || true
  fi
  printf '\n== %s exp-update ==\n' "$(date '+%F %T')" >>"$EXP_UPDATE_LOG" 2>/dev/null || true
  exec > >(
    set +e
    trap '' PIPE
    while IFS= read -r _l || [[ -n "$_l" ]]; do
      _p="${_l//$'\e['[0-9]m/}"
      printf '%s\n' "${_p//$'\e['[0-9][0-9]m/}" >>"$EXP_UPDATE_LOG" 2>/dev/null
      printf '%s\n' "$_l" 2>/dev/null
    done
  ) 2>&1
  _exp_relay_pid=$!
}

# Lets the relay write out what it still holds before the run hands back to
# its caller, so the caller's own lines come after this run's.
exp_update_close_log() {
  local i
  [[ -n "$_exp_relay_pid" ]] || return 0
  exec >&- 2>&-
  for (( i = 0; i < 50; i++ )); do
    kill -0 "$_exp_relay_pid" 2>/dev/null || break
    sleep 0.1
  done
  return 0
}

# What updatems and this run keep in the clone is not a local edit, but an
# updatems from before 3.0.0 treats anything untracked as one and stashes it
# before the run starts, the applied-tag marker and earlier backups included.
# Out of its sight, they stay where they are.
exp_protect_clone_state() {
  local exclude p prev head tag=""
  exclude=$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path info/exclude 2>/dev/null) || return 0
  mkdir -p "${exclude%/*}" 2>/dev/null || true
  for p in '.updatems-applied-tag' '.update-backups/' '.update-lock' '.update-deferred'; do
    grep -qxF -- "$p" "$exclude" 2>/dev/null || printf '%s\n' "$p" >>"$exclude" 2>/dev/null || true
  done
  # Such an updatems has already stashed the marker by the time this runs,
  # and without it a retry after a stopped run compares the whole tree. The
  # hop it set up starts at the release it last applied, so that release is
  # written back, but only when HEAD@{1} is a different commit carrying
  # exactly a release tag: a retry that already lost the marker parks on the
  # target itself, and writing that would record the release as delivered.
  [[ -e "${REPO_ROOT}/.updatems-applied-tag" || "$DRY_RUN" == true ]] && return 0
  prev=$(git -C "$REPO_ROOT" rev-parse -q --verify 'HEAD@{1}^{commit}' 2>/dev/null) || return 0
  head=$(git -C "$REPO_ROOT" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) || return 0
  [[ "$prev" != "$head" ]] || return 0
  tag=$(git -C "$REPO_ROOT" tag --points-at "$prev" 2>/dev/null | grep -E '^[0-9]{1,2}\.[0-9]+\.[0-9]+$' | sort -V | tail -n1) || tag=""
  [[ -n "$tag" ]] || return 0
  printf '%s\n' "$tag" >"${REPO_ROOT}/.updatems-applied-tag" 2>/dev/null || return 0
  log_info "Recorded ${tag} as the last applied release, so a stopped run repeats only this update"
}

# A lock only counts while its PID is still an update. One left behind by an
# older run can name a PID the system has since given to something else.
exp_lock_owner_live() {
  local pid="${1:-}" cmd
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  (( pid != $$ )) || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  cmd=$(tr '\0' ' ' 2>/dev/null <"/proc/${pid}/cmdline") || return 1
  [[ "$cmd" == *exp-update* || "$cmd" == *finish-deferred* ]]
}

# Reads a process's parent, state and start time (clock ticks since boot).
# A PID together with its start time names one process for good, where the
# PID alone can be handed to something new once the first has exited.
_exp_proc_stat() {
  local stat
  local -a f
  _exp_ppid="" _exp_start="" _exp_state=""
  { IFS= read -r stat <"/proc/${1}/stat"; } 2>/dev/null || return 1
  stat="${stat##*) }"
  read -ra f <<<"$stat"
  _exp_state="${f[0]:-}" _exp_ppid="${f[1]:-}" _exp_start="${f[19]:-}"
  [[ -n "$_exp_start" ]]
}

exp_proc_alive() {
  [[ -n "${1:-}" && -n "${2:-}" ]] || return 1
  _exp_proc_stat "$1" || return 1
  [[ "$_exp_start" == "$2" && "$_exp_state" != Z && "$_exp_state" != X ]]
}

# Every file a Quickshell instance started from $1 reloads on, following
# Quickshell's own scan (src/core/scan.cpp): the root file, then each
# capitalized .qml and .qml.json file in the root's folder and in every folder
# a scanned file imports (qs.a.b or a quoted path), and so on down. Script
# imports and qmldir files are never watched, and neither are files that
# appear after the scan, so writing those reloads nothing.
qs_watched_files() {
  local root_file="$1" root_dir="${1%/*}" f d line imp name
  local -A seen_files=() seen_dirs=()
  local -a files=("$root_file") dirs=() imports=()
  [[ -f "$root_file" ]] || return 0
  while (( ${#files[@]} + ${#dirs[@]} )); do
    while (( ${#files[@]} )); do
      f="${files[-1]}"
      unset 'files[-1]'
      [[ -z "${seen_files[$f]:-}" ]] || continue
      seen_files[$f]=1
      printf '%s\n' "$f"
      [[ -r "$f" ]] || continue
      d="${f%/*}"
      dirs+=("$d")
      imports=()
      # Only the header is read for imports, up to the first line that opens
      # a block.
      while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ "$line" == import* ]]; then
          if [[ "$line" == *" qs."* ]]; then
            imp="${line#*" qs."}"
            imp="${imp%% *}"
            if [[ "$imp" =~ ^[A-Za-z0-9_.]*$ ]]; then imports+=("${root_dir}/${imp//.//}"); fi
          elif [[ "$line" =~ \"([^\"]*)\" ]]; then
            imp="${BASH_REMATCH[1]}"
            if [[ "$imp" == root:* ]]; then
              imp="${imp#root:}"
              imports+=("${root_dir}/${imp#/}")
            else
              imports+=("${d}/${imp}")
            fi
          fi
        elif [[ "$line" == *"{"* ]]; then
          break
        fi
      done <"$f"
      for imp in ${imports[@]+"${imports[@]}"}; do
        [[ -d "$imp" ]] || continue
        if [[ "$imp" == *"/."* ]]; then imp=$(realpath -ms -- "$imp" 2>/dev/null) || continue; fi
        dirs+=("$imp")
      done
    done
    while (( ${#dirs[@]} )); do
      d="${dirs[-1]}"
      unset 'dirs[-1]'
      [[ -z "${seen_dirs[$d]:-}" ]] || continue
      seen_dirs[$d]=1
      for f in "$d"/*; do
        [[ -f "$f" ]] || continue
        name="${f##*/}"
        [[ "${name:0:1}" == [[:upper:]] ]] || continue
        case "$name" in
          *.qml) files+=("$f") ;;
          *.qml.json)
            if [[ -z "${seen_files[$f]:-}" ]]; then
              seen_files[$f]=1
              printf '%s\n' "$f"
            fi
            ;;
        esac
      done
    done
  done
}

# The one Settings window that restarts itself during an update is one from
# before 3.0.0, whose settings.qml never turns Quickshell's file watching off,
# running this update from its own Update page. The update is then that
# window's child, and the restart takes it down. So when this run descends
# from such a window, the files the window restarts on are left for after
# the update has ended, and finish-deferred.sh puts them in place then.
#
# What it waits for is the root helper the page started, or, if there is
# none, whatever the window started directly.
exp_detect_old_settings() {
  local settings="${HOME}/.config/quickshell/ii/settings.qml"
  local pid=$$ hops=0 found=0 below="" below_start="" helper="" helper_start="" arg exe ppid start f
  local -a argv
  EXP_DEFER=0
  [[ -f "$settings" ]] || return 0
  grep -q 'Quickshell.watchFiles = false' "$settings" 2>/dev/null && return 0
  while (( pid > 1 && hops++ < 64 )); do
    _exp_proc_stat "$pid" || break
    ppid="$_exp_ppid" start="$_exp_start"
    argv=()
    mapfile -d '' -t argv 2>/dev/null <"/proc/${pid}/cmdline" || argv=()
    exe="${argv[0]:-}"
    exe="${exe##*/}"
    if [[ "$exe" == qs || "$exe" == quickshell ]]; then
      for arg in "${argv[@]}"; do
        while [[ "$arg" == *//* ]]; do arg="${arg//\/\//\/}"; done
        if [[ "$arg" == "$settings" ]]; then
          found=1
          break
        fi
      done
      (( found )) && break
    fi
    if [[ -z "$helper" && "$exe" != sudo ]]; then
      for arg in "${argv[@]:0:2}"; do
        if [[ "$arg" == mainstream-update-helper || "$arg" == */mainstream-update-helper ]]; then
          helper="$pid" helper_start="$start"
          break
        fi
      done
    fi
    below="$pid" below_start="$start"
    pid="$ppid"
  done
  (( found )) || return 0
  if [[ -n "$helper" ]]; then
    EXP_DEFER_WAIT_PID="$helper" EXP_DEFER_WAIT_START="$helper_start"
  else
    EXP_DEFER_WAIT_PID="$below" EXP_DEFER_WAIT_START="$below_start"
  fi
  [[ -n "$EXP_DEFER_WAIT_PID" && -n "$EXP_DEFER_WAIT_START" ]] || return 0
  while IFS= read -r f; do
    EXP_WATCHED["$f"]=1
  done < <(qs_watched_files "$settings")
  EXP_DEFER=1
}

# The blob of every shipped path in the releases the update starts from,
# which is what exp_home_is_stock compares a home copy with. The spec is a
# comma-separated list of revisions, where "tags" stands for every release
# tag behind HEAD.
exp_base_load() {
  local spec="${1:-}" rev entry meta path
  local -a revs=()
  [[ -n "$spec" && "$spec" != - ]] || return 0
  for rev in ${spec//,/ }; do
    if [[ "$rev" == tags ]]; then
      while IFS= read -r entry; do
        if [[ "$entry" =~ ^[0-9]{1,2}\.[0-9]+\.[0-9]+$ ]]; then revs+=("refs/tags/${entry}"); fi
      done < <(git -C "$REPO_ROOT" tag --merged HEAD --no-contains HEAD 2>/dev/null)
    else
      revs+=("$rev")
    fi
  done
  for rev in ${revs[@]+"${revs[@]}"}; do
    [[ -z "${EXP_BASE_LOADED[$rev]:-}" ]] || continue
    EXP_BASE_LOADED[$rev]=1
    while IFS= read -r -d '' entry; do
      meta="${entry%%$'\t'*}"
      path="${entry#*$'\t'}"
      EXP_BASE_BLOBS[$path]+=" ${meta##* }"
    done < <(git -C "$REPO_ROOT" ls-tree -r -z --full-tree "$rev" -- dots .config .local 2>/dev/null)
  done
  return 0
}

# Where this update starts from. EXP_RANGE_BASE is the one earlier commit the
# changed files are read against, when there is one to trust; a forced run
# also counts a file as untouched when any earlier release shipped it as is.
exp_base_init() {
  local head prev
  EXP_BASE_SPEC="" EXP_RANGE_BASE=""
  head=$(git -C "$REPO_ROOT" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) || return 0
  prev=$(git -C "$REPO_ROOT" rev-parse -q --verify 'HEAD@{1}^{commit}' 2>/dev/null) || prev=""
  if [[ -n "$prev" && "$prev" != "$head" ]]; then
    if [[ "$FORCE_CHECK" != true ]] || git -C "$REPO_ROOT" merge-base --is-ancestor "$prev" "$head" 2>/dev/null; then
      EXP_RANGE_BASE="$prev"
    fi
  fi
  if [[ "$FORCE_CHECK" == true ]]; then
    EXP_BASE_SPEC="tags${EXP_RANGE_BASE:+,${EXP_RANGE_BASE}}"
  else
    EXP_BASE_SPEC="$EXP_RANGE_BASE"
  fi
  exp_base_load "$EXP_BASE_SPEC"
}

# The home path a path in the clone is installed to.
exp_home_path_for() {
  if [[ "$1" == dots/* ]]; then
    printf '%s/%s' "$HOME" "${1#dots/}"
  else
    printf '%s/%s' "$HOME" "$1"
  fi
}

# The list in .update-deferred has one line per file: M to put the release's
# copy in place or D to remove the home one, the releases the home copy is
# compared with (exp_base_load), and the path in the clone. A path listed by
# an earlier run keeps its line, since its home copy is still from then.
exp_defer_load() {
  local op base rel
  EXP_DEFERRED_SEEN=()
  [[ -f "$EXP_DEFERRED_FILE" ]] || return 0
  while IFS=$'\t' read -r op base rel || [[ -n "${rel:-}" ]]; do
    if [[ -n "${rel:-}" ]]; then EXP_DEFERRED_SEEN[$rel]=1; fi
  done <"$EXP_DEFERRED_FILE"
  return 0
}

exp_defer_add() {
  local op="$1" rel="$2"
  [[ -z "${EXP_DEFERRED_SEEN[$rel]:-}" ]] || return 0
  EXP_DEFERRED_SEEN[$rel]=1
  [[ "$DRY_RUN" == true ]] && return 0
  printf '%s\t%s\t%s\n' "$op" "${EXP_BASE_SPEC:--}" "$rel" >>"$EXP_DEFERRED_FILE"
}

# Whether a file waits for the end of the update: this run is under a
# Settings window that restarts on it (exp_detect_old_settings), and the
# unattended choice for it writes the file.
exp_should_defer() {
  local repo_file="$1" home_file="$2" rel
  (( EXP_DEFER )) || return 1
  [[ -n "${EXP_WATCHED[$home_file]:-}" && -f "$home_file" ]] || return 1
  [[ "$NON_INTERACTIVE" == true ]] || return 1
  [[ "${DEFAULT_CHOICE:-}" == 1 || "${DEFAULT_CHOICE:-}" == 8 ]] || return 1
  cmp -s "$repo_file" "$home_file" && return 1
  rel="${repo_file#"$REPO_ROOT"/}"
  exp_defer_add M "$rel"
  if [[ "$DEFAULT_CHOICE" == 8 ]] && ! exp_home_is_stock "$home_file" "$rel"; then
    EXP_OWN_DEFERRED+=("$home_file")
  fi
  files_deferred=$((files_deferred + 1))
  return 0
}

# Puts every staged file in place in one go, so a Settings window that
# restarts on the first of them reads a finished set. The files at the top of
# the tree, which a restart starts from, go last: a restart that begins early
# still reads the old ones and runs again when they change.
exp_commit_staged() {
  local -a first=() last=()
  local i dest top="${HOME}/.config/quickshell/ii"
  (( ${#EXP_STAGE[@]} )) || return 0
  for (( i = 0; i + 1 < ${#EXP_STAGE[@]}; i += 2 )); do
    dest="${EXP_STAGE[i+1]}"
    if [[ "${dest%/*}" == "$top" ]]; then
      last+=("${EXP_STAGE[i]}" "$dest")
    else
      first+=("${EXP_STAGE[i]}" "$dest")
    fi
  done
  EXP_STAGE=()
  set -- ${first[@]+"${first[@]}"} ${last[@]+"${last[@]}"}
  if command -v python3 >/dev/null 2>&1 \
     && python3 -c 'import os, sys
a = sys.argv[1:]
for i in range(0, len(a) - 1, 2):
    os.replace(a[i], a[i + 1])' "$@" 2>/dev/null; then
    return 0
  fi
  # Whatever python3 did not get to is still staged.
  while (( $# >= 2 )); do
    if [[ -e "$1" ]]; then mv -f "$1" "$2" || rm -f "$1"; fi
    shift 2
  done
  return 0
}

exp_discard_staged() {
  local i
  for (( i = 0; i < ${#EXP_STAGE[@]}; i += 2 )); do
    rm -f "${EXP_STAGE[i]}" 2>/dev/null
  done
  if [[ -n "${_exp_inflight_tmp:-}" ]]; then
    rm -f "$_exp_inflight_tmp" 2>/dev/null
    _exp_inflight_tmp=""
  fi
  EXP_STAGE=()
  EXP_STAGING=0
  return 0
}

# One file of the release onto its home copy: created when it is missing, and
# settled through handle_file_conflict when the two differ.
apply_repo_file() {
  local repo_file="$1" home_file="$2" label="${3:-$2}"
  ensure_directory "$(dirname "$home_file")" || return 0
  if [[ -f "$home_file" ]]; then
    cmp -s "$repo_file" "$home_file" && return 0
    # Clear progress line if showing
    if [[ "$VERBOSE" == false ]] && command -v tput &>/dev/null 2>&1 && [[ ${total_files:-0} -gt 0 ]]; then
      printf "\r%*s\r" "80" "" >&2
    fi
    log_info "Found difference in: $label"
    if [[ "$DRY_RUN" == true ]]; then
      log_warning "[DRY-RUN] Conflict detected (would prompt): $home_file"
    else
      handle_file_conflict "$repo_file" "$home_file"
      exp_relogin_check "$home_file"
    fi
    files_updated=$(( ${files_updated:-0} + 1 ))
  else
    if [[ "$DRY_RUN" == true ]]; then
      if [[ "$VERBOSE" == true ]]; then
        log_info "[DRY-RUN] Would create new file: $home_file"
      fi
    else
      _install_repo_file "$repo_file" "$home_file"
      exp_relogin_check "$home_file"
      if [[ "$VERBOSE" == true ]]; then
        log_success "Created new file: $home_file"
      fi
    fi
    files_created=$(( ${files_created:-0} + 1 ))
  fi
  return 0
}

# A file the release no longer ships goes when it is still exactly what an
# earlier release put there. One with changes of the user's own stays theirs.
exp_remove_release_file() {
  local home_file="$1" repo_rel="$2"
  [[ -f "$home_file" && ! -L "$home_file" ]] || return 0
  if ! exp_home_is_stock "$home_file" "$repo_rel"; then
    log_info "Kept $home_file: the release no longer ships it, and it has changes of your own"
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would remove $home_file, which the release no longer ships"
    return 0
  fi
  if rm -f "$home_file"; then
    log_info "Removed $home_file, which the release no longer ships"
    exp_relogin_check "$home_file"
  fi
  return 0
}

# Files deleted or moved away between the two releases, which the copy never
# visits since it only looks at what the new release has.
exp_remove_deleted_files() {
  local status old new home dir mapped
  [[ -n "$EXP_RANGE_BASE" ]] || return 0
  while IFS= read -r -d '' status; do
    IFS= read -r -d '' old || break
    if [[ "$status" == R* ]]; then
      IFS= read -r -d '' new || break
    fi
    mapped=0
    for dir in "${MONITOR_DIRS[@]}"; do
      if [[ "$old" == "$dir"/* ]]; then
        mapped=1
        break
      fi
    done
    (( mapped )) || continue
    home=$(exp_home_path_for "$old")
    should_ignore "$home" && continue
    if (( EXP_DEFER )) && [[ -n "${EXP_WATCHED[$home]:-}" && -f "$home" ]]; then
      exp_defer_add D "$old"
      continue
    fi
    exp_remove_release_file "$home" "$old"
  done < <(git -C "$REPO_ROOT" diff -z --name-status -M --diff-filter=DR "$EXP_RANGE_BASE" HEAD -- "${MONITOR_DIRS[@]}" 2>/dev/null)
  return 0
}

# Puts the files a run left for later in place, all at once. Called by
# finish-deferred.sh once the update that left them has ended, and by the
# next run or the next login when that never happened.
exp_apply_deferred() {
  local line op base rel home repo_file n=0
  local -a entries=()
  [[ -f "$EXP_DEFERRED_FILE" ]] || return 0
  [[ "$DRY_RUN" == true ]] && return 0
  mapfile -t entries <"$EXP_DEFERRED_FILE"
  for line in ${entries[@]+"${entries[@]}"}; do
    IFS=$'\t' read -r op base rel <<<"$line"
    exp_base_load "$base"
  done
  EXP_STAGE=()
  EXP_STAGING=1
  for line in ${entries[@]+"${entries[@]}"}; do
    IFS=$'\t' read -r op base rel <<<"$line"
    [[ -n "${rel:-}" ]] || continue
    home=$(exp_home_path_for "$rel")
    should_ignore "$home" && continue
    case "$op" in
      M)
        repo_file="${REPO_ROOT}/${rel}"
        [[ -f "$repo_file" ]] || continue
        apply_repo_file "$repo_file" "$home" "$rel"
        ;;
      D)
        # Shipped again by a later release, whose copy step has it.
        [[ -e "${REPO_ROOT}/${rel}" ]] && continue
        exp_remove_release_file "$home" "$rel"
        ;;
      *) continue ;;
    esac
    n=$((n + 1))
  done
  EXP_STAGING=0
  exp_commit_staged
  rm -f "$EXP_DEFERRED_FILE"
  EXP_DEFERRED_SEEN=()
  if (( n )); then
    log_success "Put in place ${n} file(s) the update had left for after it finished"
  fi
  return 0
}

# Starts finish-deferred.sh outside this update's process tree, so it
# outlives the Settings window and all under it, and waits there for the
# update to end.
exp_launch_finisher() {
  local script="${REPO_ROOT}/sdata/subcmd-exp-update/finish-deferred.sh" bash_bin v
  local -a args=(--wait-pid "$EXP_DEFER_WAIT_PID" --wait-start "$EXP_DEFER_WAIT_START") env=()
  [[ -f "$script" ]] || return 1
  bash_bin=$(command -v bash 2>/dev/null) || bash_bin=/usr/bin/bash
  for v in HOME PATH XDG_RUNTIME_DIR XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS; do
    if [[ -n "${!v:-}" ]]; then env+=("--setenv=${v}=${!v}"); fi
  done
  if command -v systemd-run >/dev/null 2>&1 \
     && systemd-run --user --collect --quiet --unit="mainstream-update-finish-$$" \
          ${env[@]+"${env[@]}"} "$bash_bin" "$script" "${args[@]}" </dev/null >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "${EXP_UPDATE_LOG%/*}" 2>/dev/null || true
  if command -v setsid >/dev/null 2>&1 \
     && setsid -f "$bash_bin" "$script" "${args[@]}" </dev/null >>"$EXP_UPDATE_LOG" 2>&1; then
    return 0
  fi
  return 1
}

# Changes that only take effect when a session starts. Each gets one line in
# the relogin note, which the Update page shows until the next login clears
# it (hypr/hyprland/execs.lua).
exp_note_relogin() {
  EXP_RELOGIN_REASONS["$1"]=1
}

exp_relogin_check() {
  case "${1#"$HOME"/}" in
    .config/hypr/hyprland/env.lua|.config/environment.d/*)
      exp_note_relogin "The session environment changed" ;;
    .config/hypr/hyprland/execs.lua|.config/autostart/*)
      exp_note_relogin "The programs that start with the session changed" ;;
    .config/systemd/user/*)
      exp_note_relogin "Background services changed" ;;
    .config/xdg-desktop-portal/*)
      exp_note_relogin "Desktop portal settings changed" ;;
  esac
  return 0
}

exp_write_relogin_note() {
  local reason line tmp
  (( ${#EXP_RELOGIN_REASONS[@]} )) || return 0
  [[ "$DRY_RUN" == true ]] && return 0
  mkdir -p "${EXP_RELOGIN_FILE%/*}" 2>/dev/null || return 0
  if [[ -f "$EXP_RELOGIN_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ -n "$line" ]]; then EXP_RELOGIN_REASONS["$line"]=1; fi
    done <"$EXP_RELOGIN_FILE"
  fi
  tmp=$(mktemp "${EXP_RELOGIN_FILE}.XXXXXX" 2>/dev/null) || return 0
  for reason in "${!EXP_RELOGIN_REASONS[@]}"; do
    printf '%s\n' "$reason"
  done | sort >"$tmp"
  mv -f "$tmp" "$EXP_RELOGIN_FILE" 2>/dev/null || rm -f "$tmp"
  return 0
}

# The shell's Python packages live in a venv the installer builds from
# sdata/uv/requirements.txt. When a release changes that list, the venv is
# brought in line the same way, so a package the release swapped or dropped
# goes too. The list the venv was last brought to is kept beside it, so a
# sync that failed (no network, say) is tried again by the next update.
exp_sync_venv() {
  local venv="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/.venv"
  local req="${REPO_ROOT}/sdata/uv/requirements.txt" stamp old=""
  [[ "$DRY_RUN" != true && -f "$req" && -x "${venv}/bin/python" ]] || return 0
  declare -F sync_venv_requirements >/dev/null 2>&1 || return 0
  stamp="${venv}/.mainstream-requirements.txt"
  if [[ -f "$stamp" ]]; then
    cmp -s "$stamp" "$req" && return 0
    old="$stamp"
  elif [[ -n "$EXP_RANGE_BASE" ]] \
       && ! git -C "$REPO_ROOT" diff --quiet "$EXP_RANGE_BASE" HEAD -- sdata/uv/requirements.txt 2>/dev/null; then
    git -C "$REPO_ROOT" show "${EXP_RANGE_BASE}:sdata/uv/requirements.txt" >"$stamp" 2>/dev/null || : >"$stamp"
    old="$stamp"
  else
    return 0
  fi
  log_header "Updating Python Packages"
  if sync_venv_requirements "$venv" "$req" "$old"; then
    cp -f "$req" "$stamp" 2>/dev/null || true
    log_success "The shell's Python packages match this release"
  else
    log_warning "Could not update the shell's Python packages; the next update tries again"
  fi
  return 0
}

# One plain list of the files with changes of the user's own that the update
# replaced, and where each of their versions went.
exp_print_own_changes() {
  local entry home backup tilde='~'
  (( ${#EXP_OWN_REPLACED[@]} + ${#EXP_OWN_DEFERRED[@]} )) || return 0
  echo
  log_warning "These files had changes of your own, and the update replaced them. Your versions are kept here:"
  for entry in ${EXP_OWN_REPLACED[@]+"${EXP_OWN_REPLACED[@]}"}; do
    home="${entry%%$'\t'*}"
    backup="${entry#*$'\t'}"
    echo "  ${home/#"$HOME"/$tilde} -> ${backup/#"$HOME"/$tilde}"
  done
  for home in ${EXP_OWN_DEFERRED[@]+"${EXP_OWN_DEFERRED[@]}"}; do
    echo "  ${home/#"$HOME"/$tilde} -> ${REPO_ROOT/#"$HOME"/$tilde}/.update-backups/ (once the update has finished)"
  done
  return 0
}

# Hyprland watches its config and reloads on every write. The files below are
# replaced one at a time, so without this it reloads part-way through and reads
# a tree that is half old and half new, which is what puts a screen of config
# errors in front of someone who has done nothing wrong. Each of those reloads
# also re-runs plugins.lua, which is its own trouble.
#
# Restored by the trap whatever happens next: leaving it off would quietly stop
# every later config change from taking effect, which is far worse than the
# errors this avoids.
_hypr_live() { command -v hyprctl >/dev/null 2>&1 && hyprctl -j version >/dev/null 2>&1; }
_hypr_autoreload_is() {
  hyprctl -j getoption misc:disable_autoreload 2>/dev/null | grep -Eq '"bool": *'"$1"'([^a-z]|$)'
}
# hyprctl keyword only reaches a hyprland.conf; on the Lua config (Hyprland
# 0.55 and later) it is refused with "Use eval". The value goes through
# hl.config, with keyword kept for a machine still on the old config, and is
# read back to say whether it took.
_hypr_set_disable_autoreload() {
  hyprctl eval "hl.config({ misc = { disable_autoreload = $1 } })" >/dev/null 2>&1 || true
  _hypr_autoreload_is "$1" && return 0
  hyprctl keyword misc:disable_autoreload "$1" >/dev/null 2>&1 || true
  _hypr_autoreload_is "$1"
}

# The same problem, one layer up: these files are what the running shell is
# built from. Reloading part-way through brings back panels assembled from a
# half-old tree, and the controls that would put it right are the ones that
# broke, so the way out is a terminal or the power button.
_qs_live() { command -v qs >/dev/null 2>&1 && qs -c ii ipc show >/dev/null 2>&1; }
_qs_held=0
resume_qs_reload() {
  [[ "$_qs_held" -eq 0 ]] && return 0
  _qs_held=0
  qs -c ii ipc call updates resumeReload >/dev/null 2>&1 || true
}
_hypr_autoreload_restored=0
restore_hypr_autoreload() {
  [[ "$_hypr_autoreload_restored" -eq 1 ]] && return 0
  _hypr_autoreload_restored=1
  _hypr_live || return 0
  _hypr_set_disable_autoreload false >/dev/null 2>&1 || true
}

# Lets the shell reload onto the new files. When files were left for after
# the update, the shell stays held until they are in, and releasing it is the
# finisher's job; releasing it here would build it from a half-new tree.
exp_release_shell() {
  (( _exp_shell_released )) && return 0
  _exp_shell_released=1
  if (( EXP_DEFER )) && [[ -s "$EXP_DEFERRED_FILE" && "$DRY_RUN" != true ]]; then
    if exp_launch_finisher; then
      log_info "The files this Settings window is built from go in once the update has finished, and the desktop reloads then"
    else
      log_warning "Could not start the step that finishes the update; the remaining files go in at the next login"
      exp_note_relogin "Some files of the update go in at the next login"
      exp_write_relogin_note
    fi
    return 0
  fi
  resume_qs_reload
}

# Everything the run took is given back here whatever ends it. A broken pipe
# is ignored first, since the reader may already be gone and a write that
# ended the handler would skip what follows. errexit is off in here, since
# handing on a failing code with it on ends the handler right there, before
# the lock is removed. A second signal is caught and dropped so it cannot cut
# the handler short either; it still stops the command it lands on.
#
# The Decorations pass comes first, so a run stopped after general.lua was
# replaced still puts the user's values back. It runs while autoreload is
# still held, so its write does not set off a reload of a tree the copy left
# half done. The exit code is carried across so the failure notice still says
# what happened.
_exp_exit_handler() {
  trap '' PIPE
  local rc="${1:-0}"
  set +e
  trap : INT TERM HUP
  exp_discard_staged
  if (( _exp_holds_taken )); then
    deco_carry_finish
    restore_hypr_autoreload
    exp_release_shell
  fi
  # A run stopped after env.lua was replaced still needs the login.
  exp_write_relogin_note
  (exit "$rc")
  cleanup_on_exit
  exp_update_close_log
}

_pkg_build_tmp=""

# Cleanup function for signal handling
cleanup_on_exit() {
  local exit_code=$?
  
  # Remove lock file, when it is this run's: one that refused to start because
  # another update holds it leaves that update's lock alone.
  if [[ "$(cat "${REPO_ROOT}/.update-lock" 2>/dev/null)" == "$$" ]]; then
    rm -f "${REPO_ROOT}/.update-lock" 2>/dev/null || true
  fi
  if [[ -n "${_pkg_build_tmp:-}" ]]; then
    rm -rf "$_pkg_build_tmp" 2>/dev/null || true
  fi
  
  if [[ $exit_code -ne 0 ]] && [[ "$DRY_RUN" != true ]]; then
    echo
    log_warning "Update interrupted or failed (exit code: $exit_code)"
    log_info "System may be in an inconsistent state"
    log_info "Run the update again to complete the process"
  fi
}

# Set up signal handling and lock file
if [[ "${SOURCE_ONLY:-false}" != true ]]; then
exp_update_start_log
trap '_exp_exit_handler "$?"' EXIT
# A signal has to end the run. A handler that returns only stops the command
# it landed on, and the update carries on from the next one: a pull that was
# stopped reads as a failed pull and the files are copied anyway, and a Stop
# during the copy goes on replacing files after the notice said it stopped.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

exp_protect_clone_state || true

# Check for concurrent runs
if [[ -f "${REPO_ROOT}/.update-lock" ]]; then
  # Check if the process is still running
  if exp_lock_owner_live "$(cat "${REPO_ROOT}/.update-lock" 2>/dev/null)"; then
    log_die "Another update is already running (PID: $(cat "${REPO_ROOT}/.update-lock"))"
  else
    log_warning "Found stale lock file, removing..."
    rm -f "${REPO_ROOT}/.update-lock"
  fi
fi

# Create lock file with current PID
if [[ "$DRY_RUN" != true ]]; then
  echo $$ > "${REPO_ROOT}/.update-lock"
fi

# Main script starts here
log_header "Dotfiles Update Script"

if [[ "$SKIP_NOTICE" == false ]]; then
  log_warning "THIS SCRIPT IS NOT FULLY TESTED AND MAY CAUSE ISSUES!"
  log_warning "It might be safer if you want to preserve your modifications and not delete added files,"
  log_warning "  but this can cause partial updates and therefore unexpected behavior like in #1856."
  log_warning "In general, prefer \"./setup install\" for updates if available."
  safe_read "Continue? (y/N): " response "N"

  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    log_error "Update aborted by user"
    exit 1
  fi
fi

# Check if we're in a git repository
cd "$REPO_ROOT" || log_die "Failed to change to repository directory"

if git rev-parse --is-inside-work-tree &>/dev/null; then
  log_info "Running in git repository: $(git rev-parse --show-toplevel)"
else
  log_error "Not in a git repository. Please run this script from your dotfiles repository."
  exit 1
fi

# Auto-detect repository structure
log_header "Detecting Repository Structure"
if detected_dirs=$(detect_repo_structure); then
  read -ra MONITOR_DIRS <<<"$detected_dirs"
  log_success "Detected repository structure:"
  for dir in "${MONITOR_DIRS[@]}"; do
    if [[ -d "${REPO_ROOT}/${dir}" ]]; then
      log_info "  ✓ ${REPO_ROOT}/${dir}"
    else
      log_warning "  ✗ ${REPO_ROOT}/${dir} (not found, will skip)"
    fi
  done
else
  log_die "Failed to detect repository structure. Make sure you're in the correct directory."
fi

# Load ignore patterns once at startup (performance optimization)
load_ignore_patterns

# Step 1: Pull latest commits
log_header "Pulling Latest Changes"

if [[ "${DOTS_SKIP_PULL:-0}" == "1" ]]; then
  log_info "Repository pinned by caller (DOTS_SKIP_PULL=1): skipping pull"
else

current_branch=$(git branch --show-current)
if [[ -z "$current_branch" ]]; then
  log_warning "In detached HEAD state. Checking out main/master branch..."
  if git show-ref --verify --quiet refs/heads/main; then
    git checkout main
    current_branch="main"
  elif git show-ref --verify --quiet refs/heads/master; then
    git checkout master
    current_branch="master"
  else
    log_die "Could not find main or master branch"
  fi
fi

log_info "Current branch: $current_branch"

if ! git diff --quiet || ! git diff --cached --quiet; then
  log_warning "You have uncommitted changes:"
  git status --short
  echo

  if ! safe_read "Do you want to continue? This will stash your changes. (y/N): " response "N"; then
    echo
    log_error "Failed to read input. Aborting."
    exit 1
  fi

  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    log_die "Aborted by user"
  fi
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would stash changes"
  else
    git stash push -m "Auto-stash before update $(date)"
    log_info "Changes stashed"
  fi
fi

if git remote get-url origin &>/dev/null; then
  log_info "Pulling changes from origin/$current_branch..."
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would run: git pull --ff-only"
  else
    if git pull --ff-only; then
      log_success "Successfully pulled latest changes"
      git submodule update --init --recursive
      # Verify we actually got new commits
      if git rev-parse --verify HEAD@{1} &>/dev/null; then
        if [[ "$(git rev-parse HEAD)" == "$(git rev-parse HEAD@{1})" ]]; then
          log_info "Already up to date with remote"
        fi
      fi
    else
      log_warning "Failed to pull changes from remote."
      log_warning "This could be due to:"
      log_warning "  - Network issues"
      log_warning "  - Uncommitted local changes (use 'git stash' first)"
      log_warning "  - Diverged history (may need 'git pull --rebase')"
      log_info "Continuing with local repository state..."
    fi
  fi
else
  log_warning "No remote 'origin' configured. Skipping pull operation."
  log_info "This appears to be a local-only repository."
fi

fi

# Step 2: Handle package building
rebuilt_packages=0

if [[ "$CHECK_PACKAGES" == true ]]; then
  log_header "Package Management"

  # Check if required Arch Linux tools are available
  if ! command -v pacman &>/dev/null || ! command -v makepkg &>/dev/null; then
    log_warning "Arch Linux package management tools (pacman/makepkg) not found."
    log_warning "Skipping package management as this appears to be a non-Arch Linux system."
    log_warning "Use -p/--packages flag only on Arch Linux systems."
    PKG_TOOLS_AVAILABLE=false
  else
    PKG_TOOLS_AVAILABLE=true
  fi

  if [[ "$PKG_TOOLS_AVAILABLE" == true ]]; then
    if [[ ! -d "$ARCH_PACKAGES_DIR" ]]; then
      log_warning "No packages directory found (tried: dist-arch, arch-packages, sdata/dist-arch)."
      log_warning "Skipping package management."
    else
      # Scan for changed PKGBUILDs
      changed_pkgbuilds=()
      for pkg_dir in "$ARCH_PACKAGES_DIR"/*/; do
        pkg_dir="${pkg_dir%/}"
        if [[ -f "${pkg_dir}/PKGBUILD" ]]; then
          pkg_name=$(basename "$pkg_dir")
          if check_pkgbuild_changed "$pkg_dir"; then
            if pkgbuild_wants_build "$pkg_dir"; then
              changed_pkgbuilds+=("$pkg_name")
            elif [[ "$FORCE_CHECK" != true || "$VERBOSE" == true ]]; then
              log_info "Not building ${pkg_name}: it is not installed, or it is already at this version or newer from the repositories"
            fi
          fi
        fi
      done

      if [[ ${#changed_pkgbuilds[@]} -gt 0 ]]; then
        log_info "Found ${#changed_pkgbuilds[@]} package(s) with changed PKGBUILDs: ${changed_pkgbuilds[*]}"
        echo
        echo "Package build options:"
        echo "1) Build only packages with changed PKGBUILDs"
        echo "2) List all packages and select which to build"
        echo "3) Build all packages"
        echo "4) Skip package building"
        echo

        if [[ "$NON_INTERACTIVE" == true ]]; then
          pkg_choice="1"
          log_info "Non-interactive mode: Using default package option: $pkg_choice"
        elif safe_read "Choose an option (1-4): " pkg_choice "1"; then
          if [[ "$VERBOSE" == true ]]; then
            log_info "User selected package option: $pkg_choice"
          fi
        else
          log_warning "Failed to read input. Skipping package building."
          pkg_choice=""
        fi

        if [[ -n "$pkg_choice" ]]; then
          case $pkg_choice in
            1) build_packages "changed" ;;
            2)
              if list_packages; then
                build_packages "select"
              fi
              ;;
            3) build_packages "all" ;;
            4|*) log_info "Skipping package building" ;;
          esac
        fi
      else
        log_info "No PKGBUILDs have changed since last update."
        echo
        if [[ "$NON_INTERACTIVE" == true ]]; then
          check_anyway="N"
          log_info "Non-interactive mode: Using default for check packages anyway: $check_anyway"
        elif safe_read "Do you want to check and build packages anyway? (y/N): " check_anyway "N"; then
          if [[ "$VERBOSE" == true ]]; then
            log_info "User chose to check packages anyway: $check_anyway"
          fi
        else
          log_warning "Failed to read input. Skipping package management."
          check_anyway=""
        fi

        if [[ -n "$check_anyway" && "$check_anyway" =~ ^[Yy]$ ]]; then
          if list_packages; then
            echo
            echo "Package build options:"
            echo "1) Select specific packages to build"
            echo "2) Build all packages"
            echo "3) Skip package building"

            if safe_read "Choose an option (1-3): " build_choice "3"; then
              case $build_choice in
                1) build_packages "select" ;;
                2) build_packages "all" ;;
                3|*) log_info "Skipping package building" ;;
              esac
            else
              log_info "Skipping package building"
            fi
          fi
        else
          log_info "Skipping package management"
        fi
      fi
    fi
  fi
else
  log_header "Package Management"
  log_info "Package checking disabled. Use -p or --packages flag to enable package management."
fi

# Step 3: Update configuration files
# Repairs to the machine's own files, before anything is compared against the
# repository. These used to run only on the install path, so the people who
# update, who are the ones carrying the old state, never got them.
if [[ -r "${REPO_ROOT}/sdata/lib/migrations.sh" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/sdata/lib/migrations.sh"
  migrate_custom_general_plugin_block "${REPO_ROOT}"
fi

# A run that was killed outright cannot have released anything, and both holds
# outlive the script that took them. Clearing first costs nothing when there is
# nothing to clear, and spares the next person a session where their settings
# quietly stop applying. The shell is left held when an earlier run left files
# for later, since releasing it would build it from the half-new tree before
# this run puts them in.
if _hypr_live; then _hypr_set_disable_autoreload false >/dev/null 2>&1 || true; fi
if _qs_live && [[ ! -s "$EXP_DEFERRED_FILE" ]]; then qs -c ii ipc call updates resumeReload >/dev/null 2>&1 || true; fi

# From here on the exit handler gives back what is taken below.
_exp_holds_taken=1
if _hypr_live && ! _hypr_set_disable_autoreload true; then
  log_warning "Hyprland's autoreload could not be held off, so it may reload while the files are copied"
fi
if _qs_live && qs -c ii ipc call updates holdReload >/dev/null 2>&1; then
  _qs_held=1
  log_info "Shell reloading held until the new files are all in place"
fi

log_header "Updating Configuration Files"

process_files=false
if [[ "$FORCE_CHECK" == true ]]; then
  process_files=true
  log_info "Force mode: checking all configuration files"
elif has_new_commits; then
  process_files=true
  log_info "New commits detected: checking changed configuration files"
else
  log_info "No new commits found and force mode not enabled: skipping file updates"
  process_files=false
fi

exp_base_init || true
exp_defer_load || true
if [[ "$process_files" == true || -s "$EXP_DEFERRED_FILE" ]]; then
  exp_detect_old_settings || true
fi
if (( EXP_DEFER )); then
  log_info "This update runs from a Settings window of an earlier release, which restarts when the files it is built from change and would stop the update. Those files go in once the update has finished."
elif [[ -s "$EXP_DEFERRED_FILE" ]]; then
  log_info "Putting in place the files an earlier update left for after it finished"
  exp_apply_deferred || true
fi

if [[ "$process_files" == true ]]; then
  files_processed=0
  files_updated=0
  files_created=0
  
  deco_carry_begin || true

  # Count total files for progress indication (optional). The count only
  # feeds a line redrawn in place, which a pipe cannot show.
  total_files=0
  if [[ "$VERBOSE" == false ]] && [[ -t 2 ]] && command -v tput &>/dev/null 2>&1; then
    for dir_name in "${MONITOR_DIRS[@]}"; do
      repo_dir_path="${REPO_ROOT}/${dir_name}"
      [[ ! -d "$repo_dir_path" ]] && continue
      total_files=$((total_files + $(find "$repo_dir_path" -type f 2>/dev/null | wc -l)))
    done
  fi

  for dir_name in "${MONITOR_DIRS[@]}"; do
    repo_dir_path="${REPO_ROOT}/${dir_name}"
    
    if [[ ! -d "$repo_dir_path" ]]; then
      if [[ "$VERBOSE" == true ]]; then
        log_warning "Skipping non-existent directory: $repo_dir_path"
      fi
      continue
    fi
    
    # FIX: Properly handle dots/ prefix mapping
    if [[ "$dir_name" == dots/* ]]; then
      # Strip "dots/" prefix for home directory mapping
      home_subdir="${dir_name#dots/}"
      home_dir_path="${HOME}/${home_subdir}"
    else
      # Direct structure
      home_dir_path="${HOME}/${dir_name}"
    fi

    log_info "Processing directory: $dir_name → ${home_dir_path}"

    ensure_directory "$home_dir_path" || continue

    while IFS= read -r -d '' -u 9 repo_file; do
      # Calculate relative path from the repo source directory
      rel_path="${repo_file#$repo_dir_path/}"
      home_file="${home_dir_path}/${rel_path}"

      if should_ignore "$home_file"; then
        if [[ "$VERBOSE" == true ]]; then
          log_info "Ignored: $rel_path (matches ignore pattern)"
        fi
        continue
      fi

      if [[ "$VERBOSE" == true ]]; then
        log_info "Processing: $rel_path"
      fi

      ((files_processed++))
      
      # Show progress for non-verbose mode
      if [[ "$VERBOSE" == false ]] && command -v tput &>/dev/null 2>&1 && [[ $total_files -gt 0 ]]; then
        printf "\r[INFO] Processing files: %d/%d" "$files_processed" "$total_files" >&2
      fi

      exp_should_defer "$repo_file" "$home_file" && continue
      apply_repo_file "$repo_file" "$home_file" "$rel_path"
    done 9< <(order_additions_first "$repo_dir_path" "$home_dir_path") || true
    echo
  done

  # Clear progress line if it was shown
  if [[ "$VERBOSE" == false ]] && command -v tput &>/dev/null 2>&1 && [[ $total_files -gt 0 ]]; then
    printf "\r%*s\r" "80" "" >&2
  fi

  exp_remove_deleted_files || true

  # Before the reload below, so Hyprland reads the settings once, already right.
  deco_carry_finish || true

  echo
  log_info "File processing summary:"
  log_info "- Files processed: $files_processed"
  log_info "- Files with conflicts: $files_updated"
  log_info "- New files created: $files_created"
  if (( files_deferred )); then
    log_info "- Files left for after the update: $files_deferred"
  fi
else
  log_info "Skipping file updates (no changes detected and not in force mode)"
fi

# Settings a release renamed or reshaped in config.json, once the files that
# read them are in. A run that left files for later has this repeated by the
# finisher, after the rest go in.
if [[ "$DRY_RUN" != true ]] && declare -F config_migrations_run >/dev/null 2>&1; then
  config_migrations_run "${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json" || true
fi

# Step 4: Update script permissions
# The tree is consistent again, so hand Hyprland one reload of the finished
# thing rather than the several it would have taken along the way.
if _hypr_live && [[ "$_hypr_autoreload_restored" -eq 0 ]]; then
  restore_hypr_autoreload
  hyprctl reload >/dev/null 2>&1 || true
fi
exp_release_shell

log_header "Updating Script Permissions"

if [[ -d "${HOME}/.local/bin" ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would update script permissions in ~/.local/bin"
  else
    find "${HOME}/.local/bin" -type f -exec chmod +x {} \; 2>/dev/null || true
    log_success "Updated ~/.local/bin script permissions"
  fi
fi

exp_sync_venv || true

log_header "Update Complete"
if [[ "$DRY_RUN" == true ]]; then
  log_warning "DRY-RUN MODE: No changes were actually made"
  log_info "Run without -n/--dry-run to apply changes"
else
  log_success "Dotfiles update completed successfully!"
fi

echo
echo -e "${STY_CYAN}Summary:${STY_RST}"
if command -v git >/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
  echo "- Repository: $(git log -1 --pretty=format:'%h - %s (%cr)' 2>/dev/null || echo 'Unknown')"
else
  echo "- Repository: Unknown (git not available)"
fi
echo "- Branch: ${current_branch:-Unknown}"
echo "- Structure: ${MONITOR_DIRS[*]}"
echo "- Mode: $([ "$FORCE_CHECK" == true ] && echo "Force check" || echo "Normal")"
echo "- Package checking: $([ "$CHECK_PACKAGES" == true ] && echo "Enabled" || echo "Disabled")"

if [[ $rebuilt_packages -gt 0 ]]; then
  echo "- Packages rebuilt: $rebuilt_packages"
fi

if [[ "$process_files" == true ]]; then
  echo "- Files processed: $files_processed"
  echo "- Files updated/conflicted: $files_updated"
  echo "- New files created: $files_created"
fi

exp_print_own_changes || true

exp_write_relogin_note || true
if (( ${#EXP_RELOGIN_REASONS[@]} )) && [[ "$DRY_RUN" != true ]]; then
  echo
  log_info "Log out and back in to finish updating: $(printf '%s\n' "${!EXP_RELOGIN_REASONS[@]}" | sort | paste -sd ';' - | sed 's/;/; /g')"
fi

if [[ ! -f "$XDG_UPDATE_IGNORE_FILE" && ! -f "$UPDATE_IGNORE_FILE" ]]; then
  echo
  log_info "Tip: Create ignore files to exclude files from updates:"
  echo "  - Repository ignore: ${REPO_ROOT}/.updateignore"
  echo "  - User ignore: ${XDG_UPDATE_IGNORE_FILE}"
  echo
  echo "Example patterns:"
  echo "  *.log                 # Ignore all .log files"
  echo "  .config/personal/     # Ignore entire directory"
  echo "  secret-config.conf    # Ignore specific file"
  echo "  /temp-file            # Ignore from root only"
  echo "  **secret**            # Ignore files containing 'secret'"
fi

# Show backup directory if any backups were created
if [[ -d "${REPO_ROOT}/.update-backups" ]] && [[ "$DRY_RUN" != true ]]; then
  echo
  log_info "Backups stored in: ${REPO_ROOT}/.update-backups/"
fi

fi

echo
