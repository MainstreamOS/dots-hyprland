# shellcheck shell=bash

install_app_catalog() {
  local app id label
  local grouped=${1:-}
  local -a MAINSTREAM_DEFAULT_APPS=()
  source "$REPO_ROOT/sdata/dist-arch/mainstream-extras/default-apps.list"
  for app in "${MAINSTREAM_DEFAULT_APPS[@]}"; do
    IFS='|' read -r id label _ <<< "$app"
    printf '%s\t%s\tdefault' "$id" "$label"
    [[ $grouped != --groups ]] || printf '\tDefault apps'
    printf '\n'
  done
  # An item with "selected: true" is preselected like the default apps.
  awk -v grouped="$grouped" '
    function flush() {
      if (id != "" && label != "") {
        printf "%s\t%s\t%s", id, label, (preselected ? "default" : "optional")
        if (grouped == "--groups") printf "\t%s", group
        print ""
      }
      id = ""
    }
    /^    - name: "/ {
      flush()
      group = $0; sub(/^    - name: "[^[:alnum:]]*/, "", group); sub(/"$/, "", group)
    }
    /^          - name: / { flush(); id = $3; label = ""; preselected = 0 }
    /^            display: "/ { label = $0; sub(/^ +display: "/, "", label); sub(/"$/, "", label) }
    /^            selected: true/ { preselected = 1 }
    END { flush() }
  ' "$REPO_ROOT/sdata/subcmd-install/optional-apps.conf"
}

choose_install_apps() {
  local id label kind number input index mark
  local -a ids=() labels=() indexes=()
  local -A known=() selected=()
  while IFS=$'\t' read -r id label kind; do
    [[ ${known[$id]:-} ]] && continue
    known[$id]=1
    ids+=("$id")
    labels+=("$label")
    [[ $kind != default ]] || selected[$id]=1
  done < <(install_app_catalog)

  # --proton sets the Proton items; --apps sets the apps and leaves them alone.
  if [[ -n ${MS_INSTALL_PROTONS+x} ]]; then
    _install_choice_list MS_INSTALL_PROTONS --proton none "${INSTALL_PROTONS[@]}" || return
    for id in "${ids[@]}"; do
      [[ $id == proton:* ]] && unset 'selected[$id]'
    done
    for id in $MS_INSTALL_PROTONS; do
      selected[proton:$id]=1
    done
  fi
  if [[ ${MS_INSTALL_APPS_SET:-false} == true ]]; then
    for id in "${ids[@]}"; do
      [[ $id == *:* ]] || unset 'selected[$id]'
    done
    IFS=, read -ra indexes <<< "$MS_INSTALL_APPS"
    for id in "${indexes[@]}"; do
      if [[ $id == proton:* ]]; then
        printf 'Choose Proton with --proton, not --apps (%q).\n' "$id" >&2
        return 1
      fi
      if [[ -z $id || $id == *:* || ! ${known[$id]:-} ]]; then
        printf 'Unknown install app %q. Use --list-apps to see the choices.\n' "$id" >&2
        return 1
      fi
      selected[$id]=1
    done
  else
    if [[ ! -t 0 || ! -t 1 ]]; then
      printf 'Custom installs without a terminal require --apps <comma-separated IDs>.\n' >&2
      return 1
    fi
    while true; do
      printf '\nChoose apps to install. The recommended apps are already selected.\n'
      for index in "${!ids[@]}"; do
        id=${ids[index]}
        mark=' '
        [[ ! ${selected[$id]:-} ]] || mark=x
        printf ' %2d. [%s] %s\n' "$((index + 1))" "$mark" "${labels[index]}"
      done
      printf '\nEnter numbers to toggle, or press Enter to continue: '
      IFS= read -r input || return 1
      [[ -n $input ]] || break
      read -ra indexes <<< "$input"
      for number in "${indexes[@]}"; do
        if [[ ! $number =~ ^[1-9][0-9]?$ ]] || (( number > ${#ids[@]} )); then
          printf 'Invalid app number: %s\n' "$number" >&2
          continue
        fi
        id=${ids[number - 1]}
        if [[ ${selected[$id]:-} ]]; then unset 'selected[$id]'; else selected[$id]=1; fi
      done
    done
  fi

  # Choice items (names with ':') are never packages.
  MS_SELECTED_APPS=()
  MS_INSTALL_PROTONS=""
  for id in "${ids[@]}"; do
    [[ ${selected[$id]:-} ]] || continue
    case $id in
      proton:*) MS_INSTALL_PROTONS+="${MS_INSTALL_PROTONS:+ }${id#proton:}" ;;
      *:*) ;;
      *) MS_SELECTED_APPS+=("$id") ;;
    esac
  done
}

# Sets the variable $1 from the flag $2 or a numbered prompt headed $3. The
# remaining "value|label" pairs are the choices, and the first is preselected.
_choose_install_option() {
  local var=$1 flag=$2 heading=$3 pair choice index allowed
  shift 3
  local -a values=() labels=()
  for pair in "$@"; do
    values+=("${pair%%|*}")
    labels+=("${pair#*|}")
  done
  allowed=$(IFS='|'; printf '%s' "${values[*]}")
  if [[ -n ${!var:-} ]]; then
    for choice in "${values[@]}"; do
      [[ ${!var} != "$choice" ]] || return 0
    done
    printf 'Unknown %s value %q. Choose %s.\n' "$flag" "${!var}" "$allowed" >&2
    return 1
  fi
  # A scripted run installs its --apps exactly as listed unless it asks for a source.
  if [[ ! -t 0 || ! -t 1 ]]; then
    printf -v "$var" ''
    printf 'No terminal: apps install as listed; pass %s to swap them.\n' "$flag" >&2
    return 0
  fi
  printf '\n%s\n' "$heading"
  for index in "${!labels[@]}"; do
    printf '  %d. %s\n' "$((index + 1))" "${labels[index]}"
  done
  while true; do
    printf 'Choice [1]: '
    IFS= read -r choice || return 1
    [[ -n $choice ]] || choice=1
    if [[ $choice =~ ^[1-9]$ ]] && (( choice <= ${#values[@]} )); then
      printf -v "$var" '%s' "${values[choice - 1]}"
      return 0
    fi
    printf 'Choose a number from 1 to %d.\n' "${#values[@]}"
  done
}

choose_app_source() {
  _choose_install_option MS_INSTALL_APP_SOURCE --app-source 'Choose where apps come from' \
    'native|Native packages (recommended)' \
    'flatpak|Flatpak, for apps that have one'
}

# The values each list flag accepts, in the order the install prefers them.
INSTALL_KERNELS=(linux-mainstream-performance linux-mainstream linux)
INSTALL_PROTONS=(mainstream ge cachyos)

# Normalizes the comma list in $1 to the allowed values $4... in preference
# order, which picks the defaults; $3, if set, is the value meaning none.
_install_choice_list() {
  local var=$1 flag=$2 none=$3 item value known list=""
  shift 3
  local -a items=()
  if [[ -n $none && ${!var} == "$none" ]]; then
    printf -v "$var" ''
    return 0
  fi
  IFS=, read -ra items <<< "${!var}"
  (( ${#items[@]} )) || items=('')
  for item in "${items[@]}"; do
    known=false
    for value; do
      [[ $item != "$value" ]] || known=true
    done
    if ! $known; then
      printf 'Unknown %s value %q. Choose from %s%s.\n' "$flag" "$item" "$(IFS=,; printf '%s' "$*")" \
        "${none:+, or $none}" >&2
      return 1
    fi
  done
  for value; do
    [[ ",${!var}," != *",$value,"* ]] || list+="${list:+ }$value"
  done
  printf -v "$var" '%s' "$list"
}

choose_install_kernel() {
  local input number kernel
  local -a numbered=(linux-mainstream linux-mainstream-performance linux) picked=()
  if [[ -n ${MS_INSTALL_KERNELS+x} ]]; then
    _install_choice_list MS_INSTALL_KERNELS --kernel '' "${INSTALL_KERNELS[@]}" || return
  elif [[ ! -t 0 || ! -t 1 ]]; then
    MS_INSTALL_KERNELS=linux-mainstream
    printf 'No terminal: using --kernel linux-mainstream.\n' >&2
  else
    printf '\nChoose the kernels to install. Enter one or more numbers, such as "1 2".\n'
    printf '  1. Mainstream kernel (recommended)\n'
    printf '  2. Mainstream performance kernel (needs a CPU from about 2015 or newer)\n'
    printf "  3. Arch's linux kernel\n"
    while true; do
      printf 'Kernels [1]: '
      IFS= read -r input || return 1
      read -ra picked <<< "${input:-1}"
      MS_INSTALL_KERNELS=""
      for number in "${picked[@]}"; do
        if [[ ! $number =~ ^[1-3]$ ]]; then
          printf 'Choose numbers from 1 to 3.\n'
          continue 2
        fi
        MS_INSTALL_KERNELS+="${MS_INSTALL_KERNELS:+,}${numbered[number - 1]}"
      done
      break
    done
    _install_choice_list MS_INSTALL_KERNELS --kernel '' "${INSTALL_KERNELS[@]}" || return
  fi
  # The performance kernel does not boot on an older CPU.
  if [[ " $MS_INSTALL_KERNELS " == *" linux-mainstream-performance "* ]] && ! cpu_runs_x86_64_v3; then
    printf 'This CPU does not support x86-64-v3, which the performance kernel needs. Using the Mainstream kernel instead.\n' >&2
    kernel=${MS_INSTALL_KERNELS// /,}
    MS_INSTALL_KERNELS=${kernel/linux-mainstream-performance/linux-mainstream}
    _install_choice_list MS_INSTALL_KERNELS --kernel '' "${INSTALL_KERNELS[@]}"
  fi
}

# Swaps each selected app for its native or Flatpak pair so it comes from the
# chosen source; apps without a pair stay as they are.
apply_app_source() {
  local app swapped
  MS_SWAPPED_FLATPAKS=()
  (( ${#MS_SELECTED_APPS[@]} )) || return 0
  # shellcheck source=sdata/lib/app-variants.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/app-variants.sh"
  local APP_VARIANTS_LIST="$REPO_ROOT/sdata/dist-arch/mainstream-extras/app-variants.list"
  # Only a Flatpak swapped in here falls back to its native package if it fails.
  for app in "${MS_SELECTED_APPS[@]}"; do
    swapped=$(app_variant_swap "$MS_INSTALL_APP_SOURCE" "$app")
    [[ $swapped != "$app" && $swapped == *.* ]] && MS_SWAPPED_FLATPAKS+=("$swapped")
  done
  mapfile -t MS_SELECTED_APPS < <(printf '%s\n' "${MS_SELECTED_APPS[@]}" \
    | app_variants_apply "$MS_INSTALL_APP_SOURCE")
}

prepare_install_profile() {
  if [[ -z ${MS_INSTALL_PROFILE:-} ]]; then
    MS_INSTALL_PROFILE=default
    if [[ -t 0 && -t 1 && ${ask:-} != false && ${SKIP_ALLGREETING:-} != true ]]; then
      local choice
      printf '\nChoose what to install\n  1. Default (recommended apps)\n  2. Custom (pick your apps)\n  3. Gaming (starts in Steam)\n  4. OS only\n'
      while true; do
        printf 'Install choice [1]: '
        IFS= read -r choice || return 1
        case "$choice" in
          ''|1) break ;;
          2) MS_INSTALL_PROFILE=custom; break ;;
          3) MS_INSTALL_PROFILE=gaming; break ;;
          4) MS_INSTALL_PROFILE=os-only; break ;;
          *) printf 'Choose 1, 2, 3 or 4.\n' ;;
        esac
      done
    fi
  fi

  OS_ONLY_INSTALL=false
  CONSOLE_MODE_INSTALL=false
  # Only Custom installs make these choices; the other profiles keep their defaults.
  [[ $MS_INSTALL_PROFILE == custom ]] || unset MS_INSTALL_APP_SOURCE MS_INSTALL_KERNELS MS_INSTALL_PROTONS
  MS_MODE_SUFFIX=" · $MS_INSTALL_PROFILE"
  case "$MS_INSTALL_PROFILE" in
    default) ;;
    custom)
      choose_app_source && choose_install_kernel && choose_install_apps && apply_app_source ;;
    gaming) CONSOLE_MODE_INSTALL=true ;;
    os-only) OS_ONLY_INSTALL=true ;;
    *) printf 'Unknown install profile %q. Choose default, custom, gaming or os-only.\n' "$MS_INSTALL_PROFILE" >&2; return 1 ;;
  esac
}
