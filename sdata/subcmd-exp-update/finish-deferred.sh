#!/usr/bin/env bash
# Puts in place the files an update left for after it had finished.
#
# An update run from the Update page of a Settings window from before 3.0.0
# is that window's child, and the window restarts itself as soon as a file it
# was built from changes, which would stop the update partway. exp-update
# leaves those files out and lists them in .update-deferred in the clone (see
# exp_detect_old_settings in 0.run.sh). This waits for that update to end,
# puts them in with exp-update's own per-file step, all at once, and lets the
# shell reload onto the finished tree.
#
# Whichever gets there first puts the list in place:
#   --wait-pid PID --wait-start TICKS
#                 this, started by exp-update outside the update's process
#                 tree; waits for that process (the root helper) to end
#   --login       this, started by hypr/hyprland/execs.lua at login before
#                 the shell starts, for a list nothing got to
#   the next exp-update run, which applies a list it finds before copying
set -u
# Nothing reads this but the log, and the session that started it may end
# while it waits.
trap '' PIPE HUP

_self=$(readlink -f -- "${BASH_SOURCE[0]}") || exit 0
REPO_ROOT=$(cd -- "${_self%/*}/../.." && pwd) || exit 0
cd -- "$REPO_ROOT" || exit 0

wait_pid="" wait_start="" login=0
while (( $# )); do
  case "$1" in
    --wait-pid) wait_pid="${2:-}"; shift; (( $# )) && shift ;;
    --wait-start) wait_start="${2:-}"; shift; (( $# )) && shift ;;
    --login) login=1; shift ;;
    *) shift ;;
  esac
done

[[ -s "${REPO_ROOT}/.update-deferred" ]] || exit 0

# shellcheck source=/dev/null
source "${REPO_ROOT}/sdata/lib/environment-variables.sh" || exit 0
# shellcheck source=/dev/null
source "${REPO_ROOT}/sdata/lib/functions.sh" || exit 0

# The unattended settings updatems runs exp-update with.
FORCE_CHECK=false
CHECK_PACKAGES=false
DRY_RUN=false
VERBOSE=false
SKIP_NOTICE=true
NON_INTERACTIVE=true
DEFAULT_CHOICE=8
SOURCE_ONLY=true
# shellcheck source=/dev/null
source "${REPO_ROOT}/sdata/subcmd-exp-update/0.run.sh" || exit 0
set +e

if [[ ! -t 1 ]]; then
  mkdir -p "${EXP_UPDATE_LOG%/*}" 2>/dev/null
  exec >>"$EXP_UPDATE_LOG" 2>&1
  # Plain text in the log, as the relay leaves exp-update's own lines.
  for _sty in "${!STY_@}"; do printf -v "$_sty" '%s' ''; done
fi

# The update that left the list is over once the process it named has ended.
# Bounded, so a finisher whose update never ends does not wait for good; the
# next login or update then does the work.
if (( ! login )) && [[ -n "$wait_pid" && -n "$wait_start" ]]; then
  for (( i = 0; i < 21600; i++ )); do
    exp_proc_alive "$wait_pid" "$wait_start" || break
    sleep 1
  done
  if exp_proc_alive "$wait_pid" "$wait_start"; then
    log_warning "The update is still running after six hours; leaving its files for the next login"
    exit 0
  fi
  # The Settings window restarts into the new release as soon as these go
  # in, which clears its page. A moment first lets the result it has just
  # printed be read.
  sleep 3
fi
# Headed once the wait is over, so the update's own lines in the log come
# before these rather than around them.
printf '\n== %s finish-deferred%s ==\n' "$(date '+%F %T')" "$( (( login )) && echo ' (login)')"

lock="${REPO_ROOT}/.update-lock"
for (( i = 0; i < 1800; i++ )); do
  [[ -f "$lock" ]] && exp_lock_owner_live "$(cat "$lock" 2>/dev/null)" || break
  # An update is running and applies the list itself before it copies, and
  # the shell must not wait on it at login.
  (( login )) && exit 0
  sleep 1
done
if [[ -f "$lock" ]] && exp_lock_owner_live "$(cat "$lock" 2>/dev/null)"; then
  exit 0
fi
# A later run got to the list first. The shell it held is still the old one in
# memory until let go; one that reports itself not held was started since, and
# one too old to answer is asked only whether it is running.
if [[ ! -s "$EXP_DEFERRED_FILE" ]]; then
  if (( ! login )); then
    _held=$(qs -c ii ipc call updates held 2>/dev/null)
    if [[ "$_held" == true ]] || { [[ "$_held" != false ]] && _qs_live; }; then
      qs_release
    fi
  fi
  exit 0
fi
# Created only when absent, so a run that found the lock free at the same
# moment cannot take it as well.
if [[ -f "$lock" ]] && ! exp_lock_owner_live "$(cat "$lock" 2>/dev/null)"; then
  rm -f "$lock"
fi
( set -o noclobber; echo $$ >"$lock" ) 2>/dev/null || exit 0
trap '[[ "$(cat "$lock" 2>/dev/null)" == "$$" ]] && rm -f "$lock"; exp_discard_staged' EXIT

# The shell is normally still held by the update that left the list. Holding
# it again covers one that was released since, so it reloads once, onto the
# finished tree.
if (( ! login )) && _qs_live && qs -c ii ipc call updates holdReload >/dev/null 2>&1; then
  _qs_held=1
fi

# Migrated before the files that read the new layout go in, so what loads
# them reads it straight away.
if declare -F config_migrations_run >/dev/null 2>&1; then
  config_migrations_run "${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json" || true
fi

load_ignore_patterns
exp_apply_deferred
exp_print_own_changes

if (( ! login )) && _qs_live; then
  qs_release
  _qs_held=0
fi
exit 0
