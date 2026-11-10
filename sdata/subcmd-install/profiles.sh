# shellcheck shell=bash

install_app_catalog() {
  local app id label
  local -a MAINSTREAM_DEFAULT_APPS=()
  source "$REPO_ROOT/sdata/dist-arch/mainstream-extras/default-apps.list"
  for app in "${MAINSTREAM_DEFAULT_APPS[@]}"; do
    IFS='|' read -r id label _ <<< "$app"
    printf '%s\t%s\tdefault\n' "$id" "$label"
  done
  awk '
    /^          - name: / { id = $3 }
    /^            display: "/ {
      label = $0; sub(/^ +display: "/, "", label); sub(/"$/, "", label)
      printf "%s\t%s\toptional\n", id, label
    }
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

  if [[ ${MS_INSTALL_APPS_SET:-false} == true ]]; then
    selected=()
    IFS=, read -ra indexes <<< "$MS_INSTALL_APPS"
    for id in "${indexes[@]}"; do
      if [[ -z $id || ! ${known[$id]:-} ]]; then
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

  MS_SELECTED_APPS=()
  for id in "${ids[@]}"; do
    [[ ! ${selected[$id]:-} ]] || MS_SELECTED_APPS+=("$id")
  done
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
  MS_MODE_SUFFIX=" · $MS_INSTALL_PROFILE"
  case "$MS_INSTALL_PROFILE" in
    default) ;;
    custom) choose_install_apps ;;
    gaming) CONSOLE_MODE_INSTALL=true ;;
    os-only) OS_ONLY_INSTALL=true ;;
    *) printf 'Unknown install profile %q. Choose default, custom, gaming or os-only.\n' "$MS_INSTALL_PROFILE" >&2; return 1 ;;
  esac
}
