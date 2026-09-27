# This script is meant to be sourced.
# It's not for directly running.
# shellcheck shell=bash

# Settings > Decorations and the Welcome app save their values into the user's
# copy of hypr/hyprland/general.lua, and the animation style into
# animations/active beside it. Both are also files every release ships, and a
# release that changes one has the user's copy replaced like any other
# conflict, which on its own sends every decoration setting back to stock.
#
# The release being left is in the clone's history at the start of the update
# range. A value that differs from what it shipped is the user's own and goes
# back into the new file; one that matches it takes the new release's value.
# decorations.py makes that call per setting, since it is the one place that
# knows how each is spelled.
#
# Settings > Layouts rides along on the same copies: its default layout sits
# in general.lua and its per-workspace switch in hyprland.lua, and layouts.py
# carries those two the same way. The touchpad gestures in general.lua are
# only a copy of choices kept in config.json, which updates never touch, so
# they are written again from there with gestures.py once general.lua has
# been replaced.
#
# Anything missing along the way (python3, the old file, a reader that fails)
# leaves the update exactly as it would be without this, and quiet about it.
# The functions here return 0 whatever happens, so a caller under errexit
# carries on.

DECO_CARRY_DIR=""
DECO_GESTURES_PENDING=""
DECO_USER_FILES=("${HOME}/.config/hypr/hyprland/general.lua" "${HOME}/.config/hypr/hyprland/animations/active" "${HOME}/.config/hypr/hyprland.lua")

# Where a tree keeps its dotfiles: under dots/, or at the top in the oldest layout.
_deco_carry_prefix() {
  local rev="$1" p
  for p in "dots/" ""; do
    if git -C "$REPO_ROOT" rev-parse -q --verify "${rev}:${p}.config/hypr/hyprland/general.lua" >/dev/null 2>&1; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

# Called before any conflict is settled: sets DECO_CARRY_DIR to a folder with
# what each earlier release shipped, or leaves it empty when there is nothing
# the pass could do.
deco_carry_begin() {
  DECO_CARRY_DIR=""
  [[ "${DRY_RUN:-false}" != true && "${EUID:-0}" -ne 0 ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  [[ -f "${DECO_USER_FILES[0]}" ]] || return 0
  # A linked general.lua is written through by the update's own copy, and
  # the carry would replace the link with a file, so it is left as it is.
  [[ -L "${DECO_USER_FILES[0]}" ]] && return 0
  # Without the new release's reader there is no pass to run, and nothing
  # should promise that the values will stay.
  local reader_prefix=dots/
  [[ -d "${REPO_ROOT}/dots/.config" ]] || reader_prefix=""
  [[ -f "${REPO_ROOT}/${reader_prefix}.config/quickshell/ii/scripts/themes/decorations.py" ]] || return 0
  local head rev tag prefix dir id f n=0
  local -a revs=()
  local -A seen=()
  head=$(git -C "$REPO_ROOT" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) || return 0
  # The same start of the range get_changed_files reads.
  rev=$(git -C "$REPO_ROOT" rev-parse -q --verify 'HEAD@{1}^{commit}' 2>/dev/null) || return 0
  revs+=("$rev")
  # A forced run's HEAD@{1} is trusted when it is an earlier commit of this
  # branch, as on every Edge update, where it is the last applied one. When it
  # is not, it is only where the clone happened to sit: the branch tip after a
  # fresh clone, or a later commit after a downgrade. Then every earlier
  # release is compared as well, and a value is the user's only when none of
  # them shipped it.
  if [[ "${FORCE_CHECK:-false}" == true ]] \
     && { [[ "$rev" == "$head" ]] || ! git -C "$REPO_ROOT" merge-base --is-ancestor "$rev" "$head" 2>/dev/null; }; then
    while IFS= read -r tag; do
      if [[ "$tag" =~ ^[0-9]{1,2}\.[0-9]+\.[0-9]+$ ]]; then revs+=("refs/tags/${tag}"); fi
    done < <(git -C "$REPO_ROOT" tag --merged "$head" --no-contains "$head" 2>/dev/null)
  fi
  dir=$(mktemp -d 2>/dev/null) || return 0
  for rev in "${revs[@]}"; do
    prefix=$(_deco_carry_prefix "$rev") || continue
    # Most releases ship the same files as the one before, and one copy of
    # each distinct set is enough.
    id=""
    for f in hypr/hyprland/general.lua hypr/hyprland/animations/active hypr/hyprland.lua quickshell/ii/scripts/themes/decorations-schema.json; do
      id+="$(git -C "$REPO_ROOT" rev-parse -q --verify "${rev}:${prefix}.config/${f}" 2>/dev/null || echo none):"
    done
    [[ -z "${seen[$id]:-}" ]] || continue
    seen[$id]=1
    f="${dir}/was/$((n + 1))"
    if ! mkdir -p "${f}/animations" 2>/dev/null \
       || ! git -C "$REPO_ROOT" show "${rev}:${prefix}.config/hypr/hyprland/general.lua" >"${f}/general.lua" 2>/dev/null; then
      rm -rf "$f" || true
      continue
    fi
    # The reader finds the style beside general.lua and that release's
    # defaults beside it too, so each copy keeps the same layout.
    git -C "$REPO_ROOT" show "${rev}:${prefix}.config/hypr/hyprland/animations/active" >"${f}/animations/active" 2>/dev/null \
      || rm -f "${f}/animations/active" || true
    git -C "$REPO_ROOT" show "${rev}:${prefix}.config/quickshell/ii/scripts/themes/decorations-schema.json" >"${f}/decorations-schema.json" 2>/dev/null \
      || rm -f "${f}/decorations-schema.json" || true
    git -C "$REPO_ROOT" show "${rev}:${prefix}.config/hypr/hyprland.lua" >"${f}/hyprland.lua" 2>/dev/null \
      || rm -f "${f}/hyprland.lua" || true
    n=$((n + 1))
  done
  if (( n == 0 )) || ! mkdir -p "${dir}/yours/animations" 2>/dev/null; then
    rm -rf "$dir" || true
    return 0
  fi
  DECO_CARRY_DIR="$dir"
  return 0
}

# Called for each file just before a conflict on it is settled. The copy is
# the user's file as it stands at that moment, so the pass puts back what they
# had when it was replaced rather than what they had when the run started.
deco_carry_snapshot() {
  local file="${1:-}" dest
  # The gestures come back from config.json, which needs no copy, so this is
  # noted even when there is no folder to copy into.
  [[ "$file" == "${DECO_USER_FILES[0]}" ]] && DECO_GESTURES_PENDING=1
  [[ -n "$DECO_CARRY_DIR" && -f "$file" ]] || return 0
  case "$file" in
    "${DECO_USER_FILES[0]}") dest="${DECO_CARRY_DIR}/yours/general.lua" ;;
    "${DECO_USER_FILES[1]}") dest="${DECO_CARRY_DIR}/yours/animations/active" ;;
    "${DECO_USER_FILES[2]}") dest="${DECO_CARRY_DIR}/yours/hyprland.lua" ;;
    *) return 0 ;;
  esac
  cp "$file" "$dest" 2>/dev/null || rm -f "$dest" 2>/dev/null || true
  return 0
}

# Called once the conflicts are settled. Puts the user's own values back into
# whatever the update replaced, says which in one line, and removes the copies.
deco_carry_finish() {
  local dir="${DECO_CARRY_DIR:-}" prefix="dots/" py new out="" shown="" i limit=4 layouts="" gestures
  local -a run=(python3) was=() labels=()
  [[ -d "${REPO_ROOT}/dots/.config" ]] || prefix=""
  if command -v timeout >/dev/null 2>&1; then run=(timeout -k 5 20 python3); fi
  # Every general.lua that went through a conflict gets its gestures written
  # again, whether or not there is anything else to carry.
  if [[ -n "${DECO_GESTURES_PENDING:-}" ]]; then
    DECO_GESTURES_PENDING=""
    gestures="${REPO_ROOT}/${prefix}.config/quickshell/ii/scripts/hyprland/gestures.py"
    if [[ "${DRY_RUN:-false}" != true && "${EUID:-0}" -ne 0 && -f "$gestures" \
          && -f "${DECO_USER_FILES[0]}" && ! -L "${DECO_USER_FILES[0]}" ]] \
       && command -v python3 >/dev/null 2>&1; then
      local gestures_rc=0
      "${run[@]}" "$gestures" apply --general "${DECO_USER_FILES[0]}" >/dev/null 2>&1 || gestures_rc=$?
      if (( gestures_rc == 0 )); then
        if declare -F log_info >/dev/null 2>&1; then log_info "Kept your touchpad gestures"; else echo "Kept your touchpad gestures"; fi
      fi
    fi
  fi
  [[ -n "$dir" ]] || return 0
  py="${REPO_ROOT}/${prefix}.config/quickshell/ii/scripts/themes/decorations.py"
  new="${REPO_ROOT}/${prefix}.config/hypr/hyprland/general.lua"
  for i in "${dir}"/was/*/general.lua; do
    if [[ -f "$i" ]]; then was+=("$i"); fi
  done
  # Only a file that went through a conflict has a copy, and a run where
  # neither did has nothing to put back.
  if [[ -f "$py" && -f "$new" ]] && (( ${#was[@]} )) \
     && [[ -f "${dir}/yours/general.lua" || -f "${dir}/yours/animations/active" ]]; then
    # Bounded (see run above): the write waits on the lock the Settings page
    # also takes, and this runs while Hyprland's autoreload is still held off.
    # The new release's reader, so a setting its schema dropped is not carried.
    out=$("${run[@]}" "$py" carry "${DECO_USER_FILES[0]}" "${dir}/yours/general.lua" "$new" "${was[@]}" 2>/dev/null) || out=""
  fi
  py="${REPO_ROOT}/${prefix}.config/quickshell/ii/scripts/hyprland/layouts.py"
  if [[ -f "$py" ]] && (( ${#was[@]} )) \
     && [[ -f "${dir}/yours/general.lua" || -f "${dir}/yours/hyprland.lua" ]]; then
    layouts=$("${run[@]}" "$py" carry "$dir" "${DECO_USER_FILES[0]}" "$new" "${DECO_USER_FILES[2]}" "${REPO_ROOT}/${prefix}.config/hypr/hyprland.lua" 2>/dev/null) || layouts=""
  fi
  # Let go of only once the copies are gone, so a run stopped part-way through
  # this still has them to finish the pass with on its way out.
  rm -rf "$dir" 2>/dev/null || true
  DECO_CARRY_DIR=""
  if [[ -n "$layouts" ]]; then
    layouts="${layouts//$'\n'/, }"
    if declare -F log_info >/dev/null 2>&1; then log_info "Kept your Layouts settings: ${layouts}"; else echo "Kept your Layouts settings: ${layouts}"; fi
  fi
  [[ -n "$out" ]] || return 0
  mapfile -t labels <<<"$out"
  # One short line even for someone who applied a theme, which sets nearly
  # every key: a few names and a count, never "and 1 more".
  if (( ${#labels[@]} <= 5 )); then limit=5; fi
  shown="${labels[0]}"
  for (( i = 1; i < ${#labels[@]} && i < limit; i++ )); do shown+=", ${labels[i]}"; done
  if (( ${#labels[@]} > limit )); then shown+=" and $(( ${#labels[@]} - limit )) more"; fi
  if declare -F log_info >/dev/null 2>&1; then
    log_info "Kept your Decorations settings: ${shown}"
  else
    echo "Kept your Decorations settings: ${shown}"
  fi
  return 0
}

# An exp-update from before this pass read its whole script before its own
# pull brought the pass in, so the update that delivers it would still reset
# the values. That runner sources migrations.sh after the pull and before it
# copies anything, and settles every conflict through handle_file_conflict, so
# migrations.sh puts the pass around that call for the one run. Each call
# finishes its own file straight away: that runner has no step after the copy
# to hang the pass on, and nothing that would clear the copies up later.
deco_carry_wrap_older_runner() {
  declare -F handle_file_conflict >/dev/null 2>&1 || return 0
  declare -F _deco_carry_prior_handle_file_conflict >/dev/null 2>&1 && return 0
  local body
  body=$(declare -f handle_file_conflict 2>/dev/null) || return 0
  eval "_deco_carry_prior_${body}" 2>/dev/null || return 0
  declare -F _deco_carry_prior_handle_file_conflict >/dev/null 2>&1 || return 0
  handle_file_conflict() {
    local _deco_carry_file="" _deco_carry_rc=0
    case "${2:-}" in
      "${DECO_USER_FILES[0]}"|"${DECO_USER_FILES[1]}"|"${DECO_USER_FILES[2]}") _deco_carry_file=1 ;;
    esac
    if [[ -n "$_deco_carry_file" ]]; then
      deco_carry_begin || true
      deco_carry_snapshot "$2" || true
    fi
    # Called plainly, as that runner calls it, so errexit treats a failure
    # inside it exactly as it did before.
    _deco_carry_prior_handle_file_conflict "$@"
    _deco_carry_rc=$?
    if [[ -n "$_deco_carry_file" ]]; then
      deco_carry_finish || true
    fi
    return "$_deco_carry_rc"
  }
  return 0
}
